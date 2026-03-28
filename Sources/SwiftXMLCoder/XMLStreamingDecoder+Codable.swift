// swiftlint:disable file_length large_tuple
import Foundation
import Logging
import CLibXML2
import XMLCoderCompatibility

final class _XMLStreamingParserSessionContext {
    var error: XMLParsingError?
    var depth: Int = 0
    var nodeCount: Int = 0
    var warnedDepthApproaching: Bool = false
    var warnedNodeCountApproaching: Bool = false
    let limits: XMLTreeParser.Limits
    let whitespacePolicy: XMLTreeParser.WhitespaceTextNodePolicy
    var logger: Logger
    var parserCtxt: xmlParserCtxtPtr?
    var attributeBuffer: [XMLTreeAttribute] = []
    var namespaceDeclarationBuffer: [XMLNamespaceDeclaration] = []
    let enforceNodeCountLimit: Bool
    let enforceAttributeLimit: Bool
    let enforceTextNodeLimit: Bool
    let enforceCDATALimit: Bool
    let enforceCommentLimit: Bool

    private var queue: ContiguousArray<XMLStreamEvent> = []
    private var queueIndex: Int = 0

    init(
        limits: XMLTreeParser.Limits,
        whitespacePolicy: XMLTreeParser.WhitespaceTextNodePolicy,
        logger: Logger
    ) {
        self.limits = limits
        self.whitespacePolicy = whitespacePolicy
        self.logger = logger
        self.enforceNodeCountLimit = limits.maxNodeCount != nil
        self.enforceAttributeLimit = limits.maxAttributesPerElement != nil
        self.enforceTextNodeLimit = limits.maxTextNodeBytes != nil
        self.enforceCDATALimit = limits.maxCDATABlockBytes != nil
        self.enforceCommentLimit = limits.maxCommentBytes != nil
    }

    func enqueue(_ event: XMLStreamEvent) {
        queue.append(event)
    }

    func dequeue() -> XMLStreamEvent? {
        guard queueIndex < queue.count else { return nil }
        defer {
            queueIndex += 1
            if queueIndex >= 1024, queueIndex * 2 > queue.count {
                queue.removeFirst(queueIndex)
                queueIndex = 0
            }
        }
        return queue[queueIndex]
    }

    func peek() -> XMLStreamEvent? {
        guard queueIndex < queue.count else { return nil }
        return queue[queueIndex]
    }

    var hasQueuedEvents: Bool {
        queueIndex < queue.count
    }
}

final class _XMLStreamingParserSession {
    private static let chunkSize = 32 * 1024

    private let data: Data
    private let configuration: XMLTreeParser.Configuration
    private var parserCtxt: xmlParserCtxtPtr?
    private var unmanagedContext: Unmanaged<_XMLStreamingParserSessionContext>?
    private var context: _XMLStreamingParserSessionContext?

    private var offset: Int = 0
    private var didFinalizeChunk: Bool = false
    private var didReachEOF: Bool = false
    /// Monotonically increasing counter for events consumed via nextEvent().
    /// Used as an index into lazyLineTable for error-path line resolution.
    private(set) var eventCounter: Int = 0

    /// Shared lazy line table — re-parses the original data only on first error-formatting access.
    private(set) lazy var lazyLineTable: _LazyLineTable = _LazyLineTable(
        data: data,
        parserConfig: configuration
    )

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    init(data: Data, configuration: XMLTreeParser.Configuration) throws {
        self.data = data
        self.configuration = configuration

        try _xmlStreamingEnsureLimit(
            actual: data.count,
            limit: configuration.limits.maxInputBytes,
            code: "XML6_2H_MAX_INPUT_BYTES",
            context: "XML input bytes",
            logger: configuration.logger
        )

        var logger = configuration.logger
        logger[metadataKey: "component"] = "XMLDecoderStreamingSession"
        let context = _XMLStreamingParserSessionContext(
            limits: configuration.limits,
            whitespacePolicy: configuration.whitespaceTextNodePolicy,
            logger: logger
        )
        let unmanaged = Unmanaged.passRetained(context)
        let ctxPtr = unmanaged.toOpaque()

        var handler = xmlSAXHandler()
        handler.initialized = UInt32(XML_SAX2_MAGIC)

        handler.startDocument = { userCtx in
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
            ctx.enqueue(.startDocument(version: nil, encoding: nil, standalone: nil))
        }
        handler.endDocument = { userCtx in
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
            ctx.enqueue(.endDocument)
        }
        // swiftlint:disable closure_parameter_position
        handler.startElementNs = {
            userCtx, localname, prefix, URI,
            nbNamespaces, namespaces,
            nbAttributes, nbDefaulted, attributes in
        // swiftlint:enable closure_parameter_position
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
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
                ctx.logger.warning(
                    "XML stream depth approaching limit",
                    metadata: ["depth": "\(ctx.depth)", "limit": "\(maxDepth)"]
                )
            }
            if ctx.enforceNodeCountLimit, _xmlStreamingIncrementAndCheckNodeCount(ctx: ctx) { return }
            let name = _xmlStreamingQName(localname: localname, prefix: prefix, uri: URI)

            ctx.namespaceDeclarationBuffer.removeAll(keepingCapacity: true)
            if let namespaces = namespaces, nbNamespaces > 0 {
                for nsIdx in 0..<Int(nbNamespaces) {
                    let pfx = _xmlStreamingString(from: namespaces[nsIdx * 2])
                    let uri = _xmlStreamingString(from: namespaces[nsIdx * 2 + 1]) ?? ""
                    ctx.namespaceDeclarationBuffer.append(XMLNamespaceDeclaration(prefix: pfx, uri: uri))
                }
            }

            ctx.attributeBuffer.removeAll(keepingCapacity: true)
            let totalAttrs = Int(nbAttributes) + Int(nbDefaulted)
            if let attributes = attributes, totalAttrs > 0 {
                if ctx.enforceAttributeLimit, let maxAttrs = ctx.limits.maxAttributesPerElement, totalAttrs > maxAttrs {
                    ctx.error = XMLParsingError.parseFailed(
                        message: "[XML6_2H_MAX_ATTRS] Attribute count \(totalAttrs) exceeds limit \(maxAttrs)."
                    )
                    return
                }
                for attrIdx in 0..<totalAttrs {
                    let base = attrIdx * 5
                    let attrName = _xmlStreamingQName(
                        localname: attributes[base],
                        prefix: attributes[base + 1],
                        uri: attributes[base + 2]
                    )
                    let valueStart = attributes[base + 3]
                    let valueEnd = attributes[base + 4]
                    let value: String
                    if let beginPtr = valueStart, let endPtr = valueEnd, endPtr >= beginPtr {
                        let len = endPtr - beginPtr
                        value = String(
                            bytes: UnsafeBufferPointer(start: beginPtr, count: len),
                            encoding: .utf8
                        ) ?? ""
                    } else {
                        value = ""
                    }
                    ctx.attributeBuffer.append(XMLTreeAttribute(name: attrName, value: value))
                }
            }

            ctx.enqueue(
                .startElement(
                    name: name,
                    attributes: ctx.attributeBuffer,
                    namespaceDeclarations: ctx.namespaceDeclarationBuffer
                )
            )
        }
        // swiftlint:disable closure_parameter_position
        handler.endElementNs = { userCtx, localname, prefix, URI in
        // swiftlint:enable closure_parameter_position
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
            guard ctx.error == nil else { return }
            ctx.depth -= 1
            ctx.enqueue(.endElement(name: _xmlStreamingQName(localname: localname, prefix: prefix, uri: URI)))
        }
        handler.characters = { userCtx, chars, len in
            guard let ctx = _xmlStreamingContext(from: userCtx), let chars = chars else { return }
            guard ctx.error == nil else { return }
            let byteCount = Int(len)
            if ctx.enforceTextNodeLimit,
               _xmlStreamingCheckByteLimit(
                byteCount,
                limit: ctx.limits.maxTextNodeBytes,
                code: "XML6_2H_MAX_TEXT_NODE_BYTES",
                ctx: ctx
               ) {
                return
            }

            guard let raw = String(
                bytes: UnsafeBufferPointer(start: chars, count: byteCount),
                encoding: .utf8
            ) else { return }

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

            if ctx.enforceNodeCountLimit, _xmlStreamingIncrementAndCheckNodeCount(ctx: ctx) { return }
            ctx.enqueue(.text(text))
        }
        handler.cdataBlock = { userCtx, value, len in
            guard let ctx = _xmlStreamingContext(from: userCtx), let value = value else { return }
            guard ctx.error == nil else { return }
            let byteCount = Int(len)
            if ctx.enforceCDATALimit,
               _xmlStreamingCheckByteLimit(
                byteCount,
                limit: ctx.limits.maxCDATABlockBytes,
                code: "XML6_2H_MAX_CDATA_BYTES",
                ctx: ctx
               ) {
                return
            }
            guard let text = String(
                bytes: UnsafeBufferPointer(start: value, count: byteCount),
                encoding: .utf8
            ) else { return }
            if ctx.enforceNodeCountLimit, _xmlStreamingIncrementAndCheckNodeCount(ctx: ctx) { return }
            ctx.enqueue(.cdata(text))
        }
        handler.comment = { userCtx, value in
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
            guard ctx.error == nil else { return }
            let text = _xmlStreamingString(from: value) ?? ""
            let byteCount = text.utf8.count
            if ctx.enforceCommentLimit,
               _xmlStreamingCheckByteLimit(
                byteCount,
                limit: ctx.limits.maxCommentBytes,
                code: "XML6_2H_MAX_COMMENT_BYTES",
                ctx: ctx
               ) {
                return
            }
            if ctx.enforceNodeCountLimit, _xmlStreamingIncrementAndCheckNodeCount(ctx: ctx) { return }
            ctx.enqueue(.comment(text))
        }
        // swiftlint:disable closure_parameter_position
        handler.processingInstruction = { userCtx, target, data in
        // swiftlint:enable closure_parameter_position
            guard let ctx = _xmlStreamingContext(from: userCtx) else { return }
            guard ctx.error == nil else { return }
            if ctx.enforceNodeCountLimit, _xmlStreamingIncrementAndCheckNodeCount(ctx: ctx) { return }
            ctx.enqueue(
                .processingInstruction(
                    target: _xmlStreamingString(from: target) ?? "",
                    data: _xmlStreamingString(from: data)
                )
            )
        }

        guard let parserCtxt = xmlCreatePushParserCtxt(&handler, ctxPtr, nil, 0, nil) else {
            unmanaged.release()
            throw XMLParsingError.parseFailed(message: "Failed to create libxml2 SAX push parser context.")
        }

        _ = xmlCtxtUseOptions(parserCtxt, configuration.parsingConfiguration.libxmlOptions)
        xmlResetLastError()

        self.parserCtxt = parserCtxt
        self.unmanagedContext = unmanaged
        self.context = context
        context.parserCtxt = parserCtxt
    }

    deinit {
        if let parserCtxt = parserCtxt {
            xmlFreeParserCtxt(parserCtxt)
            self.parserCtxt = nil
        }
        context?.parserCtxt = nil
        unmanagedContext?.release()
        unmanagedContext = nil
        context = nil
    }

    func nextEvent() throws -> XMLStreamEvent? {
        if let error = context?.error { throw error }
        if let event = context?.dequeue() { eventCounter += 1; return event }

        while true {
            guard !didReachEOF else {
                if let event = context?.dequeue() { eventCounter += 1; return event }
                return nil
            }
            try pump()
            if let error = context?.error { throw error }
            if let event = context?.dequeue() { eventCounter += 1; return event }
        }
    }

    /// Peek at the next event without consuming it. Pumps the parser if needed.
    func peekNextEvent() throws -> XMLStreamEvent? {
        if let error = context?.error { throw error }
        if let event = context?.peek() { return event }

        while true {
            guard !didReachEOF else { return context?.peek() }
            try pump()
            if let error = context?.error { throw error }
            if let event = context?.peek() { return event }
        }
    }

    func drainToDocumentEnd() throws {
        while let _ = try nextEvent() {}
    }

    private func pump() throws {
        guard let parserCtxt = parserCtxt else {
            throw XMLParsingError.parseFailed(message: "Streaming parser context is not available.")
        }

        guard !didReachEOF else { return }
        let parseResult: Int32

        if !didFinalizeChunk, offset < data.count {
            let nextChunkSize = min(Self.chunkSize, data.count - offset)
            parseResult = data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else {
                    return xmlParseChunk(parserCtxt, nil, 0, 0)
                }
                let ptr = base.assumingMemoryBound(to: CChar.self).advanced(by: offset)
                return xmlParseChunk(parserCtxt, ptr, Int32(nextChunkSize), 0)
            }
            offset += nextChunkSize
        } else {
            parseResult = xmlParseChunk(parserCtxt, nil, 0, 1)
            didFinalizeChunk = true
            didReachEOF = true
        }

        if let error = context?.error {
            throw error
        }
        guard parseResult == 0 else {
            let message: String?
            if let errPtr = xmlGetLastError(), let msgPtr = errPtr.pointee.message {
                message = String(cString: msgPtr).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = nil
            }
            throw XMLParsingError.parseFailed(message: message ?? "libxml2 SAX parse returned error code \(parseResult).")
        }
    }
}

final class _XMLStreamingStagedChild {
    let name: XMLQualifiedName
    let events: ContiguousArray<XMLStreamEvent>
    /// Shared lazy line table — re-parses original data only when formatting errors.
    private let lazyLineTable: _LazyLineTable?

    init(name: XMLQualifiedName, events: ContiguousArray<XMLStreamEvent>, lazyLineTable: _LazyLineTable?) {
        self.name = name
        self.events = events
        self.lazyLineTable = lazyLineTable
    }

    func makeBuffer() -> _XMLEventBuffer {
        _XMLEventBuffer(events: events, lineTable: lazyLineTable)
    }
}

final class _XMLStreamingElementState {
    let session: _XMLStreamingParserSession
    let startName: XMLQualifiedName
    let startAttributes: [XMLTreeAttribute]
    let startNamespaces: [XMLNamespaceDeclaration]
    /// Event index of the startElement in the session's event stream.
    /// Used to lazily resolve line numbers via the session's lazyLineTable on error paths.
    let startEventIndex: Int?

    /// Lazily resolved line number — only computed on first access (error path).
    var startLine: Int? {
        guard let idx = startEventIndex else { return nil }
        return session.lazyLineTable.lineNumberAt(idx)
    }

    private var stagedChildren: [_XMLStreamingStagedChild] = []
    private var inventoryComplete: Bool = false
    private var directTextParts: [String] = []
    private(set) var childCursor: Int = 0
    private var storedError: XMLParsingError?

    /// Result of consumeChildInline: either an inline child state (fast path)
    /// or a buffered staged child (fallback for out-of-order access).
    enum InlineChildResult {
        case inline(_XMLStreamingElementState)
        case buffered(_XMLStreamingStagedChild)
        /// Scalar leaf element decoded directly from the stream — no heap allocation.
        /// Contains the text content (possibly empty) and the element's qualified name.
        case scalarLeaf(String, XMLQualifiedName)
    }

    init(session: _XMLStreamingParserSession, start: XMLStreamEvent) throws {
        guard case .startElement(let name, let attributes, let namespaces) = start else {
            throw XMLParsingError.parseFailed(message: "[XML6_5_MISSING_ROOT] Cannot identify root element.")
        }
        self.session = session
        self.startName = name
        self.startAttributes = attributes
        self.startNamespaces = namespaces
        // eventCounter was already incremented when nextEvent() returned this event,
        // so subtract 1 to get the index of the startElement event.
        self.startEventIndex = session.eventCounter - 1
    }

    /// Creates an element state with pre-consumed text parts (from a failed scalar leaf fast-path).
    init(session: _XMLStreamingParserSession, start: XMLStreamEvent, preConsumedText: [String]) throws {
        guard case .startElement(let name, let attributes, let namespaces) = start else {
            throw XMLParsingError.parseFailed(message: "[XML6_5_MISSING_ROOT] Cannot identify root element.")
        }
        self.session = session
        self.startName = name
        self.startAttributes = attributes
        self.startNamespaces = namespaces
        self.startEventIndex = session.eventCounter - 1
        self.directTextParts = preConsumedText
    }

    var childCount: Int {
        stagedChildren.count
    }

    func throwIfStoredError() throws {
        if let storedError = storedError {
            throw storedError
        }
    }

    func resetChildCursor() {
        childCursor = 0
    }

    func consumeChild(named localName: String, namespaceURI: String?) throws -> _XMLStreamingStagedChild? {
        try throwIfStoredError()

        if childCursor < stagedChildren.count {
            let candidate = stagedChildren[childCursor]
            if childMatches(candidate, localName: localName, namespaceURI: namespaceURI) {
                childCursor += 1
                return candidate
            }
        }

        while !inventoryComplete {
            if let child = try scanNextChildOrClose() {
                stagedChildren.append(child)
                if childCursor == stagedChildren.count - 1,
                   childMatches(child, localName: localName, namespaceURI: namespaceURI) {
                    childCursor += 1
                    return child
                }
            }
        }

        for child in stagedChildren {
            if childMatches(child, localName: localName, namespaceURI: namespaceURI) {
                return child
            }
        }
        return nil
    }

    /// Fast-path inline consumption: if the next unseen event from the session is a
    /// startElement matching the requested name, return an `.inline` child state that
    /// reads directly from the session (zero copies). Otherwise, fall back to buffered
    /// capture and return `.buffered`.
    func consumeChildInline(
        named localName: String,
        namespaceURI: String?
    ) throws -> InlineChildResult? {
        try throwIfStoredError()

        // If there are already-buffered children beyond the cursor, we can't go inline —
        // the session cursor is past them. Use the existing buffered path.
        if childCursor < stagedChildren.count {
            let candidate = stagedChildren[childCursor]
            if childMatchesName(candidate.name, localName: localName, namespaceURI: namespaceURI) {
                childCursor += 1
                return .buffered(candidate)
            }
            // Out-of-order: linear scan through buffered children.
            for child in stagedChildren {
                if childMatchesName(child.name, localName: localName, namespaceURI: namespaceURI) {
                    return .buffered(child)
                }
            }
            // Not found in buffered — need to scan forward from session.
            // Fall through to the streaming scan below.
        }

        // Stream forward: consume events until we find a matching startElement,
        // the parent's endElement, or a non-matching startElement (which gets buffered).
        while !inventoryComplete {
            guard let next = try session.nextEvent() else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
                )
            }
            switch next {
            case .startElement(let name, _, _):
                if childMatchesName(name, localName: localName, namespaceURI: namespaceURI) {
                    childCursor += 1
                    // SCALAR LEAF FAST PATH: peek ahead — if text+endElement or just endElement,
                    // extract the scalar directly without allocating _XMLStreamingElementState.
                    var preConsumedText: [String] = []
                    if let leafResult = try tryScalarLeafFastPath(name: name, preConsumedText: &preConsumedText) {
                        return leafResult
                    }
                    // INLINE FAST PATH: complex child — create an inline child state.
                    // Inject any text consumed during the failed scalar leaf attempt.
                    let childState = preConsumedText.isEmpty
                        ? try _XMLStreamingElementState(session: session, start: next)
                        : try _XMLStreamingElementState(session: session, start: next, preConsumedText: preConsumedText)
                    return .inline(childState)
                } else {
                    // Out-of-order child: buffer it and keep scanning.
                    let staged = try captureChild(startEvent: next, name: name)
                    stagedChildren.append(staged)
                }
            case .text(let value), .cdata(let value):
                directTextParts.append(value)
            case .endElement:
                inventoryComplete = true
            default:
                break
            }
        }

        // Not found inline — check buffered children (out-of-order fallback).
        for child in stagedChildren {
            if childMatchesName(child.name, localName: localName, namespaceURI: namespaceURI) {
                return .buffered(child)
            }
        }
        return nil
    }

    /// Consume the next child element inline, regardless of name.
    /// Used by the unkeyed container in allChildren mode.
    func consumeAnyChildInline() throws -> InlineChildResult? {
        try throwIfStoredError()

        // If there are already-buffered children beyond the cursor, return the next one.
        if childCursor < stagedChildren.count {
            let child = stagedChildren[childCursor]
            childCursor += 1
            return .buffered(child)
        }

        // Stream forward until we find a startElement or the parent's endElement.
        while !inventoryComplete {
            guard let next = try session.nextEvent() else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
                )
            }
            switch next {
            case .startElement(let name, _, _):
                childCursor += 1
                var preConsumedText: [String] = []
                if let leafResult = try tryScalarLeafFastPath(name: name, preConsumedText: &preConsumedText) {
                    return leafResult
                }
                let childState = preConsumedText.isEmpty
                    ? try _XMLStreamingElementState(session: session, start: next)
                    : try _XMLStreamingElementState(session: session, start: next, preConsumedText: preConsumedText)
                return .inline(childState)
            case .text(let value), .cdata(let value):
                directTextParts.append(value)
            case .endElement:
                inventoryComplete = true
            default:
                break
            }
        }
        return nil
    }

    /// Peek ahead to check if there are more child elements, without buffering them.
    /// Consumes text/cdata events as a side effect. Returns false if the next structural
    /// event is the parent's endElement (or EOF).
    func hasMoreChildren() throws -> Bool {
        try throwIfStoredError()
        if childCursor < stagedChildren.count { return true }
        if inventoryComplete { return false }

        // Peek at upcoming events — consume text/cdata, stop at startElement or endElement.
        while !inventoryComplete {
            guard let peeked = try session.peekNextEvent() else { return false }
            switch peeked {
            case .startElement:
                return true  // There's a child — don't consume it.
            case .endElement:
                _ = try session.nextEvent()  // Consume the endElement.
                inventoryComplete = true
                return false
            case .text(let value), .cdata(let value):
                _ = try session.nextEvent()  // Consume text into directTextParts.
                directTextParts.append(value)
            default:
                _ = try session.nextEvent()  // Skip non-structural events.
            }
        }
        return false
    }

    func peekChild(named localName: String, namespaceURI: String?) throws -> _XMLStreamingStagedChild? {
        try throwIfStoredError()

        for child in stagedChildren {
            if childMatches(child, localName: localName, namespaceURI: namespaceURI) {
                return child
            }
        }

        while !inventoryComplete {
            if let child = try scanNextChildOrClose() {
                stagedChildren.append(child)
                if childMatches(child, localName: localName, namespaceURI: namespaceURI) {
                    return child
                }
            }
        }
        return nil
    }

    func child(at index: Int) throws -> _XMLStreamingStagedChild? {
        try throwIfStoredError()
        while stagedChildren.count <= index, !inventoryComplete {
            if let child = try scanNextChildOrClose() {
                stagedChildren.append(child)
            }
        }
        guard index >= 0, index < stagedChildren.count else { return nil }
        return stagedChildren[index]
    }

    func drainToEndIfNeeded() throws {
        try throwIfStoredError()
        while !inventoryComplete {
            if let child = try scanNextChildOrClose() {
                stagedChildren.append(child)
            }
        }
    }

    func allChildrenBestEffort() -> [_XMLStreamingStagedChild] {
        do {
            try drainToEndIfNeeded()
        } catch let error as XMLParsingError {
            if storedError == nil { storedError = error }
        } catch {
            if storedError == nil {
                storedError = XMLParsingError.other(
                    underlyingError: error,
                    message: "Unexpected streaming decode scan failure."
                )
            }
        }
        return stagedChildren
    }

    func lexicalText(draining: Bool) throws -> String? {
        if draining {
            try drainToEndIfNeeded()
        } else {
            try throwIfStoredError()
        }
        guard !directTextParts.isEmpty else { return nil }
        return directTextParts.joined()
    }

    /// Try to decode a leaf element (text+endElement or just endElement) directly from the
    /// session stream without allocating an `_XMLStreamingElementState`. Returns `nil` if the
    /// next event is a nested startElement, meaning this is a complex child.
    ///
    /// Precondition: the child's startElement has already been consumed from the session.
    /// On `nil` return, `preConsumedText` will contain any text events already consumed
    /// from the stream that must be injected into the subsequent `_XMLStreamingElementState`.
    private func tryScalarLeafFastPath(
        name: XMLQualifiedName,
        preConsumedText: inout [String]
    ) throws -> InlineChildResult? {
        guard let peeked = try session.peekNextEvent() else { return nil }
        switch peeked {
        case .endElement:
            _ = try session.nextEvent()
            return .scalarLeaf("", name)
        case .text, .cdata:
            // Consume text/cdata segments until we see endElement (leaf) or startElement (complex).
            while let next = try session.peekNextEvent() {
                switch next {
                case .text(let value), .cdata(let value):
                    _ = try session.nextEvent()
                    preConsumedText.append(value)
                case .endElement:
                    _ = try session.nextEvent()
                    let text = preConsumedText.count == 1
                        ? preConsumedText[0]
                        : preConsumedText.joined()
                    preConsumedText.removeAll()
                    return .scalarLeaf(text, name)
                default:
                    // Mixed content (text + child elements) — not a scalar leaf.
                    // preConsumedText retains the consumed text for the caller.
                    return nil
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func childMatchesName(_ name: XMLQualifiedName, localName: String, namespaceURI: String?) -> Bool {
        guard name.localName == localName else { return false }
        if let namespaceURI = namespaceURI {
            return name.namespaceURI == namespaceURI
        }
        return true
    }

    private func childMatches(_ child: _XMLStreamingStagedChild, localName: String, namespaceURI: String?) -> Bool {
        childMatchesName(child.name, localName: localName, namespaceURI: namespaceURI)
    }

    private func scanNextChildOrClose() throws -> _XMLStreamingStagedChild? {
        while let next = try session.nextEvent() {
            switch next {
            case .startElement(let name, _, _):
                return try captureChild(startEvent: next, name: name)
            case .endElement:
                inventoryComplete = true
                return nil
            case .text(let value), .cdata(let value):
                directTextParts.append(value)
            default:
                break
            }
        }

        throw XMLParsingError.parseFailed(
            message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
        )
    }

    private func captureChild(
        startEvent: XMLStreamEvent,
        name: XMLQualifiedName
    ) throws -> _XMLStreamingStagedChild {
        var events = ContiguousArray<XMLStreamEvent>()
        events.append(startEvent)

        var depth = 1
        while depth > 0 {
            guard let next = try session.nextEvent() else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
                )
            }
            events.append(next)
            switch next {
            case .startElement:
                depth += 1
            case .endElement:
                depth -= 1
            default:
                break
            }
        }

        return _XMLStreamingStagedChild(name: name, events: events, lazyLineTable: session.lazyLineTable)
    }
}

final class _XMLStreamingDecoder: Decoder {
    let options: _XMLDecoderOptions
    let state: _XMLStreamingElementState
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    let fieldNamespaces: [String: XMLNamespace]
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(
        options: _XMLDecoderOptions,
        state: _XMLStreamingElementState,
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:],
        fieldNamespaces: [String: XMLNamespace] = [:],
        codingPath: [CodingKey]
    ) {
        self.options = options
        self.state = state
        self.fieldNodeKinds = fieldNodeKinds
        self.fieldNamespaces = fieldNamespaces
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        try state.throwIfStoredError()
        state.resetChildCursor()
        return KeyedDecodingContainer(_XMLStreamingKeyedDecodingContainer<Key>(decoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        try state.throwIfStoredError()
        return _XMLStreamingUnkeyedDecodingContainer(decoder: self, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        try state.throwIfStoredError()
        return _XMLStreamingSingleValueDecodingContainer(decoder: self, codingPath: codingPath)
    }

    func finish() throws {
        try state.drainToEndIfNeeded()
    }

    func sourceLocation() -> String {
        guard let line = state.startLine else { return "" }
        return " (line \(line))"
    }

    func decodeFailed(codingPath explicitPath: [CodingKey], message: String) -> XMLParsingError {
        let path = explicitPath.map { key -> String in
            if let index = key.intValue { return "[\(index)]" }
            return key.stringValue
        }
        let location = state.startLine.map { XMLSourceLocation(line: $0) }
        return XMLParsingError.decodeFailed(codingPath: path, location: location, message: message)
    }

    func decodeFailed(message: String) -> XMLParsingError {
        decodeFailed(codingPath: codingPath, message: message)
    }

    var scalarDecoder: _XMLScalarDecoder {
        _XMLScalarDecoder(
            options: options,
            fail: { [weak self] codingPath, message in
                guard let self = self else { return XMLParsingError.parseFailed(message: message) }
                return self.decodeFailed(codingPath: codingPath, message: message)
            }
        )
    }

    func isKnownScalarType(_ type: Any.Type) -> Bool {
        scalarDecoder.isKnownScalarType(type)
    }

    func decodeScalarFromCurrentElement<T: Decodable>(
        _ type: T.Type,
        codingPath: [CodingKey]
    ) throws -> T? {
        let lexical = try state.lexicalText(draining: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if type == String.self {
            let raw = try state.lexicalText(draining: true) ?? ""
            return raw as? T
        }
        guard !lexical.isEmpty else { return nil }
        return try scalarDecoder.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: state.startName.localName,
            isAttribute: false
        )
    }

    /// Dispatch decode to the appropriate path based on inline vs buffered child result.
    func decodeValue<T: Decodable>(
        _ type: T.Type,
        from result: _XMLStreamingElementState.InlineChildResult,
        codingPath: [CodingKey]
    ) throws -> T {
        switch result {
        case .inline(let childState):
            return try decodeValueInline(type, state: childState, codingPath: codingPath)
        case .buffered(let staged):
            return try decodeValueBuffered(type, from: staged, codingPath: codingPath)
        case .scalarLeaf(let text, let name):
            return try decodeScalarLeaf(type, text: text, localName: name.localName, codingPath: codingPath)
        }
    }

    /// Fast path: decode directly from the session stream — zero copies.
    private func decodeValueInline<T: Decodable>(
        _ type: T.Type,
        state childState: _XMLStreamingElementState,
        codingPath: [CodingKey]
    ) throws -> T {
        // Scalar types: read lexical text from the child state.
        if let scalar: T = try decodeScalarFromChildState(type, state: childState, codingPath: codingPath) {
            return scalar
        }
        if scalarDecoder.isKnownScalarType(type) {
            throw decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar at path '\(renderPath(codingPath))'."
            )
        }

        // Complex types: create a recursive streaming decoder for the child.
        var nestedOptions = options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let childDecoder = _XMLStreamingDecoder(
            options: nestedOptions,
            state: childState,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: codingPath
        )
        let result = try T(from: childDecoder)
        try childDecoder.finish()
        return result
    }

    /// Decode a scalar value by draining the child state's lexical text content.
    private func decodeScalarFromChildState<T: Decodable>(
        _ type: T.Type,
        state: _XMLStreamingElementState,
        codingPath: [CodingKey]
    ) throws -> T? {
        if type == String.self {
            let raw = try state.lexicalText(draining: true) ?? ""
            return raw as? T
        }
        guard let lexical = try state.lexicalText(draining: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !lexical.isEmpty else {
            return nil
        }
        return try scalarDecoder.decodeScalarFromLexical(
            lexical, as: type, codingPath: codingPath,
            localName: state.startName.localName, isAttribute: false
        )
    }

    /// Decode a scalar value directly from pre-extracted leaf text — zero heap allocation path.
    private func decodeScalarLeaf<T: Decodable>(
        _ type: T.Type,
        text: String,
        localName: String,
        codingPath: [CodingKey]
    ) throws -> T {
        if type == String.self {
            // swiftlint:disable:next force_cast
            return text as! T
        }
        let lexical = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lexical.isEmpty else {
            throw decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode \(type) from empty leaf element '\(localName)'."
            )
        }
        guard let decoded: T = try scalarDecoder.decodeScalarFromLexical(
            lexical, as: type, codingPath: codingPath,
            localName: localName, isAttribute: false
        ) else {
            throw decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode \(type) from leaf element '\(localName)'."
            )
        }
        return decoded
    }

    /// Fallback path: decode from a buffered staged child via _XMLSAXDecoder.
    func decodeValueBuffered<T: Decodable>(
        _ type: T.Type,
        from child: _XMLStreamingStagedChild,
        codingPath: [CodingKey]
    ) throws -> T {
        let buffer = child.makeBuffer()
        let spanStart = 0
        let spanEnd = buffer.count - 1

        let saxDecoder = _XMLSAXDecoder(
            options: options,
            buffer: buffer,
            start: spanStart,
            end: spanEnd,
            fieldNodeKinds: fieldNodeKinds,
            fieldNamespaces: fieldNamespaces,
            codingPath: codingPath
        )

        if let scalar: T = try saxDecoder.decodeScalarFromSpan(
            type,
            spanStart: spanStart,
            spanEnd: spanEnd,
            localName: child.name.localName,
            codingPath: codingPath
        ) {
            return scalar
        }

        if saxDecoder.isKnownScalarType(type) {
            throw decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar at path '\(renderPath(codingPath))'."
            )
        }

        var nestedOptions = options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLSAXDecoder(
            options: nestedOptions,
            buffer: buffer,
            start: spanStart,
            end: spanEnd,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: codingPath
        )
        return try T(from: nestedDecoder)
    }

    /// Check whether an inline or buffered child represents a nil value.
    func isNilResult(_ result: _XMLStreamingElementState.InlineChildResult) -> Bool {
        switch result {
        case .inline(let childState):
            // Drain the child; if it has no children and no non-whitespace text → nil.
            let children = childState.allChildrenBestEffort()
            let lexical = (try? childState.lexicalText(draining: false))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return children.isEmpty && lexical.isEmpty
        case .buffered(let staged):
            let buffer = staged.makeBuffer()
            return buffer.isNilSpan(from: 0, to: buffer.count - 1)
        case .scalarLeaf(let text, _):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func isNilChild(_ child: _XMLStreamingStagedChild) -> Bool {
        let buffer = child.makeBuffer()
        return buffer.isNilSpan(from: 0, to: buffer.count - 1)
    }

    func attribute(named localName: String) -> XMLTreeAttribute? {
        state.startAttributes.first(where: { $0.name.localName == localName })
    }

    func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

struct _XMLStreamingKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let decoder: _XMLStreamingDecoder
    private(set) var codingPath: [CodingKey]

    init(decoder: _XMLStreamingDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    var allKeys: [Key] {
        let children = decoder.state.allChildrenBestEffort().map { $0.name.localName }
        let attributes = decoder.state.startAttributes.map { $0.name.localName }
        return Set(children + attributes)
            .compactMap { Key(stringValue: $0) }
            .sorted { $0.stringValue < $1.stringValue }
    }

    private func xmlName(for key: Key) -> String {
        let raw = key.stringValue
        switch decoder.options.keyTransformStrategy {
        case .useDefaultKeys:
            return raw
        case .custom(let closure):
            return closure(raw)
        default:
            break
        }
        if let cached = decoder.options.keyNameCache.storage[raw] {
            return cached
        }
        let transformed = decoder.options.keyTransformStrategy.transform(raw)
        decoder.options.keyNameCache.storage[raw] = transformed
        return transformed
    }

    private func fieldNamespaceURI(for key: Key) -> String? {
        decoder.fieldNamespaces[key.stringValue]?.uri
    }

    private func consumedChildInline(for key: Key) throws -> _XMLStreamingElementState.InlineChildResult? {
        try decoder.state.consumeChildInline(named: xmlName(for: key), namespaceURI: fieldNamespaceURI(for: key))
    }

    private func peekChild(for key: Key) throws -> _XMLStreamingStagedChild? {
        try decoder.state.peekChild(named: xmlName(for: key), namespaceURI: fieldNamespaceURI(for: key))
    }

    func contains(_ key: Key) -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return false }
        let name = xmlName(for: key)
        if decoder.attribute(named: name) != nil { return true }
        if (try? decoder.state.peekChild(named: name, namespaceURI: fieldNamespaceURI(for: key))) != nil {
            return true
        }
        return false
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return true }
        let name = xmlName(for: key)
        if decoder.attribute(named: name) != nil { return false }
        guard let child = try peekChild(for: key) else { return true }
        return decoder.isNilChild(child)
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decodeScalar(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeScalar(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeScalar(type, forKey: key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeScalar(type, forKey: key) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute { return try decodeAttribute(type, forKey: key) }
        if nodeKind == .ignored {
            throw decoder.decodeFailed(codingPath: codingPath, message: "[XML6_6_IGNORED_FIELD_DECODE] Field '\(key.stringValue)' is marked @XMLIgnore.")
        }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        let childPath = codingPath + [key]
        guard let result = try consumedChildInline(for: key) else {
            throw decoder.decodeFailed(
                codingPath: childPath,
                message: "[XML6_5_KEY_NOT_FOUND] Missing key '\(key.stringValue)' at path '\(decoder.renderPath(codingPath))'\(decoder.sourceLocation())."
            )
        }
        return try decoder.decodeValue(type, from: result, codingPath: childPath)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let childPath = codingPath + [key]
        guard let result = try consumedChildInline(for: key) else {
            throw decoder.decodeFailed(
                codingPath: childPath,
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested key '\(key.stringValue)'."
            )
        }
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: childPath)
        return try nested.decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let childPath = codingPath + [key]
        guard let result = try consumedChildInline(for: key) else {
            throw decoder.decodeFailed(
                codingPath: childPath,
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested unkeyed key '\(key.stringValue)'."
            )
        }
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: childPath)
        return try nested.decoder.unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        decoder
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        let childPath = codingPath + [key]
        guard let result = try consumedChildInline(for: key) else {
            throw decoder.decodeFailed(
                codingPath: childPath,
                message: "[XML6_5_KEY_NOT_FOUND] Missing super key '\(key.stringValue)'."
            )
        }
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: childPath)
        return nested.decoder
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute { return try decodeAttribute(type, forKey: key) }
        if nodeKind == .ignored {
            throw decoder.decodeFailed(codingPath: codingPath, message: "[XML6_6_IGNORED_FIELD_DECODE] Field '\(key.stringValue)' is marked @XMLIgnore.")
        }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        let childPath = codingPath + [key]
        guard let result = try consumedChildInline(for: key) else {
            throw decoder.decodeFailed(
                codingPath: childPath,
                message: "[XML6_5_KEY_NOT_FOUND] Missing scalar key '\(key.stringValue)'"
                    + " at path '\(decoder.renderPath(codingPath))'\(decoder.sourceLocation())."
            )
        }
        return try decoder.decodeValue(type, from: result, codingPath: childPath)
    }

    private func decodeTextContent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let textPath = codingPath + [key]
        let lexical = try decoder.state.lexicalText(draining: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let wrapperType = type as? _XMLTextContentDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeTextContentLexicalValue(
                lexical,
                using: decoder.scalarDecoder,
                codingPath: textPath,
                key: key.stringValue
            )
            guard let typed = wrapped as? T else {
                throw decoder.decodeFailed(
                    codingPath: textPath,
                    message: "[XML6_6_TEXT_CONTENT_DECODE_CAST_FAILED] Unable to cast decoded text content '\(key.stringValue)' to expected type."
                )
            }
            return typed
        }

        guard let scalar: T = try decoder.scalarDecoder.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: textPath,
            localName: key.stringValue,
            isAttribute: false
        ) else {
            throw decoder.decodeFailed(
                codingPath: textPath,
                message: "[XML6_6_TEXT_CONTENT_DECODE_UNSUPPORTED] Key '\(key.stringValue)' is marked as text content but could not be decoded as scalar."
            )
        }
        return scalar
    }

    private func resolvedNodeKind<T>(for key: Key, valueType: T.Type) -> XMLFieldNodeKind {
        if let typeOverride = valueType as? _XMLFieldKindOverrideType.Type {
            return typeOverride._xmlFieldNodeKindOverride
        }
        if let override = decoder.fieldNodeKinds[key.stringValue] {
            return override
        }
        if let override = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue) {
            return override
        }
        return .element
    }

    private func decodeAttribute<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let attribute = decoder.attribute(named: xmlName(for: key)) else {
            throw decoder.decodeFailed(
                codingPath: codingPath + [key],
                message: "[XML6_6_ATTRIBUTE_NOT_FOUND] Missing attribute '\(key.stringValue)'"
                    + " at path '\(decoder.renderPath(codingPath))'\(decoder.sourceLocation())."
            )
        }

        let attributePath = codingPath + [key]
        if let wrapperType = type as? _XMLAttributeDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeAttributeLexicalValue(
                attribute.value,
                using: decoder.scalarDecoder,
                codingPath: attributePath,
                key: key.stringValue
            )
            guard let typed = wrapped as? T else {
                throw decoder.decodeFailed(
                    codingPath: attributePath,
                    message: "[XML6_6_ATTRIBUTE_DECODE_CAST_FAILED] Unable to cast decoded attribute '\(key.stringValue)' to expected type."
                )
            }
            return typed
        }

        guard let scalar = try decoder.scalarDecoder.decodeScalarFromLexical(
            attribute.value,
            as: type,
            codingPath: attributePath,
            localName: key.stringValue,
            isAttribute: true
        ) else {
            throw decoder.decodeFailed(
                codingPath: attributePath,
                message: "[XML6_6_ATTRIBUTE_DECODE_UNSUPPORTED] Unable to decode attribute '\(key.stringValue)' into non-scalar type."
            )
        }
        return scalar
    }
}

final class _XMLStreamingUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private enum SelectionMode {
        case undecided
        case itemsOnly
        case allChildren
    }

    private let decoder: _XMLStreamingDecoder
    private(set) var codingPath: [CodingKey]
    private(set) var currentIndex: Int = 0

    private var sourceIndex: Int = 0
    private var mode: SelectionMode = .undecided
    private var provisional: [_XMLStreamingStagedChild] = []
    /// Buffered eligible children from the mode-detection phase.
    private var eligible: [_XMLStreamingStagedChild] = []
    private var reachedSourceEnd: Bool = false
    /// Once mode is decided and all buffered eligible children have been consumed,
    /// switch to inline streaming for remaining children.
    private var inlineActive: Bool = false

    init(decoder: _XMLStreamingDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    var count: Int? {
        do {
            try drainEligibleToEnd()
            return eligible.count
        } catch {
            return nil
        }
    }

    var isAtEnd: Bool {
        // If there are buffered eligible children ahead, not at end.
        if currentIndex < eligible.count { return false }
        // If source is fully drained and no more buffered, at end.
        if reachedSourceEnd { return true }
        // If mode is decided and we're in inline mode, peek at the session.
        if inlineActive {
            do {
                return try !decoder.state.hasMoreChildren()
            } catch {
                return true
            }
        }
        // Mode not yet decided or still in buffered phase — buffer one more.
        do {
            try ensureEligibleCount(currentIndex + 1)
        } catch {
            return true
        }
        return currentIndex >= eligible.count
    }

    func decodeNil() throws -> Bool {
        let child = try currentChild()
        let isNil = decoder.isNilChild(child)
        if isNil { currentIndex += 1 }
        return isNil
    }

    func decode(_ type: Bool.Type) throws -> Bool { try decodeNext(type) }
    func decode(_ type: String.Type) throws -> String { try decodeNext(type) }
    func decode(_ type: Double.Type) throws -> Double { try decodeNext(type) }
    func decode(_ type: Float.Type) throws -> Float { try decodeNext(type) }
    func decode(_ type: Int.Type) throws -> Int { try decodeNext(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decodeNext(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decodeNext(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decodeNext(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decodeNext(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try decodeNext(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeNext(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeNext(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeNext(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeNext(type) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decodeNext(type)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let result = try consumeNext()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: codingPath + [indexKey])
        return try nested.decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let result = try consumeNext()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: codingPath + [indexKey])
        return try nested.decoder.unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        let result = try consumeNext()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nested = try decoder.decodeValue(_XMLAnyDecoderBridge.self, from: result, codingPath: codingPath + [indexKey])
        return nested.decoder
    }

    // MARK: - Core decode dispatch

    private func decodeNext<T: Decodable>(_ type: T.Type) throws -> T {
        let result = try consumeNext()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        return try decoder.decodeValue(type, from: result, codingPath: itemPath)
    }

    /// Returns the next eligible child as an InlineChildResult.
    /// Uses buffered children if available (mode-detection phase), then switches to inline.
    private func consumeNext() throws -> _XMLStreamingElementState.InlineChildResult {
        // Phase 1: buffered children from mode-detection.
        if currentIndex < eligible.count {
            return .buffered(eligible[currentIndex])
        }

        // Activate inline mode once all buffered eligible children have been consumed.
        if !inlineActive {
            ensureModeDecided()
            inlineActive = true
        }

        // Phase 2: inline streaming.
        guard let result = try nextEligibleInline() else {
            throw decoder.decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_UNKEYED_OUT_OF_RANGE] Unkeyed container is at end at path '\(decoder.renderPath(codingPath))'."
            )
        }
        return result
    }

    /// Consume the next eligible child inline from the session.
    private func nextEligibleInline() throws -> _XMLStreamingElementState.InlineChildResult? {
        switch mode {
        case .allChildren:
            return try decoder.state.consumeAnyChildInline()
        case .itemsOnly:
            return try decoder.state.consumeChildInline(
                named: decoder.options.itemElementName,
                namespaceURI: nil
            )
        case .undecided:
            // Should not reach here — ensureModeDecided guarantees mode is decided.
            return try decoder.state.consumeAnyChildInline()
        }
    }

    /// Ensure mode is decided by buffering enough children.
    private func ensureModeDecided() {
        guard mode == .undecided else { return }
        // If we got here with undecided, all buffered children had no "item" element.
        // That means allChildren mode.
        mode = .allChildren
        eligible = provisional
        provisional.removeAll(keepingCapacity: false)
    }

    private func currentChild() throws -> _XMLStreamingStagedChild {
        try ensureEligibleCount(currentIndex + 1)
        guard currentIndex < eligible.count else {
            throw decoder.decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_UNKEYED_OUT_OF_RANGE] Unkeyed container is at end at path '\(decoder.renderPath(codingPath))'."
            )
        }
        return eligible[currentIndex]
    }

    private func ensureEligibleCount(_ required: Int) throws {
        while eligible.count < required {
            if reachedSourceEnd { break }
            guard let child = try decoder.state.child(at: sourceIndex) else {
                reachedSourceEnd = true
                if mode == .undecided {
                    mode = .allChildren
                    eligible = provisional
                    provisional.removeAll(keepingCapacity: false)
                }
                break
            }
            sourceIndex += 1
            appendSourceChild(child)
        }
    }

    private func drainEligibleToEnd() throws {
        while !reachedSourceEnd {
            guard let child = try decoder.state.child(at: sourceIndex) else {
                reachedSourceEnd = true
                if mode == .undecided {
                    mode = .allChildren
                    eligible = provisional
                    provisional.removeAll(keepingCapacity: false)
                }
                break
            }
            sourceIndex += 1
            appendSourceChild(child)
        }
    }

    private func appendSourceChild(_ child: _XMLStreamingStagedChild) {
        switch mode {
        case .undecided:
            provisional.append(child)
            if child.name.localName == decoder.options.itemElementName {
                mode = .itemsOnly
                eligible = provisional.filter { $0.name.localName == decoder.options.itemElementName }
                provisional.removeAll(keepingCapacity: false)
            }
        case .itemsOnly:
            if child.name.localName == decoder.options.itemElementName {
                eligible.append(child)
            }
        case .allChildren:
            eligible.append(child)
        }
    }
}

struct _XMLStreamingSingleValueDecodingContainer: SingleValueDecodingContainer {
    private let decoder: _XMLStreamingDecoder
    private(set) var codingPath: [CodingKey]

    init(decoder: _XMLStreamingDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    func decodeNil() -> Bool {
        let lexical = try? decoder.state.lexicalText(draining: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let children = decoder.state.allChildrenBestEffort()
        return children.isEmpty && (lexical ?? "").isEmpty
    }

    func decode(_ type: Bool.Type) throws -> Bool { try decodeScalar(type) }
    func decode(_ type: String.Type) throws -> String { try decodeScalar(type) }
    func decode(_ type: Double.Type) throws -> Double { try decodeScalar(type) }
    func decode(_ type: Float.Type) throws -> Float { try decodeScalar(type) }
    func decode(_ type: Int.Type) throws -> Int { try decodeScalar(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try decodeScalar(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try decodeScalar(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try decodeScalar(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try decodeScalar(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try decodeScalar(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeScalar(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeScalar(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeScalar(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeScalar(type) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let scalar: T = try decoder.decodeScalarFromCurrentElement(type, codingPath: codingPath) {
            return scalar
        }
        if decoder.isKnownScalarType(type) {
            throw decoder.decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode single-value scalar at path '\(decoder.renderPath(codingPath))'."
            )
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLStreamingDecoder(
            options: nestedOptions,
            state: decoder.state,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: codingPath
        )
        return try T(from: nestedDecoder)
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        guard let scalar: T = try decoder.decodeScalarFromCurrentElement(type, codingPath: codingPath) else {
            throw decoder.decodeFailed(
                codingPath: codingPath,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode single-value scalar at path '\(decoder.renderPath(codingPath))'."
            )
        }
        return scalar
    }
}

private struct _XMLAnyDecoderBridge: Decodable {
    let decoder: Decoder

    init(from decoder: Decoder) throws {
        self.decoder = decoder
    }
}

private func _xmlStreamingContext(from ptr: UnsafeMutableRawPointer?) -> _XMLStreamingParserSessionContext? {
    guard let ptr = ptr else { return nil }
    return Unmanaged<_XMLStreamingParserSessionContext>.fromOpaque(ptr).takeUnretainedValue()
}

private func _xmlStreamingEnsureLimit(
    actual: Int,
    limit: Int?,
    code: String,
    context: String,
    logger: Logger
) throws {
    guard let limit = limit else { return }
    guard actual <= limit else {
        logger.warning(
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

private func _xmlStreamingCheckByteLimit(
    _ bytes: Int,
    limit: Int?,
    code: String,
    ctx: _XMLStreamingParserSessionContext
) -> Bool {
    guard let limit = limit, bytes > limit else { return false }
    ctx.error = XMLParsingError.parseFailed(
        message: "[\(code)] Content size \(bytes) bytes exceeds limit \(limit) bytes."
    )
    return true
}

private func _xmlStreamingIncrementAndCheckNodeCount(ctx: _XMLStreamingParserSessionContext) -> Bool {
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
        ctx.logger.warning(
            "XML stream node count approaching limit",
            metadata: ["nodeCount": "\(ctx.nodeCount)", "limit": "\(maxNodes)"]
        )
    }
    return false
}

private func _xmlStreamingString(from ptr: UnsafePointer<xmlChar>?) -> String? {
    guard let ptr = ptr else { return nil }
    return String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
}

private func _xmlStreamingQName(
    localname: UnsafePointer<xmlChar>?,
    prefix: UnsafePointer<xmlChar>?,
    uri: UnsafePointer<xmlChar>?
) -> XMLQualifiedName {
    XMLQualifiedName(
        uncheckedLocalName: _xmlStreamingString(from: localname) ?? "",
        namespaceURI: _xmlStreamingString(from: uri),
        prefix: _xmlStreamingString(from: prefix)
    )
}

// swiftlint:enable file_length large_tuple
