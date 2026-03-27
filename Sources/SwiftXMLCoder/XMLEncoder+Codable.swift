import Foundation
import Logging

// MARK: - Architecture: XMLEncoder Codable implementation
//
// This file contains the internal machinery that backs `XMLEncoder.encode(_:)`.
// It follows the standard Swift Codable pattern (containers + recursive descent),
// adapted for XML's structure where fields can be serialised as either
// child *elements* or *attributes* depending on per-field configuration.
//
// ## Build pipeline
//
//   XMLEncoder.encode(value)
//     → resolves root element name (XMLRootNameResolver)
//     → creates _XMLTreeElementBox (mutable in-memory tree)
//     → creates _XMLTreeEncoder wrapping that box
//     → calls value.encode(to: encoder)
//          → _XMLKeyedEncodingContainer   (struct/class fields)
//          → _XMLUnkeyedEncodingContainer (arrays/sequences)
//          → _XMLSingleValueEncodingContainer (scalars, enums)
//     → _XMLTreeElementBox.makeElement() collapses the mutable box into
//       an immutable XMLTreeElement
//     → XMLTreeWriter serialises the tree to Data
//
// ## Field node kind resolution (resolvedNodeKind priority chain)
//
// Each field in a keyed container is resolved in order:
//   1. Type-level: if the value's type conforms to `_XMLFieldKindOverrideType`
//      (satisfied by the `XMLAttribute<T>` / `XMLChild<T>` property wrappers),
//      its `_xmlFieldNodeKindOverride` is used unconditionally.
//   2. Macro-level: if the enclosing type conforms to
//      `XMLFieldCodingOverrideProvider` (synthesised by `@XMLCodable`), the static
//      `xmlFieldNodeKinds` dictionary is consulted by field name (CodingKey.stringValue).
//   3. Runtime: `XMLFieldCodingOverrides` attached to the encoder configuration
//      allows call-site control keyed by dotted coding-path string.
//   4. Default: `.element` — every field becomes a child XML element.
//
// ## Scalar boxing (boxedScalar)
//
// Before attempting a nested encode, the encoder tries to serialise the value
// as a plain string via `boxedScalar(_:codingPath:localName:isAttribute:)`.
// This handles the full Foundation scalar set (Int, Double, Bool, Decimal, Date,
// Data, URL, UUID) without creating an intermediate XML tree level.  Complex
// (non-scalar) types fall through and are encoded recursively via a nested encoder.

func _xmlFieldNodeKinds<T>(for type: T.Type) -> [String: XMLFieldNodeKind] {
    guard let provider = type as? XMLFieldCodingOverrideProvider.Type else {
        return [:]
    }
    return provider.xmlFieldNodeKinds
}

func _xmlFieldNamespaces<T>(for type: T.Type) -> [String: XMLNamespace] {
    guard let provider = type as? XMLFieldNamespaceProvider.Type else {
        return [:]
    }
    return provider.xmlFieldNamespaces
}

func _xmlPropertyExpandEmptyKeys<T>(for type: T.Type) -> Set<String> {
    guard let provider = type as? XMLExpandEmptyProvider.Type else {
        return []
    }
    return provider.xmlPropertyExpandEmptyKeys
}

func _xmlPropertyStringHints<T>(for type: T.Type) -> [String: XMLStringEncodingHint] {
    guard let provider = type as? XMLStringCodingOverrideProvider.Type else {
        return [:]
    }
    return provider.xmlPropertyStringHints
}

func _xmlPropertyDateHints<T>(for type: T.Type) -> [String: XMLDateFormatHint] {
    guard let provider = type as? XMLDateCodingOverrideProvider.Type else {
        return [:]
    }
    return provider.xmlPropertyDateHints
}

struct _XMLEncoderOptions {
    let itemElementName: String
    let fieldCodingOverrides: XMLFieldCodingOverrides
    let nilEncodingStrategy: XMLEncoder.NilEncodingStrategy
    let dateEncodingStrategy: XMLEncoder.DateEncodingStrategy
    let dataEncodingStrategy: XMLEncoder.DataEncodingStrategy
    let stringEncodingStrategy: XMLEncoder.StringEncodingStrategy
    let keyTransformStrategy: XMLKeyTransformStrategy
    let validationPolicy: XMLValidationPolicy
    let logger: Logger
    let userInfo: [CodingUserInfoKey: Any]
    let keyNameCache: _XMLKeyNameCache
    /// Per-property date format hints populated from `XMLDateCodingOverrideProvider`.
    var perPropertyDateHints: [String: XMLDateFormatHint] = [:]
    /// Per-property string encoding hints populated from `XMLStringCodingOverrideProvider`.
    var perPropertyStringHints: [String: XMLStringEncodingHint] = [:]
    /// Per-property expand-empty keys populated from `XMLExpandEmptyProvider`.
    var perPropertyExpandEmptyKeys: Set<String> = []

    init(configuration: XMLEncoder.Configuration) throws {
        let policy = configuration.validationPolicy
        let rawItemName = configuration.itemElementName
        let safeItemName = XMLRootNameResolver.makeXMLSafeName(rawItemName)
        if policy.validateElementNames && safeItemName != rawItemName {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ITEM_NAME_INVALID] '\(rawItemName)' is not a valid XML element name for itemElementName."
            )
        }
        self.itemElementName = safeItemName
        self.fieldCodingOverrides = configuration.fieldCodingOverrides
        self.nilEncodingStrategy = configuration.nilEncodingStrategy
        self.dateEncodingStrategy = configuration.dateEncodingStrategy
        self.dataEncodingStrategy = configuration.dataEncodingStrategy
        self.stringEncodingStrategy = configuration.stringEncodingStrategy
        self.keyTransformStrategy = configuration.keyTransformStrategy
        self.validationPolicy = policy
        self.logger = configuration.logger
        self.userInfo = configuration.userInfo
        self.keyNameCache = _XMLKeyNameCache()
    }
}

// Validates that `name` can serve as an XML element or attribute name when
// `policy.validateElementNames` is `true`. Rejects characters that would cause
// a late libxml2 writer failure with no actionable diagnostic: whitespace and
// XML structure metacharacters.
private func _validateXMLFieldName(_ name: String, context: String, policy: XMLValidationPolicy) throws {
    guard policy.validateElementNames else { return }
    let invalid = name.isEmpty || name.unicodeScalars.contains { scalar in
        let codePoint = scalar.value
        return codePoint == 0x20 || codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D  // whitespace
            || codePoint == 0x3C || codePoint == 0x3E                              // < >
            || codePoint == 0x26                                                   // &
            || codePoint == 0x22 || codePoint == 0x27                             // " '
    }
    if invalid {
        throw XMLParsingError.parseFailed(
            message: "[XML6_6_FIELD_NAME_INVALID] '\(name)' is not a valid XML name in \(context)."
        )
    }
}

/// A per-encode-session cache for transformed XML key names.
///
/// Shared across all nested `_XMLTreeEncoder` instances via the `_XMLEncoderOptions` struct
/// (struct copies carry the same class reference). Eliminates repeated string-transform work
/// when the same coding keys appear many times (e.g. encoding an array of structs).
/// Also used by `_XMLDecoderOptions` for the symmetric decode path.
final class _XMLKeyNameCache {
    var storage: [String: String] = [:]
}

enum _XMLTreeContentBox {
    case text(String)
    case cdata(String)
    case element(_XMLTreeElementBox)
}

final class _XMLTreeElementBox {
    let name: XMLQualifiedName
    var attributes: [XMLTreeAttribute]
    var namespaceDeclarations: [XMLNamespaceDeclaration]
    private var contents: [_XMLTreeContentBox]

    init(
        name: XMLQualifiedName,
        attributes: [XMLTreeAttribute] = [],
        namespaceDeclarations: [XMLNamespaceDeclaration] = [],
        estimatedContentCount: Int = 4
    ) {
        self.name = name
        self.attributes = attributes
        self.namespaceDeclarations = namespaceDeclarations
        self.contents = []
        self.contents.reserveCapacity(max(estimatedContentCount, 0))
    }

    var isEmpty: Bool { contents.isEmpty }

    func appendText(_ value: String) {
        contents.append(.text(value))
    }

    func appendCDATA(_ value: String) {
        contents.append(.cdata(value))
    }

    func appendElement(_ child: _XMLTreeElementBox) {
        contents.append(.element(child))
    }

    @discardableResult
    func makeChild(localName: String) -> _XMLTreeElementBox {
        let child = _XMLTreeElementBox(name: XMLQualifiedName(localName: localName))
        appendElement(child)
        return child
    }

    @discardableResult
    func makeChild(qualifiedName: XMLQualifiedName) -> _XMLTreeElementBox {
        let child = _XMLTreeElementBox(name: qualifiedName)
        appendElement(child)
        return child
    }

    func addNamespaceDeclarationIfNeeded(prefix: String?, uri: String) {
        let alreadyPresent = namespaceDeclarations.contains {
            $0.prefix == prefix && $0.uri == uri
        }
        if !alreadyPresent {
            namespaceDeclarations.append(XMLNamespaceDeclaration(prefix: prefix, uri: uri))
        }
    }

    func makeElement() -> XMLTreeElement {
        var children: [XMLTreeNode] = []
        children.reserveCapacity(contents.count)
        for content in contents {
            switch content {
            case .text(let value):
                children.append(.text(value))
            case .cdata(let value):
                children.append(.cdata(value))
            case .element(let child):
                children.append(.element(child.makeElement()))
            }
        }

        return XMLTreeElement(
            name: name,
            attributes: attributes,
            namespaceDeclarations: namespaceDeclarations,
            children: children
        )
    }
}

struct _XMLEncodingKey: CodingKey {
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

final class _XMLTreeEncoder: Encoder {
    let options: _XMLEncoderOptions
    let node: _XMLTreeElementBox
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    let fieldNamespaces: [String: XMLNamespace]
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(
        options: _XMLEncoderOptions,
        codingPath: [CodingKey],
        node: _XMLTreeElementBox,
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:],
        fieldNamespaces: [String: XMLNamespace] = [:]
    ) {
        self.options = options
        self.codingPath = codingPath
        self.node = node
        self.fieldNodeKinds = fieldNodeKinds
        self.fieldNamespaces = fieldNamespaces
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = _XMLKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        _XMLUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        _XMLSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func boxedScalar<T: Encodable>(
        _ value: T,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool = false
    ) throws -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let int8 as Int8:
            return String(int8)
        case let int16 as Int16:
            return String(int16)
        case let int32 as Int32:
            return String(int32)
        case let int64 as Int64:
            return String(int64)
        case let uint as UInt:
            return String(uint)
        case let uint8 as UInt8:
            return String(uint8)
        case let uint16 as UInt16:
            return String(uint16)
        case let uint32 as UInt32:
            return String(uint32)
        case let uint64 as UInt64:
            return String(uint64)
        case let float as Float:
            return String(float)
        case let double as Double:
            return String(double)
        case let decimal as Decimal:
            return NSDecimalNumber(decimal: decimal).stringValue
        case let url as URL:
            return url.absoluteString
        case let uuid as UUID:
            return uuid.uuidString
        case let date as Date:
            return try boxedDate(date, codingPath: codingPath, localName: localName, isAttribute: isAttribute)
        case let data as Data:
            return boxedData(data)
        default:
            return nil
        }
    }

    private func boxedDate(
        _ date: Date,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> String? {
        let context = XMLDateCodingContext(
            codingPath: codingPath.map(\.stringValue),
            localName: localName,
            namespaceURI: nil,
            isAttribute: isAttribute
        )

        // Per-property hint overrides the global strategy when present.
        let effectiveStrategy: XMLEncoder.DateEncodingStrategy
        if let name = localName, let hint = options.perPropertyDateHints[name] {
            options.logger.trace(
                "Per-property date hint applied",
                metadata: ["field": "\(name)", "hint": "\(hint)"]
            )
            effectiveStrategy = hint.encodingStrategy
        } else {
            effectiveStrategy = options.dateEncodingStrategy
        }

        switch effectiveStrategy {
        case .deferredToDate:
            return nil
        case .secondsSince1970:
            return String(date.timeIntervalSince1970)
        case .millisecondsSince1970:
            return String(date.timeIntervalSince1970 * 1000.0)
        case .xsdDateTimeISO8601:
            return _XMLTemporalFoundationSupport.formatISO8601(date)
        case .iso8601:
            return _XMLTemporalFoundationSupport.formatISO8601(date)
        case .xsdDate(let tz):
            return _XMLTemporalFoundationSupport.formatXSDDate(date, timeZone: tz)
        case .xsdTime(let tz):
            return XMLTime(date: date, timeZone: tz).lexicalValue
        case .xsdGYear(let tz):
            return XMLGYear(date: date, timeZone: tz).lexicalValue
        case .xsdGYearMonth(let tz):
            return XMLGYearMonth(date: date, timeZone: tz).lexicalValue
        case .xsdGMonth(let tz):
            var gMonthCal = Calendar(identifier: .gregorian)
            gMonthCal.timeZone = tz
            let gMonth = gMonthCal.component(.month, from: date)
            return XMLGMonth(month: gMonth, timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)).lexicalValue
        case .xsdGDay(let tz):
            var gDayCal = Calendar(identifier: .gregorian)
            gDayCal.timeZone = tz
            let gDay = gDayCal.component(.day, from: date)
            return XMLGDay(day: gDay, timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)).lexicalValue
        case .xsdGMonthDay(let tz):
            var gMDCal = Calendar(identifier: .gregorian)
            gMDCal.timeZone = tz
            let gMDMonth = gMDCal.component(.month, from: date)
            let gMDDay = gMDCal.component(.day, from: date)
            return XMLGMonthDay(month: gMDMonth, day: gMDDay, timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)).lexicalValue
        case .formatter(let descriptor):
            return _XMLTemporalFoundationSupport.makeDateFormatter(from: descriptor).string(from: date)
        case .custom(let closure):
            do {
                return try closure(date, context)
            } catch let error as XMLParsingError {
                throw error
            } catch {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_DATE_ENCODE_CUSTOM_FAILED] Custom date encoder failed at path '\(context.codingPath.joined(separator: "."))': \(error)."
                )
            }
        }
    }

    private func boxedData(_ data: Data) -> String? {
        switch options.dataEncodingStrategy {
        case .deferredToData:
            return nil
        case .base64:
            return data.base64EncodedString()
        case .hex:
            return data.map { String(format: "%02x", $0) }.joined()
        }
    }

    func addNilElementIfNeeded(localName: String, expandEmpty: Bool = false) {
        if options.nilEncodingStrategy == .emptyElement {
            let child = node.makeChild(localName: localName)
            if expandEmpty {
                child.appendText("")
            }
        }
    }
}

struct _XMLKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = Key

    private let encoder: _XMLTreeEncoder
    private(set) var codingPath: [CodingKey]

    init(encoder: _XMLTreeEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil(forKey key: Key) throws {
        let nodeKind = resolvedNodeKind(for: key, valueType: Never.self)
        if nodeKind == .attribute || nodeKind == .ignored {
            return
        }
        try _validateXMLFieldName(key.stringValue, context: "encodeNil field '\(key.stringValue)'", policy: encoder.options.validationPolicy)
        let expandEmpty = encoder.options.perPropertyExpandEmptyKeys.contains(key.stringValue)
        encoder.addNilElementIfNeeded(localName: xmlName(for: key), expandEmpty: expandEmpty)
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try encodeEncodable(value, forKey: key)
    }

    // MARK: encodeIfPresent — respect nilEncodingStrategy for synthesised Codable optionals
    //
    // Swift's compiler-synthesised encode(to:) calls the concrete encodeIfPresent overloads
    // (Bool?, Int?, String?, etc.) rather than encodeNil(forKey:), so the default protocol
    // implementation silently skips nil without invoking our nilEncodingStrategy.  Overriding
    // all concrete variants routes nil through encodeNil(forKey:), which enforces the strategy.

    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }

    private mutating func _encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value = value {
            try encodeEncodable(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }

    private func xmlName(for key: Key) -> String {
        let raw = key.stringValue
        switch encoder.options.keyTransformStrategy {
        case .useDefaultKeys:
            // Identity transform — zero cost, no cache needed.
            return raw
        case .custom(let closure):
            // Custom closures may be stateful — skip cache to preserve semantics.
            return closure(raw)
        default:
            break
        }
        if let cached = encoder.options.keyNameCache.storage[raw] {
            return cached
        }
        let transformed = encoder.options.keyTransformStrategy.transform(raw)
        encoder.options.keyNameCache.storage[raw] = transformed
        return transformed
    }

    private mutating func encodeEncodable<T: Encodable>(_ value: T, forKey key: Key) throws {
        let name = xmlName(for: key)
        try _validateXMLFieldName(name, context: "field '\(key.stringValue)'", policy: encoder.options.validationPolicy)
        let nodeKind = resolvedNodeKind(for: key, valueType: T.self)
        if nodeKind == .attribute {
            try encodeAttribute(value, forKey: key)
            return
        }

        if nodeKind == .ignored {
            return
        }

        if nodeKind == .textContent {
            try encodeTextContent(value, forKey: key)
            return
        }

        if let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath + [key],
            localName: name
        ) {
            try encodeScalarString(scalar, forKey: key)
            return
        }

        let child = makeChildBox(for: key)
        var nestedOptions = encoder.options
        nestedOptions.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        nestedOptions.perPropertyStringHints = _xmlPropertyStringHints(for: T.self)
        nestedOptions.perPropertyExpandEmptyKeys = _xmlPropertyExpandEmptyKeys(for: T.self)
        let nestedEncoder = _XMLTreeEncoder(
            options: nestedOptions,
            codingPath: codingPath + [key],
            node: child,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        try value.encode(to: nestedEncoder)
        // Per-field expand-empty: inject empty text into child-less elements so the writer
        // emits <field></field> instead of <field/>.
        if child.isEmpty && encoder.options.perPropertyExpandEmptyKeys.contains(key.stringValue) {
            child.appendText("")
        }
    }

    mutating func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let child = encoder.node.makeChild(localName: key.stringValue)
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [key],
            node: child
        )
        return nestedEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let child = encoder.node.makeChild(localName: key.stringValue)
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [key],
            node: child
        )
        return nestedEncoder.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        let superKey = _XMLEncodingKey(stringValue: "super") ?? _XMLEncodingKey(index: 0)
        let child = encoder.node.makeChild(localName: superKey.stringValue)
        return _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [superKey],
            node: child
        )
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        let child = encoder.node.makeChild(localName: key.stringValue)
        return _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [key],
            node: child
        )
    }

    private func encodeScalarString(_ value: String, forKey key: Key) throws {
        let child = makeChildBox(for: key)
        let effectiveStringStrategy = resolvedStringStrategy(for: key)
        switch effectiveStringStrategy {
        case .text:
            child.appendText(value)
        case .cdata:
            child.appendCDATA(value)
        }
    }

    /// Creates a child element box for `key`, applying any per-field namespace from the encoder.
    private func makeChildBox(for key: Key) -> _XMLTreeElementBox {
        let name = xmlName(for: key)
        if let ns = encoder.fieldNamespaces[key.stringValue] {
            let qualifiedName = XMLQualifiedName(localName: name, namespaceURI: ns.uri, prefix: ns.prefix)
            encoder.node.addNamespaceDeclarationIfNeeded(prefix: ns.prefix, uri: ns.uri)
            return encoder.node.makeChild(qualifiedName: qualifiedName)
        }
        return encoder.node.makeChild(localName: name)
    }

    private func resolvedStringStrategy(for key: Key) -> XMLEncoder.StringEncodingStrategy {
        // Per-property hint (from @XMLCDATA macro) takes priority over the global strategy.
        if let hint = encoder.options.perPropertyStringHints[key.stringValue] {
            switch hint {
            case .text:  return .text
            case .cdata: return .cdata
            }
        }
        return encoder.options.stringEncodingStrategy
    }

    private mutating func encodeTextContent<T: Encodable>(_ value: T, forKey key: Key) throws {
        let scalar: String
        if let provider = value as? _XMLTextContentEncodableValue {
            scalar = try provider._xmlTextContentLexicalValue(
                using: encoder,
                codingPath: codingPath + [key],
                key: key.stringValue
            )
        } else if let boxed = try encoder.boxedScalar(
            value,
            codingPath: codingPath + [key],
            localName: key.stringValue
        ) {
            scalar = boxed
        } else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_TEXT_CONTENT_ENCODE_UNSUPPORTED] Key '\(key.stringValue)' cannot be encoded as text content because value is not scalar."
            )
        }
        let effectiveStringStrategy = resolvedStringStrategy(for: key)
        switch effectiveStringStrategy {
        case .text:
            encoder.node.appendText(scalar)
        case .cdata:
            encoder.node.appendCDATA(scalar)
        }
    }

    private mutating func encodeAttribute<T: Encodable>(_ value: T, forKey key: Key) throws {
        let lexicalValue: String
        if let provider = value as? _XMLAttributeEncodableValue {
            lexicalValue = try provider._xmlAttributeLexicalValue(
                using: encoder,
                codingPath: codingPath + [key],
                key: key.stringValue
            )
        } else if let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath + [key],
            localName: key.stringValue,
            isAttribute: true
        ) {
            lexicalValue = scalar
        } else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_ENCODE_UNSUPPORTED] Key '\(key.stringValue)' cannot be encoded as XML attribute because value is not scalar."
            )
        }

        let attrName: XMLQualifiedName
        if let ns = encoder.fieldNamespaces[key.stringValue] {
            attrName = XMLQualifiedName(localName: xmlName(for: key), namespaceURI: ns.uri, prefix: ns.prefix)
            encoder.node.addNamespaceDeclarationIfNeeded(prefix: ns.prefix, uri: ns.uri)
        } else {
            attrName = XMLQualifiedName(localName: xmlName(for: key))
        }
        encoder.node.attributes.append(XMLTreeAttribute(name: attrName, value: lexicalValue))
    }

    // MARK: Field node kind resolution — priority chain (see file-level comment)
    private func resolvedNodeKind<T>(for key: Key, valueType: T.Type) -> XMLFieldNodeKind {
        if let typeOverride = valueType as? _XMLFieldKindOverrideType.Type {
            return typeOverride._xmlFieldNodeKindOverride
        }

        if let override = encoder.fieldNodeKinds[key.stringValue] {
            return override
        }

        if let override = encoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue) {
            return override
        }

        return .element
    }
}

struct _XMLUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: _XMLTreeEncoder
    private(set) var codingPath: [CodingKey]
    private(set) var count: Int = 0

    init(encoder: _XMLTreeEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        guard encoder.options.nilEncodingStrategy == .emptyElement else {
            return
        }

        _ = makeItemNode()
    }

    mutating func encode(_ value: Bool) throws { try encodeScalar(value) }
    mutating func encode(_ value: String) throws { try encodeScalar(value) }
    mutating func encode(_ value: Double) throws { try encodeScalar(value) }
    mutating func encode(_ value: Float) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int8) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int16) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int32) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int64) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt8) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt16) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt32) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt64) throws { try encodeScalar(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let indexKey = _XMLEncodingKey(index: count)
        if let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath + [indexKey],
            localName: encoder.options.itemElementName
        ) {
            let itemNode = makeItemNode()
            itemNode.appendText(scalar)
            return
        }

        let itemNode = makeItemNode()
        let currentIndexKey = _XMLEncodingKey(index: count - 1)
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [currentIndexKey],
            node: itemNode,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        try value.encode(to: nestedEncoder)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey>
    where NestedKey: CodingKey {
        let itemNode = makeItemNode()
        let indexKey = _XMLEncodingKey(index: count - 1)
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [indexKey],
            node: itemNode
        )
        return nestedEncoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let itemNode = makeItemNode()
        let indexKey = _XMLEncodingKey(index: count - 1)
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [indexKey],
            node: itemNode
        )
        return nestedEncoder.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        let itemNode = makeItemNode()
        let indexKey = _XMLEncodingKey(index: count - 1)
        return _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath + [indexKey],
            node: itemNode
        )
    }

    private mutating func encodeScalar<T: Encodable>(_ value: T) throws {
        let indexKey = _XMLEncodingKey(index: count)
        guard let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath + [indexKey],
            localName: encoder.options.itemElementName
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_4_UNKEYED_SCALAR] Unable to box unkeyed scalar."
            )
        }
        let itemNode = makeItemNode()
        itemNode.appendText(scalar)
    }

    private mutating func makeItemNode() -> _XMLTreeElementBox {
        count += 1
        return encoder.node.makeChild(localName: encoder.options.itemElementName)
    }
}

struct _XMLSingleValueEncodingContainer: SingleValueEncodingContainer {
    private let encoder: _XMLTreeEncoder
    private(set) var codingPath: [CodingKey]

    init(encoder: _XMLTreeEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        if encoder.options.nilEncodingStrategy == .emptyElement {
            // Empty root element: no-op.
        }
    }

    mutating func encode(_ value: Bool) throws { try encodeScalar(value) }
    mutating func encode(_ value: String) throws { try encodeScalar(value) }
    mutating func encode(_ value: Double) throws { try encodeScalar(value) }
    mutating func encode(_ value: Float) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int8) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int16) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int32) throws { try encodeScalar(value) }
    mutating func encode(_ value: Int64) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt8) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt16) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt32) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt64) throws { try encodeScalar(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        if let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath,
            localName: encoder.node.name.localName
        ) {
            encoder.node.appendText(scalar)
            return
        }
        let nestedEncoder = _XMLTreeEncoder(
            options: encoder.options,
            codingPath: codingPath,
            node: encoder.node,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        try value.encode(to: nestedEncoder)
    }

    private mutating func encodeScalar<T: Encodable>(_ value: T) throws {
        guard let scalar = try encoder.boxedScalar(
            value,
            codingPath: codingPath,
            localName: encoder.node.name.localName
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_4_SINGLE_SCALAR] Unable to box single value scalar."
            )
        }
        encoder.node.appendText(scalar)
    }
}
