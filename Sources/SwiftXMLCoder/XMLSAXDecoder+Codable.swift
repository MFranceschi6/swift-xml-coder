// swiftlint:disable large_tuple
import Foundation

// MARK: - _LazyLineTable
//
// Holds the original parse input and re-parses it on demand to produce a line-number table.
// This avoids the per-event append cost (and the ContiguousArray allocation) on the happy
// path. The re-parse is triggered at most once, on the first call to lineNumberAt(_:), which
// only happens when an error is being formatted.

final class _LazyLineTable {
    private let data: Data
    private let parserConfig: XMLTreeParser.Configuration
    private var lineNumbers: ContiguousArray<Int?>?

    init(data: Data, parserConfig: XMLTreeParser.Configuration) {
        self.data = data
        self.parserConfig = parserConfig
    }

    /// Initialise with a pre-built table — for testing only.
    init(prebuilt: ContiguousArray<Int?>) {
        self.data = Data()
        self.parserConfig = XMLTreeParser.Configuration()
        self.lineNumbers = prebuilt
    }

    func lineNumberAt(_ index: Int) -> Int? {
        if lineNumbers == nil { populate() }
        guard let numbers = lineNumbers, numbers.indices.contains(index) else { return nil }
        return numbers[index]
    }

    private func populate() {
        let parser = XMLStreamParser(configuration: parserConfig)
        var numbers = ContiguousArray<Int?>()
        // If re-parse fails (shouldn't — same data + same config), leave lineNumbers nil.
        try? parser.parseSAX(
            data: data,
            onEvent: { _ in },
            onEventWithLine: { _, line in numbers.append(line) }
        )
        lineNumbers = numbers
    }
}

// MARK: - _XMLEventBuffer

struct _XMLEventBuffer {
    let events: ContiguousArray<XMLStreamEvent>

    // Structural side table: startToEnd[i] == end index for the .startElement at events[i],
    // or -1 if events[i] is not a .startElement. Built once in O(n) during init.
    let startToEnd: ContiguousArray<Int>
    // Precomputed root element span; nil if the buffer has no root element.
    let rootElementRange: (start: Int, end: Int)?

    // Line numbers are populated lazily via a re-parse triggered only when an error is formatted.
    // nil means no source is available (e.g. item-decoder sub-spans).
    private let lineTable: _LazyLineTable?

    init(events: ContiguousArray<XMLStreamEvent>, lineTable: _LazyLineTable?) {
        self.events = events
        self.lineTable = lineTable

        // Single O(n) pass: pair every .startElement with its matching .endElement.
        var map = ContiguousArray(repeating: -1, count: events.count)
        var stack: [Int] = []
        stack.reserveCapacity(32)
        var foundRoot: (start: Int, end: Int)?
        for idx in events.indices {
            switch events[idx] {
            case .startElement:
                stack.append(idx)
            case .endElement:
                if let startIdx = stack.popLast() {
                    map[startIdx] = idx
                    if stack.isEmpty && foundRoot == nil {
                        foundRoot = (startIdx, idx)
                    }
                }
            default:
                break
            }
        }
        self.startToEnd = map
        self.rootElementRange = foundRoot
    }

    var count: Int { events.count }

    func lineNumberAt(_ index: Int) -> Int? {
        guard events.indices.contains(index) else { return nil }
        return lineTable?.lineNumberAt(index)
    }

    func findRootElement() throws -> (start: Int, end: Int) {
        guard let root = rootElementRange else {
            // Distinguish between unbalanced vs. missing root.
            for event in events {
                if case .startElement = event {
                    throw XMLParsingError.parseFailed(
                        message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
                    )
                }
            }
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_MISSING_ROOT] XML document does not contain a root element."
            )
        }
        return root
    }

    func elementEndIndex(from startIndex: Int) -> Int? {
        guard events.indices.contains(startIndex) else { return nil }
        guard case .startElement = events[startIndex] else { return nil }
        let end = startToEnd[startIndex]
        return end >= 0 ? end : nil
    }

    func childElementSpans(from start: Int, to end: Int) -> [(name: XMLQualifiedName, start: Int, end: Int)] {
        guard events.indices.contains(start), events.indices.contains(end), start < end else { return [] }
        var spans: [(name: XMLQualifiedName, start: Int, end: Int)] = []
        var index = start + 1

        while index < end {
            if case .startElement(let name, _, _) = events[index] {
                let childEnd = startToEnd[index]
                if childEnd > 0 {
                    spans.append((name: name, start: index, end: childEnd))
                    index = childEnd + 1  // Skip the entire subtree.
                } else {
                    index += 1
                }
            } else {
                index += 1
            }
        }
        return spans
    }

    func lexicalText(from start: Int, to end: Int) -> String? {
        guard events.indices.contains(start), events.indices.contains(end), start < end else { return nil }
        var parts: [String] = []
        var index = start + 1
        while index < end {
            switch events[index] {
            case .startElement:
                // Skip the entire child subtree — only direct text at depth 0 counts.
                let childEnd = startToEnd[index]
                index = childEnd > 0 ? childEnd + 1 : index + 1
            case .text(let value), .cdata(let value):
                parts.append(value)
                index += 1
            default:
                index += 1
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined()
    }

    func isNilSpan(from start: Int, to end: Int) -> Bool {
        guard events.indices.contains(start), events.indices.contains(end), start < end else { return true }
        // Walk the immediate content of this span. Stop as soon as we find evidence of a value:
        // a child element, or non-whitespace text. No array allocation needed.
        var index = start + 1
        while index < end {
            switch events[index] {
            case .startElement:
                return false  // Has child elements — not nil.
            case .text(let value), .cdata(let value):
                if !value.allSatisfy(\.isWhitespace) { return false }
                index += 1
            default:
                index += 1
            }
        }
        return true
    }

    func attributesAt(_ startIndex: Int) -> [XMLTreeAttribute] {
        guard events.indices.contains(startIndex) else { return [] }
        guard case .startElement(_, let attributes, _) = events[startIndex] else { return [] }
        return attributes
    }

    func makeTreeDocument() throws -> XMLTreeDocument {
        var builder = _XMLSAXTreeBuilder()
        for index in events.indices {
            try builder.consume(event: events[index], line: lineTable?.lineNumberAt(index))
        }
        return try builder.finalize()
    }
}

// MARK: - _XMLSAXDecoder
//
// A Decoder that reads directly from an _XMLEventBuffer span (start, end) without
// materialising an XMLTreeDocument. The decoder passes (start, end) index pairs into
// the buffer to child containers, which compute child spans lazily via
// _XMLEventBuffer.childElementSpans(from:to:).

final class _XMLSAXDecoder: Decoder {
    let options: _XMLDecoderOptions
    let buffer: _XMLEventBuffer
    /// Index of the .startElement event for this element.
    let start: Int
    /// Index of the .endElement event for this element.
    let end: Int
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    let fieldNamespaces: [String: XMLNamespace]
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    // Cached lazily — computed once on first keyed/unkeyed access.
    private(set) lazy var childSpans: [(name: XMLQualifiedName, start: Int, end: Int)] =
        buffer.childElementSpans(from: start, to: end)
    private(set) lazy var attributes: [XMLTreeAttribute] = buffer.attributesAt(start)

    // Sequential cursor for in-order keyed lookup. Reset by container(keyedBy:).
    // XML element order and Codable declaration order typically match, so the
    // cursor hits on the first comparison for each field — O(1) amortised.
    var childCursor: Int = 0

    init(
        options: _XMLDecoderOptions,
        buffer: _XMLEventBuffer,
        start: Int,
        end: Int,
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:],
        fieldNamespaces: [String: XMLNamespace] = [:],
        codingPath: [CodingKey]
    ) {
        self.options = options
        self.buffer = buffer
        self.start = start
        self.end = end
        self.fieldNodeKinds = fieldNodeKinds
        self.fieldNamespaces = fieldNamespaces
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        childCursor = 0
        return KeyedDecodingContainer(_XMLSAXKeyedDecodingContainer<Key>(decoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        _XMLSAXUnkeyedDecodingContainer(decoder: self, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _XMLSAXSingleValueDecodingContainer(decoder: self, codingPath: codingPath)
    }

    // MARK: - Element helpers

    /// Consuming lookup: tries the current cursor position first, then falls back to a
    /// full linear scan. Advances the cursor only on a cursor hit, so in-order Codable
    /// access (the common case) costs one comparison per field.
    func firstChildSpan(
        named localName: String,
        namespaceURI: String?
    ) -> (name: XMLQualifiedName, start: Int, end: Int)? {
        let spans = childSpans
        if childCursor < spans.count {
            let candidate = spans[childCursor]
            if candidate.name.localName == localName &&
               (namespaceURI == nil || candidate.name.namespaceURI == namespaceURI) {
                childCursor += 1
                return candidate
            }
        }
        // Fallback: full linear scan (out-of-order field, missing field, namespace filter).
        for span in spans {
            guard span.name.localName == localName else { continue }
            if let uri = namespaceURI {
                if span.name.namespaceURI == uri { return span }
            } else {
                return span
            }
        }
        return nil
    }

    /// Non-consuming peek: always linear scan, never advances the cursor.
    /// Used by contains() and decodeNil() which must not disturb decode order.
    func peekChildSpan(
        named localName: String,
        namespaceURI: String?
    ) -> (name: XMLQualifiedName, start: Int, end: Int)? {
        for span in childSpans {
            guard span.name.localName == localName else { continue }
            if let uri = namespaceURI {
                if span.name.namespaceURI == uri { return span }
            } else {
                return span
            }
        }
        return nil
    }

    func attribute(named localName: String) -> XMLTreeAttribute? {
        attributes.first(where: { $0.name.localName == localName })
    }

    func isNilSpan(start spanStart: Int, end spanEnd: Int) -> Bool {
        buffer.isNilSpan(from: spanStart, to: spanEnd)
    }

    func sourceLocation(at spanStart: Int) -> String {
        guard let line = buffer.lineNumberAt(spanStart) else { return "" }
        return " (line \(line))"
    }

    // MARK: - Error helpers

    func decodeFailed(
        codingPath explicitPath: [CodingKey],
        spanStart: Int? = nil,
        message: String
    ) -> XMLParsingError {
        let path = explicitPath.map { key -> String in
            if let index = key.intValue { return "[\(index)]" }
            return key.stringValue
        }
        let lineIndex = spanStart ?? start
        let location = buffer.lineNumberAt(lineIndex).map { XMLSourceLocation(line: $0) }
        return XMLParsingError.decodeFailed(codingPath: path, location: location, message: message)
    }

    func decodeFailed(message: String) -> XMLParsingError {
        decodeFailed(codingPath: codingPath, message: message)
    }

    // MARK: - Scalar decoding

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

    /// Decode a scalar value from the lexical text content of the span [spanStart, spanEnd].
    func decodeScalarFromSpan<T: Decodable>(
        _ type: T.Type,
        spanStart: Int,
        spanEnd: Int,
        localName: String,
        codingPath: [CodingKey]
    ) throws -> T? {
        if type == String.self {
            let value = buffer.lexicalText(from: spanStart, to: spanEnd) ?? ""
            return value as? T
        }
        guard let lexical = buffer.lexicalText(from: spanStart, to: spanEnd)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !lexical.isEmpty else {
            return nil
        }
        return try scalarDecoder.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: localName,
            isAttribute: false
        )
    }
}

// MARK: - _XMLSAXKeyedDecodingContainer

struct _XMLSAXKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let decoder: _XMLSAXDecoder
    private(set) var codingPath: [CodingKey]

    init(decoder: _XMLSAXDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    var allKeys: [Key] {
        let elementNames = decoder.childSpans.map { $0.name.localName }
        let attributeNames = decoder.attributes.map { $0.name.localName }
        return Set(elementNames + attributeNames)
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

    private func childSpan(for key: Key) -> (name: XMLQualifiedName, start: Int, end: Int)? {
        decoder.firstChildSpan(named: xmlName(for: key), namespaceURI: fieldNamespaceURI(for: key))
    }

    func contains(_ key: Key) -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return false }
        let name = xmlName(for: key)
        return decoder.peekChildSpan(named: name, namespaceURI: fieldNamespaceURI(for: key)) != nil
            || decoder.attribute(named: name) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return true }
        let name = xmlName(for: key)
        if decoder.attribute(named: name) != nil { return false }
        guard let span = decoder.peekChildSpan(named: name, namespaceURI: fieldNamespaceURI(for: key)) else {
            return true
        }
        return decoder.isNilSpan(start: span.start, end: span.end)
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
            throw decoder.decodeFailed(codingPath: codingPath,
                message: "[XML6_6_IGNORED_FIELD_DECODE] Field '\(key.stringValue)' is marked @XMLIgnore — " +
                    "use an Optional type or provide a default value via init(from:) to suppress this error.")
        }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        let childPath = codingPath + [key]
        guard let span = childSpan(for: key) else {
            throw decoder.decodeFailed(codingPath: childPath, spanStart: decoder.start,
                message: "[XML6_5_KEY_NOT_FOUND] Missing key '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }

        if let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: span.start, spanEnd: span.end,
            localName: span.name.localName, codingPath: childPath
        ) { return scalar }

        if decoder.isKnownScalarType(type) {
            throw decoder.decodeFailed(codingPath: childPath, spanStart: span.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar key '\(key.stringValue)' " +
                    "at path '\(renderPath(childPath))'\(decoder.sourceLocation(at: span.start)).")
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLSAXDecoder(
            options: nestedOptions,
            buffer: decoder.buffer,
            start: span.start,
            end: span.end,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: childPath
        )
        return try T(from: nestedDecoder)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw decoder.decodeFailed(codingPath: codingPath,
                message: "[XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED] " +
                    "Cannot decode nested keyed container from attribute '\(key.stringValue)'.")
        }
        guard let span = childSpan(for: key) else {
            throw decoder.decodeFailed(codingPath: codingPath + [key], spanStart: decoder.start,
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested key '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }
        let nestedDecoder = _XMLSAXDecoder(
            options: decoder.options,
            buffer: decoder.buffer,
            start: span.start, end: span.end,
            codingPath: codingPath + [key]
        )
        return try nestedDecoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw decoder.decodeFailed(codingPath: codingPath,
                message: "[XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED] " +
                    "Cannot decode nested unkeyed container from attribute '\(key.stringValue)'.")
        }
        guard let span = childSpan(for: key) else {
            throw decoder.decodeFailed(codingPath: codingPath + [key], spanStart: decoder.start,
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested unkeyed key '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }
        let nestedDecoder = _XMLSAXDecoder(
            options: decoder.options,
            buffer: decoder.buffer,
            start: span.start, end: span.end,
            codingPath: codingPath + [key]
        )
        return try nestedDecoder.unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        _XMLSAXDecoder(
            options: decoder.options,
            buffer: decoder.buffer,
            start: decoder.start, end: decoder.end,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: codingPath
        )
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        guard let span = decoder.firstChildSpan(named: xmlName(for: key), namespaceURI: nil) else {
            throw decoder.decodeFailed(codingPath: codingPath + [key], spanStart: decoder.start,
                message: "[XML6_5_KEY_NOT_FOUND] Missing super key '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }
        return _XMLSAXDecoder(
            options: decoder.options,
            buffer: decoder.buffer,
            start: span.start, end: span.end,
            codingPath: codingPath + [key]
        )
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute { return try decodeAttribute(type, forKey: key) }
        if nodeKind == .ignored {
            throw decoder.decodeFailed(codingPath: codingPath,
                message: "[XML6_6_IGNORED_FIELD_DECODE] Field '\(key.stringValue)' is marked @XMLIgnore — " +
                    "use an Optional type or provide a default value via init(from:) to suppress this error.")
        }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        guard let span = childSpan(for: key) else {
            throw decoder.decodeFailed(codingPath: codingPath + [key], spanStart: decoder.start,
                message: "[XML6_5_KEY_NOT_FOUND] Missing scalar key '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }
        let childPath = codingPath + [key]
        guard let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: span.start, spanEnd: span.end,
            localName: span.name.localName, codingPath: childPath
        ) else {
            throw decoder.decodeFailed(codingPath: childPath, spanStart: span.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar key '\(key.stringValue)' " +
                    "at path '\(renderPath(childPath))'\(decoder.sourceLocation(at: span.start)).")
        }
        return scalar
    }

    private func decodeTextContent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let textPath = codingPath + [key]
        let lexical = decoder.buffer.lexicalText(from: decoder.start, to: decoder.end)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let wrapperType = type as? _XMLTextContentDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeTextContentLexicalValue(
                lexical, using: decoder.scalarDecoder, codingPath: textPath, key: key.stringValue)
            guard let typed = wrapped as? T else {
                throw decoder.decodeFailed(codingPath: textPath,
                    message: "[XML6_6_TEXT_CONTENT_DECODE_CAST_FAILED] " +
                        "Unable to cast decoded text content '\(key.stringValue)' to expected type.")
            }
            return typed
        }

        guard let scalar: T = try decoder.scalarDecoder.decodeScalarFromLexical(
            lexical, as: type, codingPath: textPath, localName: key.stringValue, isAttribute: false
        ) else {
            throw decoder.decodeFailed(codingPath: textPath,
                message: "[XML6_6_TEXT_CONTENT_DECODE_UNSUPPORTED] " +
                    "Key '\(key.stringValue)' is marked as text content " +
                    "but the value could not be decoded as a scalar at path '\(renderPath(codingPath))'.")
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
            throw decoder.decodeFailed(codingPath: codingPath + [key], spanStart: decoder.start,
                message: "[XML6_6_ATTRIBUTE_NOT_FOUND] Missing attribute '\(key.stringValue)' " +
                    "at path '\(renderPath(codingPath))'\(decoder.sourceLocation(at: decoder.start)).")
        }

        let attributePath = codingPath + [key]
        if let wrapperType = type as? _XMLAttributeDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeAttributeLexicalValue(
                attribute.value, using: decoder.scalarDecoder,
                codingPath: attributePath, key: key.stringValue)
            guard let typed = wrapped as? T else {
                throw decoder.decodeFailed(codingPath: attributePath,
                    message: "[XML6_6_ATTRIBUTE_DECODE_CAST_FAILED] " +
                        "Unable to cast decoded attribute '\(key.stringValue)' to expected type.")
            }
            return typed
        }

        guard let scalar = try decoder.scalarDecoder.decodeScalarFromLexical(
            attribute.value, as: type, codingPath: attributePath,
            localName: key.stringValue, isAttribute: true
        ) else {
            throw decoder.decodeFailed(codingPath: attributePath,
                message: "[XML6_6_ATTRIBUTE_DECODE_UNSUPPORTED] " +
                    "Unable to decode attribute '\(key.stringValue)' into non-scalar type.")
        }
        return scalar
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

// MARK: - _XMLSAXUnkeyedDecodingContainer

struct _XMLSAXUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private let decoder: _XMLSAXDecoder
    private(set) var codingPath: [CodingKey]
    private let spans: [(name: XMLQualifiedName, start: Int, end: Int)]
    private(set) var currentIndex: Int = 0

    init(decoder: _XMLSAXDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
        let allSpans = decoder.childSpans
        let itemSpans = allSpans.filter { $0.name.localName == decoder.options.itemElementName }
        self.spans = itemSpans.isEmpty ? allSpans : itemSpans
    }

    var count: Int? { spans.count }
    var isAtEnd: Bool { currentIndex >= spans.count }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return true }
        let span = spans[currentIndex]
        let isNil = decoder.isNilSpan(start: span.start, end: span.end)
        if isNil { currentIndex += 1 }
        return isNil
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeScalar(type) }
    mutating func decode(_ type: String.Type) throws -> String { try decodeScalar(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeScalar(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try decodeScalar(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try decodeScalar(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeScalar(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeScalar(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeScalar(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeScalar(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeScalar(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeScalar(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeScalar(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeScalar(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeScalar(type) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let span = try currentSpan()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]

        if let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: span.start, spanEnd: span.end,
            localName: span.name.localName, codingPath: itemPath
        ) { return scalar }

        if decoder.isKnownScalarType(type) {
            throw decoder.decodeFailed(codingPath: itemPath, spanStart: span.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] " +
                    "Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'.")
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLSAXDecoder(
            options: nestedOptions,
            buffer: decoder.buffer,
            start: span.start, end: span.end,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: itemPath
        )
        return try T(from: nestedDecoder)
    }

    mutating func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let span = try currentSpan()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nestedDecoder = _XMLSAXDecoder(
            options: decoder.options, buffer: decoder.buffer,
            start: span.start, end: span.end, codingPath: codingPath + [indexKey])
        return try nestedDecoder.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let span = try currentSpan()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nestedDecoder = _XMLSAXDecoder(
            options: decoder.options, buffer: decoder.buffer,
            start: span.start, end: span.end, codingPath: codingPath + [indexKey])
        return try nestedDecoder.unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        let span = try currentSpan()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        return _XMLSAXDecoder(
            options: decoder.options, buffer: decoder.buffer,
            start: span.start, end: span.end, codingPath: codingPath + [indexKey])
    }

    private mutating func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        let span = try currentSpan()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        guard let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: span.start, spanEnd: span.end,
            localName: span.name.localName, codingPath: itemPath
        ) else {
            throw decoder.decodeFailed(codingPath: itemPath, spanStart: span.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] " +
                    "Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'.")
        }
        return scalar
    }

    private func currentSpan() throws -> (name: XMLQualifiedName, start: Int, end: Int) {
        guard !isAtEnd else {
            throw decoder.decodeFailed(codingPath: codingPath,
                message: "[XML6_5_UNKEYED_OUT_OF_RANGE] " +
                    "Unkeyed container is at end at path '\(renderPath(codingPath))'.")
        }
        return spans[currentIndex]
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

// MARK: - _XMLSAXSingleValueDecodingContainer

struct _XMLSAXSingleValueDecodingContainer: SingleValueDecodingContainer {
    private let decoder: _XMLSAXDecoder
    private(set) var codingPath: [CodingKey]

    init(decoder: _XMLSAXDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    func decodeNil() -> Bool {
        decoder.isNilSpan(start: decoder.start, end: decoder.end)
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
        if let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: decoder.start, spanEnd: decoder.end,
            localName: elementLocalName(), codingPath: codingPath
        ) { return scalar }

        if decoder.isKnownScalarType(type) {
            throw decoder.decodeFailed(codingPath: codingPath, spanStart: decoder.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] " +
                    "Unable to decode single-value scalar at path '\(renderPath(codingPath))'.")
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLSAXDecoder(
            options: nestedOptions,
            buffer: decoder.buffer,
            start: decoder.start, end: decoder.end,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: codingPath
        )
        return try T(from: nestedDecoder)
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        guard let scalar: T = try decoder.decodeScalarFromSpan(
            type, spanStart: decoder.start, spanEnd: decoder.end,
            localName: elementLocalName(), codingPath: codingPath
        ) else {
            throw decoder.decodeFailed(codingPath: codingPath, spanStart: decoder.start,
                message: "[XML6_5_SCALAR_PARSE_FAILED] " +
                    "Unable to decode single-value scalar at path '\(renderPath(codingPath))'.")
        }
        return scalar
    }

    private func elementLocalName() -> String {
        guard case .startElement(let name, _, _) = decoder.buffer.events[decoder.start] else { return "" }
        return name.localName
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}
// swiftlint:enable large_tuple
