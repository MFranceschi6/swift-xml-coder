import Foundation
import CLibXML2
import XMLCoderCompatibility

// MARK: - XMLStreamWriter internal implementation
//
// writeImpl(_ events:) creates an xmlTextWriter backed by an in-memory buffer,
// iterates the events, and maps each to the corresponding xmlTextWriter API call.
//
// C string bridging:
//   All String → xmlChar* conversions use .withXMLChar { } or .withOptionalXMLChar { }
//   so that the C pointers are only valid within their respective closures.
//   xmlChar is `unsigned char` (UInt8); CChar is `signed char` (Int8).
//   The cast via OpaquePointer is safe — the underlying bytes are the same UTF-8 content.

extension XMLStreamWriter {

    // MARK: - WriteState

    struct WriteState {
        var depth: Int = 0
        var nodeCount: Int = 0
        // Stack tracking whether each open element has received content.
        // Used to implement expandEmptyElements.
        var elementHasContent: [Bool] = []
    }

    // MARK: - writeImpl

    func writeImpl<S: Sequence>(_ events: S) throws -> Data where S.Element == XMLStreamEvent {
        LibXML2.ensureInitialized()

        let buf = xmlBufferCreate()
        guard let buf = buf else {
            throw XMLParsingError.documentCreationFailed(message: "xmlBufferCreate failed.")
        }
        defer { xmlBufferFree(buf) }

        let writer = xmlNewTextWriterMemory(buf, 0)
        guard let writer = writer else {
            throw XMLParsingError.documentCreationFailed(message: "xmlNewTextWriterMemory failed.")
        }
        defer { xmlFreeTextWriter(writer) }

        if configuration.prettyPrinted {
            xmlTextWriterSetIndent(writer, 1)
            _ = "  ".withXMLChar { xmlTextWriterSetIndentString(writer, $0) }
        }

        var state = WriteState()

        for event in events {
            try writeEvent(event, writer: writer, state: &state)
        }

        // Flush and extract bytes
        xmlTextWriterFlush(writer)
        let length = xmlBufferLength(buf)
        guard length > 0, let contentPtr = xmlBufferContent(buf) else {
            return Data()
        }

        let byteCount = Int(length)
        if let maxBytes = configuration.limits.maxOutputBytes, byteCount > maxBytes {
            throw XMLParsingError.parseFailed(
                message: "[XML6_2H_MAX_OUTPUT_BYTES] Output size \(byteCount) bytes exceeds limit \(maxBytes) bytes."
            )
        }

        return Data(bytes: UnsafeRawPointer(contentPtr), count: byteCount)
    }

    // MARK: - Per-event dispatch

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func writeEvent(
        _ event: XMLStreamEvent,
        writer: xmlTextWriterPtr,
        state: inout WriteState
    ) throws {
        switch event {

        case .startDocument(let version, let encoding, let standalone):
            let ver = version ?? "1.0"
            let enc = encoding ?? configuration.encoding
            // swiftlint:disable:next identifier_name
            let rc: Int32 = ver.withCString { verPtr in
                enc.withCString { encPtr in
                    if let standaloneDecl = standalone {
                        return (standaloneDecl ? "yes" : "no").withCString { saPtr in
                            xmlTextWriterStartDocument(writer, verPtr, encPtr, saPtr)
                        }
                    } else {
                        return xmlTextWriterStartDocument(writer, verPtr, encPtr, nil)
                    }
                }
            }
            try writerCheck(rc, operation: "startDocument")

        case .endDocument:
            try writerCheck(xmlTextWriterEndDocument(writer), operation: "endDocument")

        case .startElement(let name, let attrs, let nsDeclarations):
            try checkDepth(state.depth, operation: "startElement")
            try checkAndIncrementNodeCount(&state, operation: "startElement")

            if !state.elementHasContent.isEmpty {
                state.elementHasContent[state.elementHasContent.count - 1] = true
            }
            state.depth += 1
            state.elementHasContent.append(false)

            // Use non-NS xmlTextWriterStartElement with qualified name (prefix:localName).
            // This avoids libxml2 auto-emitting namespace declarations that would conflict
            // with the explicit xmlns:* attributes we write below.
            let qualName = name.prefix.map { "\($0):\(name.localName)" } ?? name.localName
            try writerCheck(
                qualName.withXMLChar { xmlTextWriterStartElement(writer, $0) },
                operation: "startElement"
            )

            // Namespace declarations as xmlns[:prefix]="uri" attributes
            for nsDecl in nsDeclarations {
                let attrName = nsDecl.prefix.map { "xmlns:\($0)" } ?? "xmlns"
                // swiftlint:disable:next identifier_name
                let rc: Int32 = attrName.withXMLChar { namePtr in
                    nsDecl.uri.withXMLChar { uriPtr in
                        xmlTextWriterWriteAttribute(writer, namePtr, uriPtr)
                    }
                }
                try writerCheck(rc, operation: "writeNamespaceDeclaration")
            }

            // Element attributes — use qualified name (prefix:localName)
            for attr in attrs {
                let attrQName = attr.name.prefix.map { "\($0):\(attr.name.localName)" } ?? attr.name.localName
                // swiftlint:disable:next identifier_name
                let rc: Int32 = attrQName.withXMLChar { namePtr in
                    attr.value.withXMLChar { valPtr in
                        xmlTextWriterWriteAttribute(writer, namePtr, valPtr)
                    }
                }
                try writerCheck(rc, operation: "writeAttribute")
            }

        case .endElement:
            if configuration.expandEmptyElements,
               let last = state.elementHasContent.last, !last {
                try writerCheck(
                    "".withXMLChar { xmlTextWriterWriteString(writer, $0) },
                    operation: "expandEmptyElement"
                )
            }
            state.elementHasContent.removeLast()
            state.depth -= 1
            try writerCheck(xmlTextWriterEndElement(writer), operation: "endElement")

        case .text(let str):
            let byteCount = str.utf8.count
            if let maxBytes = configuration.limits.maxTextNodeBytes, byteCount > maxBytes {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_2H_MAX_TEXT_NODE_BYTES] Text node \(byteCount) bytes"
                        + " exceeds limit \(maxBytes) bytes."
                )
            }
            try checkAndIncrementNodeCount(&state, operation: "text")
            markParentHasContent(&state)
            try writerCheck(
                str.withXMLChar { xmlTextWriterWriteString(writer, $0) },
                operation: "writeString"
            )

        case .cdata(let str):
            let byteCount = str.utf8.count
            if let maxBytes = configuration.limits.maxCDATABlockBytes, byteCount > maxBytes {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_2H_MAX_CDATA_BYTES] CDATA block \(byteCount) bytes exceeds limit \(maxBytes) bytes."
                )
            }
            try checkAndIncrementNodeCount(&state, operation: "cdata")
            markParentHasContent(&state)
            try writerCheck(
                str.withXMLChar { xmlTextWriterWriteCDATA(writer, $0) },
                operation: "writeCDATA"
            )

        case .comment(let str):
            let byteCount = str.utf8.count
            if let maxBytes = configuration.limits.maxCommentBytes, byteCount > maxBytes {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_2H_MAX_COMMENT_BYTES] Comment \(byteCount) bytes exceeds limit \(maxBytes) bytes."
                )
            }
            try checkAndIncrementNodeCount(&state, operation: "comment")
            markParentHasContent(&state)
            try writerCheck(
                str.withXMLChar { xmlTextWriterWriteComment(writer, $0) },
                operation: "writeComment"
            )

        case .processingInstruction(let target, let data):
            try checkAndIncrementNodeCount(&state, operation: "processingInstruction")
            markParentHasContent(&state)
            // swiftlint:disable:next identifier_name
            let rc: Int32 = target.withXMLChar { tgtPtr in
                data.withOptionalXMLChar { dataPtr in
                    xmlTextWriterWritePI(writer, tgtPtr, dataPtr)
                }
            }
            try writerCheck(rc, operation: "writeProcessingInstruction")
        }
    }

    // MARK: - Limit/check helpers

    private func writerCheck(_ returnCode: Int32, operation: String) throws {
        guard returnCode >= 0 else {
            throw XMLParsingError.parseFailed(
                message: "xmlTextWriter operation '\(operation)' failed (rc=\(returnCode))."
            )
        }
    }

    private func checkDepth(_ depth: Int, operation: String) throws {
        guard let maxDepth = configuration.limits.maxDepth else { return }
        guard depth < maxDepth else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_2H_MAX_DEPTH] Nesting depth \(depth + 1) exceeds limit \(maxDepth). (op=\(operation))"
            )
        }
    }

    private func checkAndIncrementNodeCount(_ state: inout WriteState, operation: String) throws {
        state.nodeCount += 1
        guard let maxNodes = configuration.limits.maxNodeCount else { return }
        guard state.nodeCount <= maxNodes else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_2H_MAX_NODE_COUNT] Node count \(state.nodeCount)"
                    + " exceeds limit \(maxNodes). (op=\(operation))"
            )
        }
    }

    private func markParentHasContent(_ state: inout WriteState) {
        guard !state.elementHasContent.isEmpty else { return }
        state.elementHasContent[state.elementHasContent.count - 1] = true
    }
}

// MARK: - String → xmlChar* bridging helpers

extension String {
    /// Calls `body` with a temporary `UnsafePointer<xmlChar>` to the UTF-8 bytes.
    /// The pointer is only valid for the duration of `body`.
    func withXMLChar<R>(_ body: (UnsafePointer<xmlChar>) -> R) -> R {
        withCString { cStr in
            body(UnsafePointer<xmlChar>(OpaquePointer(cStr)))
        }
    }
}

extension Optional where Wrapped == String {
    /// Calls `body` with either a valid `UnsafePointer<xmlChar>` or `nil`.
    func withOptionalXMLChar<R>(_ body: (UnsafePointer<xmlChar>?) -> R) -> R {
        if let str = self {
            return str.withXMLChar { body($0) }
        } else {
            return body(nil)
        }
    }
}
