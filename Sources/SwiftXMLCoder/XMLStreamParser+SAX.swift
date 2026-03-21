import Foundation
import Logging
import CLibXML2
import XMLCoderCompatibility

// MARK: - SAX Implementation
//
// Architecture:
//   parseSAX(data:onEvent:)
//     → creates SAXContext (holds closure + state + limits)
//     → zero-inits xmlSAXHandler, assigns local @convention(c) callbacks
//     → xmlSAXUserParseMemory(&handler, ctxPtr, bytes, len) — drives SAX parse
//     → each C callback retrieves SAXContext via Unmanaged, calls onEvent
//     → on limit violation: sets ctx.error (libxml2 terminates after error)
//     → after parse: re-throws ctx.error if set; otherwise checks return code
//
// C callback bridging:
//   Unmanaged<SAXContext>.passRetained → opaque pointer → passed as SAX user data
//   Each callback uses Unmanaged.fromOpaque to retrieve the Swift object (no ARC cost).
//
//   The SAX callbacks are defined as local let constants inside parseSAX rather than
//   module-level globals. They are non-capturing closures (all context flows through
//   the SAX userCtx parameter), so they remain valid C function pointers on all Swift
//   versions. This avoids nonisolated(unsafe), which requires Swift 5.10+.
//
// Note on errorSAXFunc: libxml2's error/fatalError SAX fields use a variadic C typedef
// which Swift imports as OpaquePointer and cannot be assigned a Swift closure.
// Instead, we rely on xmlGetLastError() after xmlSAXUserParseMemory returns non-zero.

// MARK: - SAXContext

final class SAXContext {
    // onEvent is stored @escaping but only lives for the duration of parseSAX.
    // withoutActuallyEscaping is used at the call site to bridge non-escaping → escaping.
    let onEvent: (XMLStreamEvent) -> Void
    var error: XMLParsingError?
    var depth: Int = 0
    var nodeCount: Int = 0
    var warnedDepthApproaching: Bool = false
    var warnedNodeCountApproaching: Bool = false
    let limits: XMLTreeParser.Limits
    let whitespacePolicy: XMLTreeParser.WhitespaceTextNodePolicy
    var logger: Logger

    init(
        onEvent: @escaping (XMLStreamEvent) -> Void,
        limits: XMLTreeParser.Limits,
        whitespacePolicy: XMLTreeParser.WhitespaceTextNodePolicy,
        logger: Logger
    ) {
        self.onEvent = onEvent
        self.limits = limits
        self.whitespacePolicy = whitespacePolicy
        self.logger = logger
    }
}

// MARK: - parseSAX entry point

extension XMLStreamParser {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func parseSAX(data: Data, onEvent: (XMLStreamEvent) -> Void) throws {
        try ensureLimitSAX(
            actual: data.count,
            limit: configuration.limits.maxInputBytes,
            code: "XML6_2H_MAX_INPUT_BYTES",
            context: "XML input bytes"
        )

        var logger = configuration.logger
        logger[metadataKey: "component"] = "XMLStreamParser"

        // withoutActuallyEscaping is safe: SAXContext + Unmanaged ref are released
        // before this function returns (defer below), so onEvent never truly escapes.
        try withoutActuallyEscaping(onEvent) { escapingOnEvent in
            let ctx = SAXContext(
                onEvent: escapingOnEvent,
                limits: configuration.limits,
                whitespacePolicy: configuration.whitespaceTextNodePolicy,
                logger: logger
            )

            let unmanaged = Unmanaged.passRetained(ctx)
            defer { unmanaged.release() }
            let ctxPtr = unmanaged.toOpaque()

            var handler = xmlSAXHandler()
            handler.initialized = UInt32(XML_SAX2_MAGIC)

            // SAX callbacks — local non-capturing closures, valid C function pointers.
            handler.startDocument = { userCtx in
                guard let ctx = saxContext(from: userCtx) else { return }
                ctx.onEvent(.startDocument(version: nil, encoding: nil, standalone: nil))
            }
            handler.endDocument = { userCtx in
                guard let ctx = saxContext(from: userCtx) else { return }
                ctx.onEvent(.endDocument)
            }
            // swiftlint:disable closure_parameter_position
            handler.startElementNs = {
                userCtx, localname, prefix, URI,
                nbNamespaces, namespaces,
                nbAttributes, nbDefaulted, attributes in
            // swiftlint:enable closure_parameter_position
                guard let ctx = saxContext(from: userCtx) else { return }
                guard ctx.error == nil else { return }
                ctx.depth += 1
                let maxDepth = ctx.limits.maxDepth
                if ctx.depth > maxDepth {
                    ctx.error = XMLParsingError.parseFailed(
                        message: "[XML6_2H_MAX_DEPTH] Element nesting depth \(ctx.depth) exceeds limit \(maxDepth)."
                    )
                    return
                }
                if !ctx.warnedDepthApproaching && ctx.depth > maxDepth * 4 / 5 {
                    ctx.warnedDepthApproaching = true
                    ctx.logger.warning("XML stream depth approaching limit",
                                       metadata: ["depth": "\(ctx.depth)", "limit": "\(maxDepth)"])
                }
                if incrementAndCheckNodeCount(ctx: ctx) { return }
                let name = saxQName(localname: localname, prefix: prefix, uri: URI)
                var nsDeclarations: [XMLNamespaceDeclaration] = []
                if let namespaces = namespaces, nbNamespaces > 0 {
                    for nsIdx in 0..<Int(nbNamespaces) {
                        let pfx = saxString(from: namespaces[nsIdx * 2])
                        let uri = saxString(from: namespaces[nsIdx * 2 + 1]) ?? ""
                        nsDeclarations.append(XMLNamespaceDeclaration(prefix: pfx, uri: uri))
                    }
                }
                var attrs: [XMLTreeAttribute] = []
                let totalAttrs = Int(nbAttributes) + Int(nbDefaulted)
                if let attributes = attributes, totalAttrs > 0 {
                    if let maxAttrs = ctx.limits.maxAttributesPerElement, totalAttrs > maxAttrs {
                        ctx.error = XMLParsingError.parseFailed(
                            message: "[XML6_2H_MAX_ATTRS] Attribute count \(totalAttrs) exceeds limit \(maxAttrs)."
                        )
                        return
                    }
                    for attrIdx in 0..<totalAttrs {
                        let base = attrIdx * 5
                        let attrName = saxQName(
                            localname: attributes[base],
                            prefix: attributes[base + 1],
                            uri: attributes[base + 2]
                        )
                        let valueStart = attributes[base + 3]
                        let valueEnd = attributes[base + 4]
                        let value: String
                        if let beginPtr = valueStart, let endPtr = valueEnd, endPtr >= beginPtr {
                            let len = endPtr - beginPtr
                            value = String(bytes: UnsafeBufferPointer(start: beginPtr, count: len),
                                           encoding: .utf8) ?? ""
                        } else {
                            value = ""
                        }
                        attrs.append(XMLTreeAttribute(name: attrName, value: value))
                    }
                }
                ctx.onEvent(.startElement(name: name, attributes: attrs, namespaceDeclarations: nsDeclarations))
            }
            // swiftlint:disable closure_parameter_position
            handler.endElementNs = {
                userCtx, localname, prefix, URI in
            // swiftlint:enable closure_parameter_position
                guard let ctx = saxContext(from: userCtx) else { return }
                guard ctx.error == nil else { return }
                ctx.depth -= 1
                ctx.onEvent(.endElement(name: saxQName(localname: localname, prefix: prefix, uri: URI)))
            }
            handler.characters = { userCtx, chars, len in
                guard let ctx = saxContext(from: userCtx), let chars = chars else { return }
                guard ctx.error == nil else { return }
                let byteCount = Int(len)
                if checkByteLimit(byteCount, limit: ctx.limits.maxTextNodeBytes,
                                  code: "XML6_2H_MAX_TEXT_NODE_BYTES", ctx: ctx) { return }
                guard let raw = String(bytes: UnsafeBufferPointer(start: chars, count: byteCount),
                                       encoding: .utf8) else { return }
                let text: String
                switch ctx.whitespacePolicy {
                case .preserve:
                    text = raw
                case .dropWhitespaceOnly:
                    guard !raw.allSatisfy(\.isWhitespace) else { return }
                    text = raw
                case .trim:
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    text = trimmed
                case .normalizeAndTrim:
                    let trimmed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    guard !trimmed.isEmpty else { return }
                    text = trimmed
                }
                if incrementAndCheckNodeCount(ctx: ctx) { return }
                ctx.onEvent(.text(text))
            }
            handler.cdataBlock = { userCtx, value, len in
                guard let ctx = saxContext(from: userCtx), let value = value else { return }
                guard ctx.error == nil else { return }
                let byteCount = Int(len)
                if checkByteLimit(byteCount, limit: ctx.limits.maxCDATABlockBytes,
                                  code: "XML6_2H_MAX_CDATA_BYTES", ctx: ctx) { return }
                guard let text = String(bytes: UnsafeBufferPointer(start: value, count: byteCount),
                                        encoding: .utf8) else { return }
                if incrementAndCheckNodeCount(ctx: ctx) { return }
                ctx.onEvent(.cdata(text))
            }
            handler.comment = { userCtx, value in
                guard let ctx = saxContext(from: userCtx) else { return }
                guard ctx.error == nil else { return }
                let text = saxString(from: value) ?? ""
                let byteCount = text.utf8.count
                if checkByteLimit(byteCount, limit: ctx.limits.maxCommentBytes,
                                  code: "XML6_2H_MAX_COMMENT_BYTES", ctx: ctx) { return }
                if incrementAndCheckNodeCount(ctx: ctx) { return }
                ctx.onEvent(.comment(text))
            }
            // swiftlint:disable closure_parameter_position
            handler.processingInstruction = {
                userCtx, target, data in
            // swiftlint:enable closure_parameter_position
                guard let ctx = saxContext(from: userCtx) else { return }
                guard ctx.error == nil else { return }
                ctx.onEvent(.processingInstruction(
                    target: saxString(from: target) ?? "",
                    data: saxString(from: data)
                ))
            }
            // handler.error / handler.fatalError: variadic C typedefs — not assignable
            // from Swift. Parse errors are captured via xmlGetLastError() below.

            let parseResult: Int32 = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return xmlSAXUserParseMemory(
                    &handler,
                    ctxPtr,
                    base.assumingMemoryBound(to: CChar.self),
                    Int32(raw.count)
                )
            }

            if let error = ctx.error {
                throw error
            }
            if parseResult != 0 {
                // Best-effort: retrieve libxml2's last error message.
                let message: String?
                if let errPtr = xmlGetLastError(), let msgPtr = errPtr.pointee.message {
                    message = String(cString: msgPtr).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    message = nil
                }
                throw XMLParsingError.parseFailed(
                    message: message ?? "libxml2 SAX parse returned error code \(parseResult)."
                )
            }
        }
    }

    private func ensureLimitSAX(actual: Int, limit: Int?, code: String, context: String) throws {
        guard let limit = limit else { return }
        guard actual <= limit else {
            configuration.logger.warning(
                "XML stream parse limit exceeded",
                metadata: [
                    "code": "\(code)",
                    "context": "\(context)",
                    "actual": "\(actual)",
                    "limit": "\(limit)"
                ]
            )
            throw XMLParsingError.parseFailed(
                message: "[\(code)] Limit exceeded: \(context) = \(actual), limit = \(limit)."
            )
        }
    }
}

// MARK: - Helper: retrieve SAXContext from opaque pointer

private func saxContext(from ptr: UnsafeMutableRawPointer?) -> SAXContext? {
    guard let ptr = ptr else { return nil }
    return Unmanaged<SAXContext>.fromOpaque(ptr).takeUnretainedValue()
}

// MARK: - Byte-limit helper

private func checkByteLimit(
    _ bytes: Int,
    limit: Int?,
    code: String,
    ctx: SAXContext
) -> Bool {
    guard let limit = limit, bytes > limit else { return false }
    ctx.error = XMLParsingError.parseFailed(
        message: "[\(code)] Content size \(bytes) bytes exceeds limit \(limit) bytes."
    )
    return true
}

// MARK: - Node-count helper

private func incrementAndCheckNodeCount(ctx: SAXContext) -> Bool {
    ctx.nodeCount += 1
    guard let maxNodes = ctx.limits.maxNodeCount else { return false }
    if ctx.nodeCount > maxNodes {
        ctx.error = XMLParsingError.parseFailed(
            message: "[XML6_2H_MAX_NODE_COUNT] Node count \(ctx.nodeCount) exceeds limit \(maxNodes)."
        )
        return true
    }
    if !ctx.warnedNodeCountApproaching && ctx.nodeCount > maxNodes * 4 / 5 {
        ctx.warnedNodeCountApproaching = true
        ctx.logger.warning("XML stream node count approaching limit",
                           metadata: ["nodeCount": "\(ctx.nodeCount)", "limit": "\(maxNodes)"])
    }
    return false
}

// MARK: - String helpers

private func saxString(from ptr: UnsafePointer<xmlChar>?) -> String? {
    guard let ptr = ptr else { return nil }
    return String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
}

private func saxString(from ptr: UnsafePointer<xmlChar>?, length: Int32) -> String? {
    guard let ptr = ptr, length > 0 else { return nil }
    return String(bytes: UnsafeBufferPointer(start: ptr, count: Int(length)), encoding: .utf8)
}

private func saxQName(
    localname: UnsafePointer<xmlChar>?,
    prefix: UnsafePointer<xmlChar>?,
    uri: UnsafePointer<xmlChar>?
) -> XMLQualifiedName {
    XMLQualifiedName(
        localName: saxString(from: localname) ?? "",
        namespaceURI: saxString(from: uri),
        prefix: saxString(from: prefix)
    )
}

