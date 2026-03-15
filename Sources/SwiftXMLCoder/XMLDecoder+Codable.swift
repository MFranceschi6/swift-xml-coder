import Foundation

// MARK: - Architecture: XMLDecoder Codable implementation
//
// This file implements the internal Codable container types that back `XMLDecoder`.
// Types are declared at file scope (not nested) because Swift's Codable protocol
// conformance synthesis requires them to be visible there.
//
// ## Decode pipeline
//
//   XMLDecoder.decode(T.self, from: data)
//     → XMLTreeParser parses raw Data into an immutable XMLTreeDocument
//     → creates _XMLTreeDecoder wrapping the root XMLTreeElement
//     → calls T(from: decoder) triggering the Codable machinery:
//          → _XMLKeyedDecodingContainer   (struct/class fields)
//          → _XMLUnkeyedDecodingContainer (arrays/sequences)
//          → _XMLSingleValueDecodingContainer (scalars, enums)
//
// ## Field node kind resolution (resolvedNodeKind priority chain)
//
// Mirrors the encoder's priority chain exactly (see XMLEncoder+Codable.swift):
//   1. Type-level: `_XMLFieldKindOverrideType` conformance on the expected type.
//   2. Macro-level: `xmlFieldNodeKinds` from `XMLFieldCodingOverrideProvider`.
//   3. Runtime: `XMLFieldCodingOverrides` on the decoder configuration.
//   4. Default: `.element` — look for a matching child element.
//
// ## Scalar decoding
//
// `_XMLTreeDecoder.decodeScalar(_:from:codingPath:)` extracts raw text from an
// element's child text/cdata nodes, then dispatches through `decodeScalarFromLexical`
// for each Foundation scalar type, producing a typed diagnostic error on failure.
//
// ## Nil semantics
//
// `isNilElement(_:)` returns true when an element has no child elements AND no
// non-empty text content.  Keyed nil resolution:
//   - attribute present → not nil
//   - child element absent → nil
//   - child element present but empty → nil
extension XMLDecoder {
    // Codable container types are implemented as file-private types below.
    // This extension anchor satisfies the '+Codable' file-naming convention.
}

struct _XMLDecoderOptions {
    let itemElementName: String
    let fieldCodingOverrides: XMLFieldCodingOverrides
    let dateDecodingStrategy: XMLDecoder.DateDecodingStrategy
    let dataDecodingStrategy: XMLDecoder.DataDecodingStrategy
    let validationPolicy: XMLValidationPolicy
    /// Per-property date format hints populated from `XMLDateCodingOverrideProvider`.
    var perPropertyDateHints: [String: XMLDateFormatHint] = [:]

    init(configuration: XMLDecoder.Configuration) {
        self.itemElementName = configuration.itemElementName
        self.fieldCodingOverrides = configuration.fieldCodingOverrides
        self.dateDecodingStrategy = configuration.dateDecodingStrategy
        self.dataDecodingStrategy = configuration.dataDecodingStrategy
        self.validationPolicy = configuration.validationPolicy
    }
}

struct _XMLDecodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "Index\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index\(index)"
        self.intValue = index
    }
}

final class _XMLTreeDecoder: Decoder {
    let options: _XMLDecoderOptions
    let node: XMLTreeElement
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(
        options: _XMLDecoderOptions,
        codingPath: [CodingKey],
        node: XMLTreeElement,
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:]
    ) {
        self.options = options
        self.codingPath = codingPath
        self.node = node
        self.fieldNodeKinds = fieldNodeKinds
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = _XMLKeyedDecodingContainer<Key>(decoder: self, codingPath: codingPath)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        _XMLUnkeyedDecodingContainer(decoder: self, codingPath: codingPath, node: node)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        _XMLSingleValueDecodingContainer(decoder: self, codingPath: codingPath, node: node)
    }

    func firstChild(named localName: String, in element: XMLTreeElement) -> XMLTreeElement? {
        childElements(of: element).first(where: { $0.name.localName == localName })
    }

    func attribute(named localName: String, in element: XMLTreeElement) -> XMLTreeAttribute? {
        element.attributes.first(where: { $0.name.localName == localName })
    }

    func childElements(of element: XMLTreeElement) -> [XMLTreeElement] {
        element.children.compactMap { child in
            guard case .element(let childElement) = child else {
                return nil
            }
            return childElement
        }
    }

    func lexicalText(of element: XMLTreeElement) -> String? {
        let textChunks = element.children.compactMap { child -> String? in
            switch child {
            case .text(let value):
                return value
            case .cdata(let value):
                return value
            case .element, .comment:
                return nil
            }
        }

        guard textChunks.isEmpty == false else {
            return nil
        }
        return textChunks.joined()
    }

    func isNilElement(_ element: XMLTreeElement) -> Bool {
        let hasElementChildren = childElements(of: element).isEmpty == false
        guard hasElementChildren == false else {
            return false
        }
        let lexical = lexicalText(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return lexical.isEmpty
    }

    func decodeScalar<T: Decodable>(
        _ type: T.Type,
        from element: XMLTreeElement,
        codingPath: [CodingKey]
    ) throws -> T? {
        if type == String.self {
            let value = lexicalText(of: element) ?? ""
            return value as? T
        }

        guard let lexical = lexicalText(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
              lexical.isEmpty == false else {
            return nil
        }

        return try decodeScalarFromLexical(
            lexical,
            as: type,
            codingPath: codingPath,
            localName: element.name.localName,
            isAttribute: false
        )
    }

    func isKnownScalarType(_ type: Any.Type) -> Bool {
        type == Bool.self ||
            type == String.self ||
            type == Double.self ||
            type == Float.self ||
            type == Int.self ||
            type == Int8.self ||
            type == Int16.self ||
            type == Int32.self ||
            type == Int64.self ||
            type == UInt.self ||
            type == UInt8.self ||
            type == UInt16.self ||
            type == UInt32.self ||
            type == UInt64.self ||
            type == Decimal.self ||
            type == URL.self ||
            type == UUID.self ||
            type == Date.self ||
            type == Data.self
    }

    func decodeScalarFromLexical<T: Decodable>(
        _ lexical: String,
        as type: T.Type,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> T? {
        if type == String.self {
            return lexical as? T
        }

        if type == Bool.self {
            guard let parsed = parseBool(lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_BOOL_PARSE_FAILED] Unable to parse Bool from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
        }
        if type == Int.self { return try parseInteger(lexical, as: Int.self, codingPath: codingPath) as? T }
        if type == Int8.self { return try parseInteger(lexical, as: Int8.self, codingPath: codingPath) as? T }
        if type == Int16.self { return try parseInteger(lexical, as: Int16.self, codingPath: codingPath) as? T }
        if type == Int32.self { return try parseInteger(lexical, as: Int32.self, codingPath: codingPath) as? T }
        if type == Int64.self { return try parseInteger(lexical, as: Int64.self, codingPath: codingPath) as? T }
        if type == UInt.self { return try parseInteger(lexical, as: UInt.self, codingPath: codingPath) as? T }
        if type == UInt8.self { return try parseInteger(lexical, as: UInt8.self, codingPath: codingPath) as? T }
        if type == UInt16.self { return try parseInteger(lexical, as: UInt16.self, codingPath: codingPath) as? T }
        if type == UInt32.self { return try parseInteger(lexical, as: UInt32.self, codingPath: codingPath) as? T }
        if type == UInt64.self { return try parseInteger(lexical, as: UInt64.self, codingPath: codingPath) as? T }

        if type == Double.self {
            guard let parsed = Double(lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_DOUBLE_PARSE_FAILED] Unable to parse Double from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
        }

        if type == Float.self {
            guard let parsed = Float(lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_FLOAT_PARSE_FAILED] Unable to parse Float from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
        }

        if type == Decimal.self {
            guard let parsed = Decimal(string: lexical, locale: Locale(identifier: "en_US_POSIX")) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_DECIMAL_PARSE_FAILED] Unable to parse Decimal from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
        }

        if type == URL.self {
            #if !canImport(Darwin) && swift(<6.0)
            guard let parsed = _xmlParityDecodeURL(lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_URL_PARSE_FAILED] Unable to parse URL from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
            #else
            guard let parsed = URL(string: lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_URL_PARSE_FAILED] Unable to parse URL from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
            #endif
        }

        if type == UUID.self {
            guard let parsed = UUID(uuidString: lexical) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_UUID_PARSE_FAILED] Unable to parse UUID from '\(lexical)' at path '\(renderCodingPath(codingPath))'."
                )
            }
            return parsed as? T
        }

        if type == Date.self {
            if case .deferredToDate = options.dateDecodingStrategy {
                return nil
            }
            let parsed = try parseDate(
                lexical,
                codingPath: codingPath,
                localName: localName,
                isAttribute: isAttribute
            )
            return parsed as? T
        }

        if type == Data.self {
            if case .deferredToData = options.dataDecodingStrategy {
                return nil
            }
            let parsed = try parseData(lexical, codingPath: codingPath)
            return parsed as? T
        }

        return nil
    }

    private func parseInteger<T: LosslessStringConvertible>(
        _ value: String,
        as type: T.Type,
        codingPath: [CodingKey]
    ) throws -> T {
        guard let parsed = T(value) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5C_INTEGER_PARSE_FAILED] Unable to parse integer from '\(value)' at path '\(renderCodingPath(codingPath))'."
            )
        }
        return parsed
    }

    private func requiredLexicalValue(from element: XMLTreeElement, codingPath: [CodingKey]) throws -> String {
        let lexical = lexicalText(of: element)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lexical = lexical, lexical.isEmpty == false else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5C_EMPTY_LEXICAL_VALUE] Empty lexical value at path '\(renderCodingPath(codingPath))'."
            )
        }
        return lexical
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1":
            return true
        case "false", "0":
            return false
        default:
            return nil
        }
    }

    private func parseDate(
        _ lexicalValue: String,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> Date {
        let context = XMLDateCodingContext(
            codingPath: codingPath.map(\.stringValue),
            localName: localName,
            namespaceURI: nil,
            isAttribute: isAttribute
        )
        // Per-property hint overrides the global strategy when present.
        let effectiveStrategy: XMLDecoder.DateDecodingStrategy
        if let name = localName, let hint = options.perPropertyDateHints[name] {
            effectiveStrategy = hint.decodingStrategy
        } else {
            effectiveStrategy = options.dateDecodingStrategy
        }
        if let parsed = try attemptParseDate(lexicalValue, strategy: effectiveStrategy, context: context) {
            return parsed
        }
        throw XMLParsingError.parseFailed(
            message: "[XML6_5C_DATE_PARSE_FAILED] Unable to parse Date from '\(lexicalValue)' at path '\(renderCodingPath(codingPath))'."
        )
    }

    private func attemptParseDate(
        _ lexicalValue: String,
        strategy: XMLDecoder.DateDecodingStrategy,
        context: XMLDateCodingContext
    ) throws -> Date? {
        switch strategy {
        case .deferredToDate:
            return nil
        case .secondsSince1970:
            guard let seconds = Double(lexicalValue) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        case .millisecondsSince1970:
            guard let millis = Double(lexicalValue) else { return nil }
            return Date(timeIntervalSince1970: millis / 1000.0)
        case .xsdDateTimeISO8601, .iso8601:
            return _XMLTemporalFoundationSupport.parseISO8601(lexicalValue)
        case .xsdDate:
            return _XMLTemporalFoundationSupport.parseXSDDate(lexicalValue)
        case .xsdTime:
            return XMLTime(lexicalValue: lexicalValue)?.toDate()
        case .xsdGYear:
            return XMLGYear(lexicalValue: lexicalValue)?.toDate()
        case .xsdGYearMonth:
            return XMLGYearMonth(lexicalValue: lexicalValue)?.toDate()
        case .xsdGMonth:
            guard let gMonth = XMLGMonth(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gMonth.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000; comps.month = gMonth.month; comps.day = 1
            comps.hour = 0; comps.minute = 0; comps.second = 0
            return cal.date(from: comps)
        case .xsdGDay:
            guard let gDay = XMLGDay(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gDay.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000; comps.month = 1; comps.day = gDay.day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            return cal.date(from: comps)
        case .xsdGMonthDay:
            guard let gMonthDay = XMLGMonthDay(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gMonthDay.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000; comps.month = gMonthDay.month; comps.day = gMonthDay.day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            return cal.date(from: comps)
        case .formatter(let descriptor):
            return _XMLTemporalFoundationSupport.makeDateFormatter(from: descriptor).date(from: lexicalValue)
        case .multiple(let strategies):
            for strategy in strategies {
                if let parsed = try attemptParseDate(lexicalValue, strategy: strategy, context: context) {
                    return parsed
                }
            }
            return nil
        case .custom(let closure):
            do {
                return try closure(lexicalValue, context)
            } catch let error as XMLParsingError {
                throw error
            } catch {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_DATE_PARSE_FAILED] Custom date decoder failed at path '\(context.codingPath.joined(separator: "."))': \(error)."
                )
            }
        }
    }

    private func parseData(_ lexicalValue: String, codingPath: [CodingKey]) throws -> Data {
        switch options.dataDecodingStrategy {
        case .deferredToData:
            let path = renderCodingPath(codingPath)
            throw XMLParsingError.parseFailed(
                message: "[XML6_5B_DATA_UNSUPPORTED_STRATEGY] Data strategy deferredToData requires deferred decoding at path '\(path)'."
            )
        case .base64:
            let normalized = lexicalValue.filter { $0.isWhitespace == false }
            guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5B_DATA_PARSE_FAILED] Unable to parse base64 Data at path '\(renderCodingPath(codingPath))'."
                )
            }
            return data
        case .hex:
            guard let data = decodeHex(lexicalValue.filter { $0.isWhitespace == false }) else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5B_DATA_PARSE_FAILED] Unable to parse hex Data at path '\(renderCodingPath(codingPath))'."
                )
            }
            return data
        }
    }

    private func decodeHex(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else {
            return nil
        }
        var data = Data(capacity: value.count / 2)
        var cursor = value.startIndex
        while cursor < value.endIndex {
            let next = value.index(cursor, offsetBy: 2)
            let byteString = value[cursor..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            cursor = next
        }
        return data
    }

    private func renderCodingPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }

}

struct _XMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = Key

    private let decoder: _XMLTreeDecoder
    private(set) var codingPath: [CodingKey]

    init(decoder: _XMLTreeDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder
        self.codingPath = codingPath
    }

    var allKeys: [Key] {
        let elementNames = decoder.childElements(of: decoder.node).map { $0.name.localName }
        let attributeNames = decoder.node.attributes.map { $0.name.localName }
        let names = Set(elementNames + attributeNames)
        return names.compactMap { Key(stringValue: $0) }.sorted(by: { $0.stringValue < $1.stringValue })
    }

    func contains(_ key: Key) -> Bool {
        decoder.firstChild(named: key.stringValue, in: decoder.node) != nil ||
            decoder.attribute(named: key.stringValue, in: decoder.node) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        if decoder.attribute(named: key.stringValue, in: decoder.node) != nil {
            return false
        }
        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            return true
        }
        return decoder.isNilElement(element)
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
        if nodeKind == .attribute {
            return try decodeAttribute(type, forKey: key)
        }

        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_KEY_NOT_FOUND] Missing key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }

        let childPath = codingPath + [key]
        if let scalar: T = try decoder.decodeScalar(type, from: element, codingPath: childPath) {
            return scalar
        }
        if decoder.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar key '\(key.stringValue)' at path '\(renderPath(childPath))'."
            )
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLTreeDecoder(
            options: nestedOptions,
            codingPath: childPath,
            node: element,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self)
        )
        return try T(from: nestedDecoder)
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED] Cannot decode nested keyed container from attribute '\(key.stringValue)'."
            )
        }

        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }

        let nestedDecoder = _XMLTreeDecoder(
            options: decoder.options,
            codingPath: codingPath + [key],
            node: element
        )
        return try nestedDecoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        if let nodeKind = decoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue),
           nodeKind == .attribute {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED] Cannot decode nested unkeyed container from attribute '\(key.stringValue)'."
            )
        }

        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_KEY_NOT_FOUND] Missing nested unkeyed key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }

        let nestedDecoder = _XMLTreeDecoder(
            options: decoder.options,
            codingPath: codingPath + [key],
            node: element
        )
        return try nestedDecoder.unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        _XMLTreeDecoder(
            options: decoder.options,
            codingPath: codingPath,
            node: decoder.node,
            fieldNodeKinds: decoder.fieldNodeKinds
        )
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_KEY_NOT_FOUND] Missing super key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }

        return _XMLTreeDecoder(
            options: decoder.options,
            codingPath: codingPath + [key],
            node: element
        )
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let nodeKind = resolvedNodeKind(for: key, valueType: type)
        if nodeKind == .attribute {
            return try decodeAttribute(type, forKey: key)
        }

        guard let element = decoder.firstChild(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_KEY_NOT_FOUND] Missing scalar key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }
        guard let scalar: T = try decoder.decodeScalar(type, from: element, codingPath: codingPath + [key]) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar key '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }
        return scalar
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
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
        guard let attribute = decoder.attribute(named: key.stringValue, in: decoder.node) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_NOT_FOUND] Missing attribute '\(key.stringValue)' at path '\(renderPath(codingPath))'."
            )
        }

        let attributePath = codingPath + [key]
        if let wrapperType = type as? _XMLAttributeDecodableValue.Type {
            let wrapped = try wrapperType._xmlDecodeAttributeLexicalValue(
                attribute.value,
                using: decoder,
                codingPath: attributePath,
                key: key.stringValue
            )
            guard let typed = wrapped as? T else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_6_ATTRIBUTE_DECODE_CAST_FAILED] Unable to cast decoded attribute '\(key.stringValue)' to expected type."
                )
            }
            return typed
        }

        guard let scalar = try decoder.decodeScalarFromLexical(
            attribute.value,
            as: type,
            codingPath: attributePath,
            localName: key.stringValue,
            isAttribute: true
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_DECODE_UNSUPPORTED] Unable to decode attribute '\(key.stringValue)' into non-scalar type."
            )
        }
        return scalar
    }
}

struct _XMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    private let decoder: _XMLTreeDecoder
    private(set) var codingPath: [CodingKey]
    private let elements: [XMLTreeElement]
    private(set) var currentIndex: Int = 0

    init(decoder: _XMLTreeDecoder, codingPath: [CodingKey], node: XMLTreeElement) {
        self.decoder = decoder
        self.codingPath = codingPath
        let allElements = decoder.childElements(of: node)
        let itemElements = allElements.filter { $0.name.localName == decoder.options.itemElementName }
        self.elements = itemElements.isEmpty ? allElements : itemElements
    }

    var count: Int? { elements.count }
    var isAtEnd: Bool { currentIndex >= elements.count }

    mutating func decodeNil() throws -> Bool {
        guard isAtEnd == false else {
            return true
        }
        let element = elements[currentIndex]
        let isNil = decoder.isNilElement(element)
        if isNil {
            currentIndex += 1
        }
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
        let element = try currentElement()
        defer { currentIndex += 1 }

        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        if let scalar: T = try decoder.decodeScalar(type, from: element, codingPath: itemPath) {
            return scalar
        }
        if decoder.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'."
            )
        }

        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLTreeDecoder(
            options: nestedOptions,
            codingPath: itemPath,
            node: element,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self)
        )
        return try T(from: nestedDecoder)
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey>
    where NestedKey: CodingKey {
        let element = try currentElement()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nestedDecoder = _XMLTreeDecoder(options: decoder.options, codingPath: codingPath + [indexKey], node: element)
        return try nestedDecoder.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let element = try currentElement()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let nestedDecoder = _XMLTreeDecoder(options: decoder.options, codingPath: codingPath + [indexKey], node: element)
        return try nestedDecoder.unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        let element = try currentElement()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        return _XMLTreeDecoder(options: decoder.options, codingPath: codingPath + [indexKey], node: element)
    }

    private mutating func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        let element = try currentElement()
        defer { currentIndex += 1 }
        let indexKey = _XMLDecodingKey(index: currentIndex)
        let itemPath = codingPath + [indexKey]
        guard let scalar: T = try decoder.decodeScalar(type, from: element, codingPath: itemPath) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode unkeyed scalar at path '\(renderPath(itemPath))'."
            )
        }
        return scalar
    }

    private func currentElement() throws -> XMLTreeElement {
        guard isAtEnd == false else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_UNKEYED_OUT_OF_RANGE] Unkeyed container is at end at path '\(renderPath(codingPath))'."
            )
        }
        return elements[currentIndex]
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

struct _XMLSingleValueDecodingContainer: SingleValueDecodingContainer {
    private let decoder: _XMLTreeDecoder
    private(set) var codingPath: [CodingKey]
    private let node: XMLTreeElement

    init(decoder: _XMLTreeDecoder, codingPath: [CodingKey], node: XMLTreeElement) {
        self.decoder = decoder
        self.codingPath = codingPath
        self.node = node
    }

    func decodeNil() -> Bool {
        decoder.isNilElement(node)
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
        if let scalar: T = try decoder.decodeScalar(type, from: node, codingPath: codingPath) {
            return scalar
        }
        if decoder.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode single-value scalar at path '\(renderPath(codingPath))'."
            )
        }
        var nestedOptions = decoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let nestedDecoder = _XMLTreeDecoder(
            options: nestedOptions,
            codingPath: codingPath,
            node: node,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self)
        )
        return try T(from: nestedDecoder)
    }

    private func decodeScalar<T: Decodable>(_ type: T.Type) throws -> T {
        guard let scalar: T = try decoder.decodeScalar(type, from: node, codingPath: codingPath) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode single-value scalar at path '\(renderPath(codingPath))'."
            )
        }
        return scalar
    }

    private func renderPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}

#if !canImport(Darwin) && swift(<6.0)
/// Hotfix for Linux swift-corelibs-foundation (pre-Swift 6 Foundation rewrite).
///
/// The old Linux URL parser may accept unbalanced IPv6 brackets instead of returning nil,
/// and does not auto-percent-encode spaces (both handled correctly by Swift 6 swift-foundation).
/// Normalises both behaviours so Linux Swift 5 decoding matches macOS and Linux Swift 6+.
internal func _xmlParityDecodeURL(_ lexical: String) -> URL? {
    var balance = 0
    for char in lexical {
        if char == "[" { balance += 1 } else if char == "]" {
            balance -= 1
            if balance < 0 { return nil }
        }
    }
    guard balance == 0 else { return nil }

    if lexical.range(of: " ") != nil {
        let encoded = lexical.replacingOccurrences(of: " ", with: "%20")
        return URL(string: encoded)
    }

    return URL(string: lexical)
}
#endif // !canImport(Darwin) && swift(<6.0)
