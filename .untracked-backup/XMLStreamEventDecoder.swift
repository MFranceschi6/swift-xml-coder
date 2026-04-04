// swiftlint:disable file_length
import Foundation

// MARK: - Architecture: XMLStreamEventDecoder
//
// A `Decoder` that operates directly on `[XMLStreamEvent]` without building
// an intermediate `XMLTreeDocument`. This replaces the buildDocument → XMLDecoder
// pipeline inside `XMLStreamDecoder.decodeImpl`.
//
// ## How it works
//
// The decoder holds the flat event array and an `EventRange` indicating the
// current element's span (start = index of .startElement, end = index of the
// matching .endElement).
//
// Each keyed container builds a ChildIndex in a single forward scan and
// consults it for key lookups. For ordered XML + ordered Decodable access,
// the index is consulted in document order — no backtracking in the common case.
//
// ## Scalar decoding
//
// A `_XMLTreeDecoder` "oracle" (built with a dummy XMLTreeElement) is held by
// each `XMLStreamEventDecoder`. It is used only to reuse the existing
// `decodeScalarFromLexical` logic — no tree navigation through the oracle.

// MARK: - EventRange

/// A closed range of indices within a `[XMLStreamEvent]` array.
///
/// `events[start]` is a `.startElement` and `events[end]` is its matching
/// `.endElement`.
struct EventRange {
    let start: Int
    let end: Int
}

// MARK: - Free helpers

/// Builds an index mapping XML local names to ordered `EventRange` lists for
/// direct children of `scope`. Complexity: O(events in scope) — one forward pass.
func _streamBuildChildIndex(
    events: [XMLStreamEvent],
    scope: EventRange
) -> [String: [EventRange]] {
    var index: [String: [EventRange]] = [:]
    var depth = 0
    var childStart = -1
    var childName = ""
    for idx in (scope.start + 1)..<scope.end {
        switch events[idx] {
        case .startElement(let name, _, _):
            depth += 1
            if depth == 1 {
                childStart = idx
                childName = name.localName
            }
        case .endElement:
            if depth == 1 {
                index[childName, default: []].append(EventRange(start: childStart, end: idx))
            }
            depth -= 1
        default:
            break
        }
    }
    return index
}

/// Returns all direct children of `scope` in document order.
/// Complexity: O(events in scope).
func _streamDirectChildren(events: [XMLStreamEvent], scope: EventRange) -> [EventRange] {
    var children: [EventRange] = []
    var depth = 0
    var childStart = -1
    for idx in (scope.start + 1)..<scope.end {
        switch events[idx] {
        case .startElement:
            depth += 1
            if depth == 1 { childStart = idx }
        case .endElement:
            if depth == 1 {
                children.append(EventRange(start: childStart, end: idx))
            }
            depth -= 1
        default:
            break
        }
    }
    return children
}

/// Concatenates `.text` and `.cdata` events at depth 0 inside `scope`.
func _streamExtractText(events: [XMLStreamEvent], scope: EventRange) -> String {
    var result = ""
    var depth = 0
    for idx in (scope.start + 1)..<scope.end {
        switch events[idx] {
        case .startElement:
            depth += 1
        case .endElement:
            depth -= 1
        case .text(let str) where depth == 0:
            result += str
        case .cdata(let str) where depth == 0:
            result += str
        default:
            break
        }
    }
    return result
}

// MARK: - XMLStreamEventDecoder

/// A `Decoder` that reads directly from `[XMLStreamEvent]` via an `EventRange`
/// cursor, eliminating intermediate `XMLTreeDocument` allocation.
///
/// Used exclusively by `XMLStreamDecoder.decodeImpl`.
final class XMLStreamEventDecoder: Decoder {
    let events: [XMLStreamEvent]
    let scope: EventRange
    let options: _XMLDecoderOptions
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    /// Lightweight oracle used only for scalar type conversion via
    /// `decodeScalarFromLexical`. The dummy element is never navigated.
    let scalarOracle: _XMLTreeDecoder

    init(
        events: [XMLStreamEvent],
        scope: EventRange,
        options: _XMLDecoderOptions,
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:],
        codingPath: [CodingKey] = []
    ) {
        self.events = events
        self.scope = scope
        self.options = options
        self.fieldNodeKinds = fieldNodeKinds
        self.codingPath = codingPath
        let dummy = XMLTreeElement(name: XMLQualifiedName(localName: "_"))
        self.scalarOracle = _XMLTreeDecoder(options: options, codingPath: [], node: dummy)
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(_StreamKeyedContainer<Key>(decoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        _StreamUnkeyedContainer(decoder: self, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _StreamSingleValueContainer(decoder: self, codingPath: codingPath)
    }

    /// Transforms a Swift coding key name to its XML element/attribute name,
    /// mirroring the `xmlName(for:)` logic in `_XMLKeyedDecodingContainer`.
    func xmlName(for rawKey: String) -> String {
        switch options.keyTransformStrategy {
        case .useDefaultKeys:
            return rawKey
        case .custom(let closure):
            return closure(rawKey)
        default:
            break
        }
        if let cached = options.keyNameCache.storage[rawKey] {
            return cached
        }
        let transformed = options.keyTransformStrategy.transform(rawKey)
        options.keyNameCache.storage[rawKey] = transformed
        return transformed
    }
}

// MARK: - _StreamKeyedContainer

// swiftlint:disable type_body_length
struct _StreamKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: XMLStreamEventDecoder
    var codingPath: [CodingKey]
    /// XML local names of child elements mapped to their ordered EventRanges.
    private let childIndex: [String: [EventRange]]
    /// XML attribute names mapped to their string values.
    private let attributes: [String: String]

    init(decoder: XMLStreamEventDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
        if case .startElement(_, let attrs, _) = decoder.events[decoder.scope.start] {
            var dict: [String: String] = [:]
            for attr in attrs {
                dict[attr.name.localName] = attr.value
            }
            self.attributes = dict
        } else {
            self.attributes = [:]
        }
        self.childIndex = _streamBuildChildIndex(events: decoder.events, scope: decoder.scope)
    }

    var allKeys: [Key] {
        Set(childIndex.keys).union(attributes.keys)
            .compactMap { Key(stringValue: $0) }
            .sorted { $0.stringValue < $1.stringValue }
    }

    func contains(_ key: Key) -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return false }
        let name = decoder.xmlName(for: key.stringValue)
        return childIndex[name] != nil || attributes[name] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if resolvedNodeKind(for: key, valueType: Never.self) == .ignored { return true }
        let name = decoder.xmlName(for: key.stringValue)
        if attributes[name] != nil { return false }
        guard let ranges = childIndex[name], let range = ranges.first else { return true }
        return isNil(scope: range)
    }

    func decode(_ type: Bool.Type,   forKey key: Key) throws -> Bool   { try decodeScalar(type, forKey: key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeScalar(type, forKey: key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeScalar(type, forKey: key) }
    func decode(_ type: Float.Type,  forKey key: Key) throws -> Float  { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int.Type,    forKey key: Key) throws -> Int    { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int8.Type,   forKey key: Key) throws -> Int8   { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int16.Type,  forKey key: Key) throws -> Int16  { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int32.Type,  forKey key: Key) throws -> Int32  { try decodeScalar(type, forKey: key) }
    func decode(_ type: Int64.Type,  forKey key: Key) throws -> Int64  { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt.Type,   forKey key: Key) throws -> UInt   { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt8.Type,  forKey key: Key) throws -> UInt8  { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeScalar(type, forKey: key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeScalar(type, forKey: key) }

    // swiftlint:disable:next function_body_length
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute   { return try decodeAttribute(type, forKey: key) }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        let name = decoder.xmlName(for: key.stringValue)
        guard let ranges = childIndex[name], let range = ranges.first else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_010] Missing key '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let childPath = codingPath + [key]
        if let scalar: T = try tryDecodeScalar(type, from: range, codingPath: childPath, localName: name) {
            return scalar
        }
        if decoder.scalarOracle.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_011] Unable to decode scalar '\(key.stringValue)' at path '\(renderPath(childPath))'."
            )
        }
        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: nestedOptions,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            codingPath: childPath
        )
        return try T(from: nested)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_012] Cannot decode nested keyed container from attribute '\(key.stringValue)'."
            )
        }
        let name = decoder.xmlName(for: key.stringValue)
        guard let ranges = childIndex[name], let range = ranges.first else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_013] Missing nested key '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let childPath = codingPath + [key]
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: childPath
        )
        return KeyedDecodingContainer(_StreamKeyedContainer<NestedKey>(decoder: nested, codingPath: childPath))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_014] Cannot decode nested unkeyed container from attribute '\(key.stringValue)'."
            )
        }
        let name = decoder.xmlName(for: key.stringValue)
        guard let ranges = childIndex[name], let range = ranges.first else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_015] Missing nested unkeyed key '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let childPath = codingPath + [key]
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: childPath
        )
        return _StreamUnkeyedContainer(decoder: nested, codingPath: childPath)
    }

    func superDecoder() throws -> Decoder {
        XMLStreamEventDecoder(
            events: decoder.events,
            scope: decoder.scope,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: codingPath
        )
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        let name = decoder.xmlName(for: key.stringValue)
        guard let ranges = childIndex[name], let range = ranges.first else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_016] Missing super key '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let childPath = codingPath + [key]
        return XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: childPath
        )
    }

    // MARK: - Private helpers

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

    private func decodeScalar<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute   { return try decodeAttribute(type, forKey: key) }
        if nodeKind == .textContent { return try decodeTextContent(type, forKey: key) }

        let name = decoder.xmlName(for: key.stringValue)
        guard let ranges = childIndex[name], let range = ranges.first else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_020] Missing scalar key '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let childPath = codingPath + [key]
        guard let scalar: T = try tryDecodeScalar(type, from: range, codingPath: childPath, localName: name) else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_021] Unable to decode scalar '\(key.stringValue)' at path '\(renderPath(childPath))'."
            )
        }
        return scalar
    }

    private func tryDecodeScalar<T: Decodable>(
        _ type: T.Type,
        from range: EventRange,
        codingPath: [CodingKey],
        localName: String
    ) throws -> T? {
        if type == String.self {
            return _streamExtractText(events: decoder.events, scope: range) as? T
        }
        let lexical = _streamExtractText(events: decoder.events, scope: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lexical.isEmpty else { return nil }
        return try decoder.scalarOracle.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: localName,
            isAttribute: false
        )
    }

    private func decodeAttribute<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let name = decoder.xmlName(for: key.stringValue)
        guard let value = attributes[name] else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_030] Missing attribute '\(key.stringValue)' at path '\(renderPath())'."
            )
        }
        let attrPath = codingPath + [key]
        if let wrapperType = type as? _XMLAttributeDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeAttributeLexicalValue(
                value,
                using: decoder.scalarOracle,
                codingPath: attrPath,
                key: key.stringValue
            )
            guard let typed = wrapped as? T else {
                throw XMLParsingError.parseFailed(
                    message: "[STREAM_DEC_031] Cannot cast decoded attribute '\(key.stringValue)' to expected type."
                )
            }
            return typed
        }
        guard let scalar = try decoder.scalarOracle.decodeScalarFromLexical(
            value,
            as: type,
            codingPath: attrPath,
            localName: key.stringValue,
            isAttribute: true
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_032] Cannot decode attribute '\(key.stringValue)' into non-scalar type."
            )
        }
        return scalar
    }

    private func decodeTextContent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let textPath = codingPath + [key]
        let lexical = _streamExtractText(events: decoder.events, scope: decoder.scope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let wrapperType = type as? _XMLTextContentDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeTextContentLexicalValue(
                lexical,
                using: decoder.scalarOracle,
                codingPath: textPath,
                key: key.stringValue
            )
            guard let typed = wrapped as? T else {
                throw XMLParsingError.parseFailed(
                    message: "[STREAM_DEC_041] Cannot cast decoded text content '\(key.stringValue)' to expected type."
                )
            }
            return typed
        }
        guard let scalar = try decoder.scalarOracle.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: textPath,
            localName: key.stringValue,
            isAttribute: false
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_042] Cannot decode text content '\(key.stringValue)' into non-scalar type."
            )
        }
        return scalar
    }

    /// Returns true when the element represented by `scope` has no direct child
    /// elements and no non-empty text content — mirrors `_XMLTreeDecoder.isNilElement`.
    private func isNil(scope: EventRange) -> Bool {
        var depth = 0
        for idx in (scope.start + 1)..<scope.end {
            switch decoder.events[idx] {
            case .startElement:
                depth += 1
                if depth == 1 { return false }
            case .endElement:
                depth -= 1
            default:
                break
            }
        }
        return _streamExtractText(events: decoder.events, scope: scope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func renderPath(_ path: [CodingKey]? = nil) -> String {
        let keys = path ?? codingPath
        let rendered = keys.map { $0.stringValue }.joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}
// swiftlint:enable type_body_length

// MARK: - _StreamUnkeyedContainer

struct _StreamUnkeyedContainer: UnkeyedDecodingContainer {
    private let decoder: XMLStreamEventDecoder
    private(set) var codingPath: [CodingKey]
    private let children: [EventRange]
    private(set) var currentIndex: Int = 0

    init(decoder: XMLStreamEventDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
        let all = _streamDirectChildren(events: decoder.events, scope: decoder.scope)
        let itemName = decoder.options.itemElementName
        let filtered = all.filter { range -> Bool in
            guard case .startElement(let name, _, _) = decoder.events[range.start] else { return false }
            return name.localName == itemName
        }
        self.children = filtered.isEmpty ? all : filtered
    }

    var count: Int? { children.count }
    var isAtEnd: Bool { currentIndex >= children.count }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return true }
        let range = children[currentIndex]
        let isNilElem = isNil(scope: range)
        if isNilElem { currentIndex += 1 }
        return isNilElem
    }

    mutating func decode(_ type: Bool.Type)   throws -> Bool   { try decodeScalarItem(type) }
    mutating func decode(_ type: String.Type) throws -> String { try decodeScalarItem(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeScalarItem(type) }
    mutating func decode(_ type: Float.Type)  throws -> Float  { try decodeScalarItem(type) }
    mutating func decode(_ type: Int.Type)    throws -> Int    { try decodeScalarItem(type) }
    mutating func decode(_ type: Int8.Type)   throws -> Int8   { try decodeScalarItem(type) }
    mutating func decode(_ type: Int16.Type)  throws -> Int16  { try decodeScalarItem(type) }
    mutating func decode(_ type: Int32.Type)  throws -> Int32  { try decodeScalarItem(type) }
    mutating func decode(_ type: Int64.Type)  throws -> Int64  { try decodeScalarItem(type) }
    mutating func decode(_ type: UInt.Type)   throws -> UInt   { try decodeScalarItem(type) }
    mutating func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeScalarItem(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeScalarItem(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeScalarItem(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeScalarItem(type) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let range = try currentRange()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        if let scalar: T = try tryDecodeScalar(type, from: range, codingPath: itemPath) {
            return scalar
        }
        if decoder.scalarOracle.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_050] Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'."
            )
        }
        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: nestedOptions,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            codingPath: itemPath
        )
        return try T(from: nested)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let range = try currentRange()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: itemPath
        )
        return KeyedDecodingContainer(_StreamKeyedContainer<NestedKey>(decoder: nested, codingPath: itemPath))
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let range = try currentRange()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        let nested = XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: itemPath
        )
        return _StreamUnkeyedContainer(decoder: nested, codingPath: itemPath)
    }

    mutating func superDecoder() throws -> Decoder {
        let range = try currentRange()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        return XMLStreamEventDecoder(
            events: decoder.events,
            scope: range,
            options: decoder.options,
            fieldNodeKinds: decoder.fieldNodeKinds,
            codingPath: itemPath
        )
    }

    // MARK: - Private helpers

    private mutating func decodeScalarItem<T: Decodable>(_ type: T.Type) throws -> T {
        let range = try currentRange()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        guard let scalar: T = try tryDecodeScalar(type, from: range, codingPath: itemPath) else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_051] Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'."
            )
        }
        return scalar
    }

    private func tryDecodeScalar<T: Decodable>(
        _ type: T.Type,
        from range: EventRange,
        codingPath: [CodingKey]
    ) throws -> T? {
        if type == String.self {
            return _streamExtractText(events: decoder.events, scope: range) as? T
        }
        let lexical = _streamExtractText(events: decoder.events, scope: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lexical.isEmpty else { return nil }
        return try decoder.scalarOracle.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: nil,
            isAttribute: false
        )
    }

    private func currentRange() throws -> EventRange {
        guard !isAtEnd else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_052] Unkeyed container exhausted at path '\(renderPath())'."
            )
        }
        return children[currentIndex]
    }

    private func isNil(scope: EventRange) -> Bool {
        var depth = 0
        for idx in (scope.start + 1)..<scope.end {
            switch decoder.events[idx] {
            case .startElement:
                depth += 1
                if depth == 1 { return false }
            case .endElement:
                depth -= 1
            default:
                break
            }
        }
        return _streamExtractText(events: decoder.events, scope: scope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func renderPath(_ path: [CodingKey]? = nil) -> String {
        let keys = path ?? codingPath
        let rendered = keys.map { $0.stringValue }.joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

// MARK: - _StreamSingleValueContainer

struct _StreamSingleValueContainer: SingleValueDecodingContainer {
    let decoder: XMLStreamEventDecoder
    var codingPath: [CodingKey]

    func decodeNil() -> Bool {
        var depth = 0
        for idx in (decoder.scope.start + 1)..<decoder.scope.end {
            switch decoder.events[idx] {
            case .startElement:
                depth += 1
                if depth == 1 { return false }
            case .endElement:
                depth -= 1
            default:
                break
            }
        }
        return _streamExtractText(events: decoder.events, scope: decoder.scope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func decode(_ type: Bool.Type)   throws -> Bool   { try decodeScalar(type) }
    func decode(_ type: String.Type) throws -> String { try decodeScalar(type) }
    func decode(_ type: Double.Type) throws -> Double { try decodeScalar(type) }
    func decode(_ type: Float.Type)  throws -> Float  { try decodeScalar(type) }
    func decode(_ type: Int.Type)    throws -> Int    { try decodeScalar(type) }
    func decode(_ type: Int8.Type)   throws -> Int8   { try decodeScalar(type) }
    func decode(_ type: Int16.Type)  throws -> Int16  { try decodeScalar(type) }
    func decode(_ type: Int32.Type)  throws -> Int32  { try decodeScalar(type) }
    func decode(_ type: Int64.Type)  throws -> Int64  { try decodeScalar(type) }
    func decode(_ type: UInt.Type)   throws -> UInt   { try decodeScalar(type) }
    func decode(_ type: UInt8.Type)  throws -> UInt8  { try decodeScalar(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeScalar(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeScalar(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeScalar(type) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let scalar: T = try tryDecodeScalar(type) { return scalar }
        if decoder.scalarOracle.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_060] Unable to decode single-value scalar at path '\(renderPath())'."
            )
        }
        return try T(from: decoder)
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        guard let scalar: T = try tryDecodeScalar(type) else {
            throw XMLParsingError.parseFailed(
                message: "[STREAM_DEC_061] Unable to decode scalar at path '\(renderPath())'."
            )
        }
        return scalar
    }

    private func tryDecodeScalar<T: Decodable>(_ type: T.Type) throws -> T? {
        let elemName: String
        if case .startElement(let name, _, _) = decoder.events[decoder.scope.start] {
            elemName = name.localName
        } else {
            elemName = ""
        }
        if type == String.self {
            return _streamExtractText(events: decoder.events, scope: decoder.scope) as? T
        }
        let lexical = _streamExtractText(events: decoder.events, scope: decoder.scope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lexical.isEmpty else { return nil }
        return try decoder.scalarOracle.decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: elemName,
            isAttribute: false
        )
    }

    private func renderPath() -> String {
        let rendered = codingPath.map { $0.stringValue }.joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}