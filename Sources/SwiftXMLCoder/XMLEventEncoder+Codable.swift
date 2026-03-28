import Foundation
import Logging

// MARK: - Architecture: Event-based Codable encoder
//
// This file implements `_XMLEventEncoder`, an alternative encoder that emits
// XMLStreamEvent values into a shared ContiguousArray collector during Codable encoding
// instead of building an intermediate tree of _XMLTreeElementBox objects.
//
// ## Build pipeline
//
//   XMLEncoder.encode(value)
//     → resolves root element name
//     → creates _XMLEventCollector
//     → creates _XMLEventEncoder for the root element
//     → value.encode(to: rootEncoder)
//          → _XMLEventKeyedEncodingContainer   (struct/class fields)
//          → _XMLEventUnkeyedEncodingContainer (arrays/sequences)
//          → _XMLEventSingleValueEncodingContainer (scalars, enums)
//     → rootEncoder.finishElement()
//     → flush collector.events → XMLStreamWriterSink → Data
//
// ## Attribute deferral
//
// XML attributes must appear in the opening tag, before any child content.
// The keyed container accumulates attribute fields in the encoder's `pendingAttributes`
// and defers `.startElement` until the first non-attribute field is encoded or
// `finishElement()` is called (empty / all-attribute elements).
//
// Consequence: if a manual `encode(to:)` implementation encodes an element field
// BEFORE an attribute field, the late attribute is silently dropped because
// `.startElement` has already been emitted.  Synthesised Codable conformances
// always emit attributes before elements, so this does not affect the common path.
//
// ## nestedContainer / nestedUnkeyedContainer / superEncoder
//
// These methods fall back to building a _XMLTreeElementBox sub-tree via _XMLTreeEncoder.
// The sub-tree box is stored in `encoder.pendingSubTrees` and is serialised to the
// collector when the next direct-child encode starts or at `finishElement()` time.
// Ordering is correct provided the caller finishes encoding all nested content before
// encoding the next sibling on the parent container — the normal Codable usage pattern.

// MARK: - _XMLEventCollector

/// Shared mutable buffer accumulating events during a single top-level encode call.
final class _XMLEventCollector {
    var events: ContiguousArray<XMLStreamEvent>

    init(estimatedEventCount: Int = 128) {
        events = ContiguousArray()
        events.reserveCapacity(estimatedEventCount)
    }
}

// MARK: - _XMLEventEncoder

final class _XMLEventEncoder: Encoder, _XMLScalarBoxer {
    let options: _XMLEncoderOptions
    let collector: _XMLEventCollector
    let elementName: XMLQualifiedName
    /// Attributes buffered before `.startElement` is emitted.
    var pendingAttributes: [XMLTreeAttribute] = []
    /// Namespace declarations buffered before `.startElement` is emitted.
    var pendingNamespaces: [XMLNamespaceDeclaration] = []
    /// True once `.startElement` has been appended to the collector.
    var startElementEmitted = false
    /// True once `finishElement()` has run (idempotent guard).
    var elementClosed = false
    /// Sub-trees created via `nestedContainer`/`nestedUnkeyedContainer`/`superEncoder`.
    /// Drained to the collector before the next direct-child encode or at `finishElement`.
    var pendingSubTrees: [_XMLTreeElementBox] = []

    var codingPath: [CodingKey]
    let fieldNodeKinds: [String: XMLFieldNodeKind]
    let fieldNamespaces: [String: XMLNamespace]
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(
        options: _XMLEncoderOptions,
        collector: _XMLEventCollector,
        elementName: XMLQualifiedName,
        codingPath: [CodingKey],
        fieldNodeKinds: [String: XMLFieldNodeKind] = [:],
        fieldNamespaces: [String: XMLNamespace] = [:]
    ) {
        self.options = options
        self.collector = collector
        self.elementName = elementName
        self.codingPath = codingPath
        self.fieldNodeKinds = fieldNodeKinds
        self.fieldNamespaces = fieldNamespaces
    }

    // MARK: Encoder

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        // Pre-declare all field namespaces on this element so they are present in
        // `.startElement` even if the first namespace-qualified child is encoded after
        // the opening tag would have been emitted.
        for (_, ns) in fieldNamespaces {
            addNamespaceDeclarationIfNeeded(prefix: ns.prefix, uri: ns.uri)
        }
        return KeyedEncodingContainer(_XMLEventKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        _XMLEventUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        _XMLEventSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }

    // MARK: Element lifecycle

    func flushStartElement() {
        guard !startElementEmitted else { return }
        startElementEmitted = true
        collector.events.append(.startElement(
            name: elementName,
            attributes: pendingAttributes,
            namespaceDeclarations: pendingNamespaces
        ))
    }

    /// Serialises all pending sub-trees (from `nestedContainer` fallback) to the collector.
    func drainPendingSubTrees() {
        guard !pendingSubTrees.isEmpty else { return }
        for box in pendingSubTrees {
            box.makeElement().walkEvents { event in
                collector.events.append(event)
            }
        }
        pendingSubTrees.removeAll()
    }

    /// Closes this element: drains pending sub-trees, emits `.startElement` (if not yet
    /// emitted), optionally injects an empty-text node for expand-empty semantics, then
    /// emits `.endElement`.  Idempotent.
    func finishElement(expandEmpty: Bool = false) {
        guard !elementClosed else { return }
        elementClosed = true
        drainPendingSubTrees()
        let alreadyHadContent = startElementEmitted
        flushStartElement()
        if expandEmpty && !alreadyHadContent {
            // Element was completely empty (no text, CDATA, or children before finishElement).
            // Inject an empty text node so the writer emits <element></element> rather than
            // the self-closing <element/>.
            collector.events.append(.text(""))
        }
        collector.events.append(.endElement(name: elementName))
    }

    // MARK: Nil element helper

    func addNilElementIfNeeded(localName: String, qualifiedName: XMLQualifiedName? = nil, expandEmpty: Bool = false) {
        guard options.nilEncodingStrategy == .emptyElement else { return }
        drainPendingSubTrees()
        flushStartElement()
        let name = qualifiedName ?? XMLQualifiedName(localName: localName)
        collector.events.append(.startElement(name: name, attributes: [], namespaceDeclarations: []))
        if expandEmpty { collector.events.append(.text("")) }
        collector.events.append(.endElement(name: name))
    }

    // MARK: Namespace declaration helper

    func addNamespaceDeclarationIfNeeded(prefix: String?, uri: String) {
        guard !pendingNamespaces.contains(where: { $0.prefix == prefix && $0.uri == uri }) else { return }
        pendingNamespaces.append(XMLNamespaceDeclaration(prefix: prefix, uri: uri))
    }

    // MARK: Scalar boxing — mirrors _XMLTreeEncoder

    func boxedScalar<T: Encodable>(
        _ value: T,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool = false
    ) throws -> String? {
        switch value {
        case let string as String:   return string
        case let bool as Bool:       return bool ? "true" : "false"
        case let int as Int:         return String(int)
        case let int8 as Int8:       return String(int8)
        case let int16 as Int16:     return String(int16)
        case let int32 as Int32:     return String(int32)
        case let int64 as Int64:     return String(int64)
        case let uint as UInt:       return String(uint)
        case let uint8 as UInt8:     return String(uint8)
        case let uint16 as UInt16:   return String(uint16)
        case let uint32 as UInt32:   return String(uint32)
        case let uint64 as UInt64:   return String(uint64)
        case let float as Float:     return String(float)
        case let double as Double:   return String(double)
        case let decimal as Decimal: return NSDecimalNumber(decimal: decimal).stringValue
        case let url as URL:         return url.absoluteString
        case let uuid as UUID:       return uuid.uuidString
        case let date as Date:       return try _boxedDate(date, codingPath: codingPath, localName: localName, isAttribute: isAttribute)
        case let data as Data:       return _boxedData(data)
        default:                     return nil
        }
    }

    private func _boxedDate(
        _ date: Date,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> String? {
        let ctx = XMLDateCodingContext(
            codingPath: codingPath.map(\.stringValue),
            localName: localName,
            namespaceURI: nil,
            isAttribute: isAttribute
        )
        let strategy: XMLEncoder.DateEncodingStrategy
        if let name = localName, let hint = options.perPropertyDateHints[name] {
            options.logger.trace(
                "Per-property date hint applied",
                metadata: ["field": "\(name)", "hint": "\(hint)"]
            )
            strategy = hint.encodingStrategy
        } else {
            strategy = options.dateEncodingStrategy
        }
        switch strategy {
        case .deferredToDate:                return nil
        case .secondsSince1970:              return String(date.timeIntervalSince1970)
        case .millisecondsSince1970:         return String(date.timeIntervalSince1970 * 1000.0)
        case .xsdDateTimeISO8601, .iso8601:  return _XMLTemporalFoundationSupport.formatISO8601(date)
        case .xsdDate(let tz):              return _XMLTemporalFoundationSupport.formatXSDDate(date, timeZone: tz)
        case .xsdTime(let tz):              return XMLTime(date: date, timeZone: tz).lexicalValue
        case .xsdGYear(let tz):             return XMLGYear(date: date, timeZone: tz).lexicalValue
        case .xsdGYearMonth(let tz):        return XMLGYearMonth(date: date, timeZone: tz).lexicalValue
        case .xsdGMonth(let tz):
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            return XMLGMonth(month: cal.component(.month, from: date), timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)).lexicalValue
        case .xsdGDay(let tz):
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            return XMLGDay(day: cal.component(.day, from: date), timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)).lexicalValue
        case .xsdGMonthDay(let tz):
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            return XMLGMonthDay(
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date),
                timezoneOffset: XMLTimezoneOffset(standardTimeOf: tz)
            ).lexicalValue
        case .formatter(let desc):
            return _XMLTemporalFoundationSupport.makeDateFormatter(from: desc).string(from: date)
        case .custom(let closure):
            do { return try closure(date, ctx) }
            catch let xmlErr as XMLParsingError { throw xmlErr }
            catch {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5C_DATE_ENCODE_CUSTOM_FAILED] Custom date encoder failed at path '\(ctx.codingPath.joined(separator: "."))': \(error)."
                )
            }
        }
    }

    private func _boxedData(_ data: Data) -> String? {
        switch options.dataEncodingStrategy {
        case .deferredToData: return nil
        case .base64:         return data.base64EncodedString()
        case .hex:            return data.map { String(format: "%02x", $0) }.joined()
        }
    }
}

// MARK: - _XMLEventKeyedEncodingContainer

struct _XMLEventKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = Key
    private let encoder: _XMLEventEncoder
    private(set) var codingPath: [CodingKey]

    init(encoder: _XMLEventEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    // MARK: Nil

    mutating func encodeNil(forKey key: Key) throws {
        let nodeKind = resolvedNodeKind(for: key, valueType: Never.self)
        guard nodeKind != .attribute && nodeKind != .ignored else { return }
        try _validateXMLFieldName(key.stringValue, context: "encodeNil field '\(key.stringValue)'", policy: encoder.options.validationPolicy)
        let name = xmlName(for: key)
        let expandEmpty = encoder.options.perPropertyExpandEmptyKeys.contains(key.stringValue)
        let qname: XMLQualifiedName
        if let ns = encoder.fieldNamespaces[key.stringValue] {
            qname = XMLQualifiedName(localName: name, namespaceURI: ns.uri, prefix: ns.prefix)
        } else {
            qname = XMLQualifiedName(localName: name)
        }
        encoder.addNilElementIfNeeded(localName: name, qualifiedName: qname, expandEmpty: expandEmpty)
    }

    // MARK: Scalar overloads (all route through encodeEncodable)

    mutating func encode(_ value: Bool,   forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Float,  forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int,    forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int8,   forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int16,  forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int32,  forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: Int64,  forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt,   forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt8,  forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try encodeEncodable(value, forKey: key) }

    // MARK: Optional overloads — enforce nilEncodingStrategy for synthesised Codable optionals

    mutating func encodeIfPresent(_ value: Bool?,   forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Float?,  forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int?,    forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int8?,   forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int16?,  forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int32?,  forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: Int64?,  forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt?,   forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt8?,  forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws { try _encodeIfPresent(value, forKey: key) }

    private mutating func _encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encodeEncodable(value, forKey: key) } else { try encodeNil(forKey: key) }
    }

    // MARK: nestedContainer / nestedUnkeyedContainer / superEncoder
    //
    // These methods fall back to building a _XMLTreeElementBox sub-tree so that element
    // close ordering is not dependent on ARC deallocation timing.  The sub-tree is
    // serialised to the collector by drainPendingSubTrees() before the next direct child
    // is encoded or when finishElement() is called on the parent encoder.

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        let box = _XMLTreeElementBox(name: childQualifiedName(for: key))
        encoder.pendingSubTrees.append(box)
        let treeEnc = _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [key], node: box)
        return treeEnc.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        let box = _XMLTreeElementBox(name: childQualifiedName(for: key))
        encoder.pendingSubTrees.append(box)
        let treeEnc = _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [key], node: box)
        return treeEnc.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        let superKey = _XMLEncodingKey(stringValue: "super") ?? _XMLEncodingKey(index: 0)
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        let box = _XMLTreeElementBox(name: XMLQualifiedName(localName: superKey.stringValue))
        encoder.pendingSubTrees.append(box)
        return _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [superKey], node: box)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        let box = _XMLTreeElementBox(name: childQualifiedName(for: key))
        encoder.pendingSubTrees.append(box)
        return _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [key], node: box)
    }

    // MARK: Core encode dispatch

    private mutating func encodeEncodable<T: Encodable>(_ value: T, forKey key: Key) throws {
        let name = xmlName(for: key)
        try _validateXMLFieldName(name, context: "field '\(key.stringValue)'", policy: encoder.options.validationPolicy)
        let nodeKind = resolvedNodeKind(for: key, valueType: T.self)

        switch nodeKind {
        case .attribute:
            try encodeAttribute(value, forKey: key)
            return
        case .ignored:
            return
        case .textContent:
            try encodeTextContent(value, forKey: key)
            return
        case .element:
            break
        }

        // Scalar fast-path: emit child element with text/cdata directly.
        if let scalar = try encoder.boxedScalar(value, codingPath: codingPath + [key], localName: name) {
            encoder.drainPendingSubTrees()
            encoder.flushStartElement()
            let childName = childQualifiedName(for: key)
            encoder.collector.events.append(.startElement(name: childName, attributes: [], namespaceDeclarations: []))
            switch resolvedStringStrategy(for: key) {
            case .text:  encoder.collector.events.append(.text(scalar))
            case .cdata: encoder.collector.events.append(.cdata(scalar))
            }
            encoder.collector.events.append(.endElement(name: childName))
            return
        }

        // Complex value: create a child event encoder.
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        var nestedOpts = encoder.options
        nestedOpts.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        nestedOpts.perPropertyStringHints = _xmlPropertyStringHints(for: T.self)
        nestedOpts.perPropertyExpandEmptyKeys = _xmlPropertyExpandEmptyKeys(for: T.self)
        let childEncoder = _XMLEventEncoder(
            options: nestedOpts,
            collector: encoder.collector,
            elementName: childQualifiedName(for: key),
            codingPath: codingPath + [key],
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        try value.encode(to: childEncoder)
        let expandEmpty = encoder.options.perPropertyExpandEmptyKeys.contains(key.stringValue)
        childEncoder.finishElement(expandEmpty: expandEmpty)
    }

    // MARK: Private helpers

    private func xmlName(for key: Key) -> String {
        let raw = key.stringValue
        switch encoder.options.keyTransformStrategy {
        case .useDefaultKeys:       return raw
        case .custom(let closure):  return closure(raw)
        default: break
        }
        if let cached = encoder.options.keyNameCache.storage[raw] { return cached }
        let transformed = encoder.options.keyTransformStrategy.transform(raw)
        encoder.options.keyNameCache.storage[raw] = transformed
        return transformed
    }

    private func childQualifiedName(for key: Key) -> XMLQualifiedName {
        let name = xmlName(for: key)
        if let ns = encoder.fieldNamespaces[key.stringValue] {
            // Namespace declaration was pre-added to pendingNamespaces in container(keyedBy:).
            return XMLQualifiedName(localName: name, namespaceURI: ns.uri, prefix: ns.prefix)
        }
        return XMLQualifiedName(localName: name)
    }

    private func resolvedStringStrategy(for key: Key) -> XMLEncoder.StringEncodingStrategy {
        if let hint = encoder.options.perPropertyStringHints[key.stringValue] {
            switch hint { case .text: return .text; case .cdata: return .cdata }
        }
        return encoder.options.stringEncodingStrategy
    }

    private func encodeTextContent<T: Encodable>(_ value: T, forKey key: Key) throws {
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
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        switch resolvedStringStrategy(for: key) {
        case .text:  encoder.collector.events.append(.text(scalar))
        case .cdata: encoder.collector.events.append(.cdata(scalar))
        }
    }

    private func encodeAttribute<T: Encodable>(_ value: T, forKey key: Key) throws {
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
            encoder.addNamespaceDeclarationIfNeeded(prefix: ns.prefix, uri: ns.uri)
            attrName = XMLQualifiedName(localName: xmlName(for: key), namespaceURI: ns.uri, prefix: ns.prefix)
        } else {
            attrName = XMLQualifiedName(localName: xmlName(for: key))
        }
        encoder.pendingAttributes.append(XMLTreeAttribute(name: attrName, value: lexicalValue))
    }

    // MARK: Field node kind resolution — same priority chain as tree encoder

    private func resolvedNodeKind<T>(for key: Key, valueType: T.Type) -> XMLFieldNodeKind {
        if let typeOverride = valueType as? _XMLFieldKindOverrideType.Type {
            return typeOverride._xmlFieldNodeKindOverride
        }
        if let override = encoder.fieldNodeKinds[key.stringValue] { return override }
        if let override = encoder.options.fieldCodingOverrides.nodeKind(for: codingPath, key: key.stringValue) { return override }
        return .element
    }
}

// MARK: - _XMLEventUnkeyedEncodingContainer

struct _XMLEventUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: _XMLEventEncoder
    private(set) var codingPath: [CodingKey]
    private(set) var count: Int = 0

    init(encoder: _XMLEventEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        guard encoder.options.nilEncodingStrategy == .emptyElement else { return }
        let itemName = makeItemStartElement()
        encoder.collector.events.append(.endElement(name: itemName))
    }

    mutating func encode(_ value: Bool)   throws { try encodeScalar(value) }
    mutating func encode(_ value: String) throws { try encodeScalar(value) }
    mutating func encode(_ value: Double) throws { try encodeScalar(value) }
    mutating func encode(_ value: Float)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int)    throws { try encodeScalar(value) }
    mutating func encode(_ value: Int8)   throws { try encodeScalar(value) }
    mutating func encode(_ value: Int16)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int32)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int64)  throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt)   throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt8)  throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt16) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt32) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt64) throws { try encodeScalar(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        let indexKey = _XMLEncodingKey(index: count)
        let itemName = XMLQualifiedName(localName: encoder.options.itemElementName)
        if let scalar = try encoder.boxedScalar(
            value, codingPath: codingPath + [indexKey], localName: encoder.options.itemElementName
        ) {
            encoder.drainPendingSubTrees()
            encoder.flushStartElement()
            count += 1
            encoder.collector.events.append(.startElement(name: itemName, attributes: [], namespaceDeclarations: []))
            encoder.collector.events.append(.text(scalar))
            encoder.collector.events.append(.endElement(name: itemName))
            return
        }
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        count += 1
        let currentKey = _XMLEncodingKey(index: count - 1)
        let itemEncoder = _XMLEventEncoder(
            options: encoder.options,
            collector: encoder.collector,
            elementName: itemName,
            codingPath: codingPath + [currentKey],
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        try value.encode(to: itemEncoder)
        itemEncoder.finishElement()
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let box = makeItemBox()
        let treeEnc = _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [_XMLEncodingKey(index: count - 1)], node: box)
        return treeEnc.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let box = makeItemBox()
        let treeEnc = _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [_XMLEncodingKey(index: count - 1)], node: box)
        return treeEnc.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        let box = makeItemBox()
        return _XMLTreeEncoder(options: encoder.options, codingPath: codingPath + [_XMLEncodingKey(index: count - 1)], node: box)
    }

    private mutating func encodeScalar<T: Encodable>(_ value: T) throws {
        let indexKey = _XMLEncodingKey(index: count)
        guard let scalar = try encoder.boxedScalar(
            value, codingPath: codingPath + [indexKey], localName: encoder.options.itemElementName
        ) else {
            throw XMLParsingError.parseFailed(message: "[XML6_4_UNKEYED_SCALAR] Unable to box unkeyed scalar.")
        }
        let itemName = makeItemStartElement()
        encoder.collector.events.append(.text(scalar))
        encoder.collector.events.append(.endElement(name: itemName))
    }

    /// Emits `.startElement` for a new item, increments `count`, and returns the item name.
    /// Caller is responsible for appending `.endElement` when content is complete.
    private mutating func makeItemStartElement() -> XMLQualifiedName {
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        count += 1
        let itemName = XMLQualifiedName(localName: encoder.options.itemElementName)
        encoder.collector.events.append(.startElement(name: itemName, attributes: [], namespaceDeclarations: []))
        return itemName
    }

    /// Creates a sub-tree box for `nestedContainer`/`nestedUnkeyedContainer`/`superEncoder`.
    private mutating func makeItemBox() -> _XMLTreeElementBox {
        encoder.drainPendingSubTrees()
        encoder.flushStartElement()
        count += 1
        let box = _XMLTreeElementBox(name: XMLQualifiedName(localName: encoder.options.itemElementName))
        encoder.pendingSubTrees.append(box)
        return box
    }
}

// MARK: - _XMLEventSingleValueEncodingContainer

struct _XMLEventSingleValueEncodingContainer: SingleValueEncodingContainer {
    private let encoder: _XMLEventEncoder
    private(set) var codingPath: [CodingKey]

    init(encoder: _XMLEventEncoder, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        // Root-level nil: emit an empty element via the encoder's element lifecycle.
        if encoder.options.nilEncodingStrategy == .emptyElement {
            encoder.flushStartElement()
        }
    }

    mutating func encode(_ value: Bool)   throws { try encodeScalar(value) }
    mutating func encode(_ value: String) throws { try encodeScalar(value) }
    mutating func encode(_ value: Double) throws { try encodeScalar(value) }
    mutating func encode(_ value: Float)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int)    throws { try encodeScalar(value) }
    mutating func encode(_ value: Int8)   throws { try encodeScalar(value) }
    mutating func encode(_ value: Int16)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int32)  throws { try encodeScalar(value) }
    mutating func encode(_ value: Int64)  throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt)   throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt8)  throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt16) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt32) throws { try encodeScalar(value) }
    mutating func encode(_ value: UInt64) throws { try encodeScalar(value) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        if let scalar = try encoder.boxedScalar(
            value, codingPath: codingPath, localName: encoder.elementName.localName
        ) {
            encoder.flushStartElement()
            encoder.collector.events.append(.text(scalar))
            return
        }
        // Complex value: create a sibling encoder sharing the same collector and element name.
        // Transfer accumulated attribute/namespace state so it ends up in the correct .startElement.
        let nested = _XMLEventEncoder(
            options: encoder.options,
            collector: encoder.collector,
            elementName: encoder.elementName,
            codingPath: codingPath,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        nested.pendingAttributes = encoder.pendingAttributes
        nested.pendingNamespaces = encoder.pendingNamespaces
        encoder.pendingAttributes = []
        encoder.pendingNamespaces = []
        try value.encode(to: nested)
        // If the nested encoder emitted .startElement, mark the original encoder so
        // finishElement() does not emit a duplicate.
        if nested.startElementEmitted {
            encoder.startElementEmitted = true
        } else {
            // No content was emitted; restore pending state.
            encoder.pendingAttributes = nested.pendingAttributes
            encoder.pendingNamespaces = nested.pendingNamespaces
        }
    }

    private mutating func encodeScalar<T: Encodable>(_ value: T) throws {
        guard let scalar = try encoder.boxedScalar(
            value, codingPath: codingPath, localName: encoder.elementName.localName
        ) else {
            throw XMLParsingError.parseFailed(message: "[XML6_4_SINGLE_SCALAR] Unable to box single value scalar.")
        }
        encoder.flushStartElement()
        encoder.collector.events.append(.text(scalar))
    }
}
