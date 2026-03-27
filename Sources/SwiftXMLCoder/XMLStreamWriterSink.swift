import Foundation
import CLibXML2

/// An incremental XML writer that accepts ``XMLStreamEvent`` values one at a time
/// and flushes serialised bytes to a callback.
///
/// `XMLStreamWriterSink` is the streaming building block underneath ``XMLStreamWriter``.
/// Instead of accumulating all output in memory and returning `Data` at the end, the sink
/// drains the libxml2 output buffer to a caller-supplied closure whenever it exceeds
/// a configurable byte threshold.
///
/// ## Usage
///
/// ```swift
/// let sink = try XMLStreamWriterSink(configuration: .init()) { chunk in
///     outputStream.write(chunk)
/// }
/// for event in events {
///     try sink.write(event)
/// }
/// try sink.finish()
/// ```
///
/// - Important: Not thread-safe. Feed events from a single call context.
final class XMLStreamWriterSink {

    // MARK: - Properties

    let configuration: XMLStreamWriter.Configuration
    private let output: (Data) throws -> Void

    /// Minimum bytes in the buffer before an automatic flush. Default 8 KiB.
    private let flushThreshold: Int

    private var buffer: xmlBufferPtr?
    private var writer: xmlTextWriterPtr?
    private var state: XMLStreamWriter.WriteState
    private var finished = false

    // MARK: - Init

    /// Creates a writer sink.
    ///
    /// - Parameters:
    ///   - configuration: Writer options (encoding, pretty-print, limits).
    ///   - flushThreshold: Minimum accumulated bytes before automatic flush. Default `8192`.
    ///   - output: Callback receiving serialised XML data chunks.
    /// - Throws: ``XMLParsingError`` if libxml2 resource allocation fails.
    init(
        configuration: XMLStreamWriter.Configuration = .init(),
        flushThreshold: Int = 8192,
        output: @escaping (Data) throws -> Void
    ) throws {
        self.configuration = configuration
        self.flushThreshold = flushThreshold
        self.output = output
        self.state = XMLStreamWriter.WriteState()

        LibXML2.ensureInitialized()

        guard let buf = xmlBufferCreate() else {
            throw XMLParsingError.documentCreationFailed(message: "xmlBufferCreate failed.")
        }
        self.buffer = buf

        guard let xmlWriter = xmlNewTextWriterMemory(buf, 0) else {
            xmlBufferFree(buf)
            self.buffer = nil
            throw XMLParsingError.documentCreationFailed(message: "xmlNewTextWriterMemory failed.")
        }
        self.writer = xmlWriter

        if configuration.prettyPrinted {
            xmlTextWriterSetIndent(xmlWriter, 1)
            _ = "  ".withXMLChar { xmlTextWriterSetIndentString(xmlWriter, $0) }
        }
    }

    deinit {
        // Free resources if finish() was never called.
        if let activeWriter = writer {
            xmlFreeTextWriter(activeWriter) // also flushes
        }
        // xmlFreeTextWriter frees the associated buffer when using xmlNewTextWriterMemory,
        // so we must NOT call xmlBufferFree here if the writer was still alive.
        // If the writer was already freed (via finish()), buffer was freed there.
    }

    // MARK: - Public API

    /// Writes a single event to the output stream.
    ///
    /// After writing, if the internal buffer exceeds the flush threshold, accumulated
    /// bytes are drained to the output callback.
    func write(_ event: XMLStreamEvent) throws {
        guard let activeWriter = writer, !finished else {
            throw XMLParsingError.parseFailed(
                message: "XMLStreamWriterSink: write called after finish or on failed sink."
            )
        }
        try writeEvent(event, writer: activeWriter, state: &state)
        try flushIfNeeded()
    }

    /// Flushes any remaining bytes and releases libxml2 resources.
    ///
    /// After calling `finish()`, no further `write(_:)` calls are allowed.
    func finish() throws {
        guard !finished else { return }
        finished = true

        if let activeWriter = writer {
            xmlTextWriterFlush(activeWriter)
            try drainBuffer()
            xmlFreeTextWriter(activeWriter)
            writer = nil
            // xmlFreeTextWriter freed the buffer
            buffer = nil
        }
    }

    // MARK: - Buffer management

    private func flushIfNeeded() throws {
        guard let buf = buffer, let activeWriter = writer else { return }
        xmlTextWriterFlush(activeWriter)
        let length = Int(xmlBufferLength(buf))
        if length >= flushThreshold {
            try drainBuffer()
        }
    }

    private func drainBuffer() throws {
        guard let buf = buffer else { return }

        xmlTextWriterFlush(writer!)
        let length = Int(xmlBufferLength(buf))
        guard length > 0, let contentPtr = xmlBufferContent(buf) else { return }

        let data = Data(bytes: UnsafeRawPointer(contentPtr), count: length)

        // Reset the buffer so we don't re-emit the same bytes.
        // xmlBufferEmpty is the API for this.
        xmlBufferEmpty(buf)

        try output(data)
    }
}

// MARK: - Event dispatch (shared with XMLStreamWriter)

extension XMLStreamWriterSink {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func writeEvent(
        _ event: XMLStreamEvent,
        writer: xmlTextWriterPtr,
        state: inout XMLStreamWriter.WriteState
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

            let qualName = name.prefix.map { "\($0):\(name.localName)" } ?? name.localName
            try writerCheck(
                qualName.withXMLChar { xmlTextWriterStartElement(writer, $0) },
                operation: "startElement"
            )

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

    private func checkAndIncrementNodeCount(_ state: inout XMLStreamWriter.WriteState, operation: String) throws {
        state.nodeCount += 1
        guard let maxNodes = configuration.limits.maxNodeCount else { return }
        guard state.nodeCount <= maxNodes else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_2H_MAX_NODE_COUNT] Node count \(state.nodeCount)"
                    + " exceeds limit \(maxNodes). (op=\(operation))"
            )
        }
    }

    private func markParentHasContent(_ state: inout XMLStreamWriter.WriteState) {
        guard !state.elementHasContent.isEmpty else { return }
        state.elementHasContent[state.elementHasContent.count - 1] = true
    }
}
