import Foundation

// MARK: - Architecture: XML field coding system
//
// This file defines the two complementary mechanisms for specifying whether a
// Codable field should be serialised as an XML *attribute* or a child *element*.
//
// ## Mechanism A — Property wrappers (all Swift versions, pre-macro path)
//
//   `XMLAttribute<Value>` and `XMLChild<Value>` are `@propertyWrapper` types.
//   They conform to `_XMLFieldKindOverrideType`, checked at priority-chain step 1.
//   The wrapper is transparent at the Codable level (delegates to the wrapped value),
//   so the field's type in generated models stays concrete (e.g. `XMLAttribute<Int>`
//   encodes as if the field were `Int`).
//
// ## Mechanism B — Macros (Swift 5.9+ via SwiftXMLCoderMacros)
//
//   `@XMLCodable` is an extension macro that synthesises an
//   `XMLFieldCodingOverrideProvider` extension whose `xmlFieldNodeKinds` static
//   dictionary maps field names to node kinds, consulted at priority-chain step 2.
//   Fields stay unboxed (e.g. `@XMLAttribute var id: Int` keeps the Swift type `Int`).
//
// ## Mechanism C — Runtime overrides (XMLFieldCodingOverrides)
//
//   `XMLFieldCodingOverrides` is a value-type dictionary keyed by dotted
//   coding-path strings (e.g. `"root.child.fieldName"`), allowing per-call-site
//   overrides without modifying the model type.  Priority-chain step 3.
//
// ## Priority chain (evaluated in order)
//
//   1. `_XMLFieldKindOverrideType` conformance on the value's Swift type (wrapper)
//   2. `XMLFieldCodingOverrideProvider.xmlFieldNodeKinds`            (macro dict)
//   3. `XMLFieldCodingOverrides` in encoder/decoder options           (runtime)
//   4. Default: `.element`
//
// `XMLElement` is a deprecated alias for `XMLChild` (renamed to avoid Foundation.XMLElement collision).

/// Whether a Codable field maps to an XML element, XML attribute, or text content.
///
/// Used as the value type in ``XMLFieldCodingOverrides`` and ``XMLFieldCodingOverrideProvider``.
/// See the architecture block at the top of this file for the full priority chain.
public enum XMLFieldNodeKind: String, Sendable, Hashable, Codable {
    /// The field is encoded as a child `<element>` node. This is the default.
    case element
    /// The field is encoded as an XML attribute on the parent element.
    case attribute
    /// The field is encoded as the text content of the parent element.
    ///
    /// Use this when you need to map both attributes and a scalar value to the same element:
    /// ```xml
    /// <price currency="USD">9.99</price>
    /// ```
    /// ```swift
    /// @XMLCodable
    /// struct Price: Codable {
    ///     @XMLAttribute var currency: String
    ///     @XMLText var value: Double
    /// }
    /// ```
    case textContent
    /// The field is excluded from XML serialization and deserialization entirely.
    ///
    /// When encoding, the field is silently skipped. When decoding, the field receives
    /// its default value as provided by the `Decodable` implementation (typically via
    /// a default value in the property declaration or `init(from:)`).
    ///
    /// Use `@XMLIgnore` or the `@XMLCodable`-synthesised dictionary to mark fields
    /// that exist in the Swift model but have no XML representation.
    case ignored
}

/// A runtime dictionary of per-field ``XMLFieldNodeKind`` overrides, keyed by
/// dotted coding-path strings (e.g. `"root.address.city"`).
///
/// Pass a configured instance via ``XMLEncoder/Configuration/fieldCodingOverrides`` or
/// ``XMLDecoder/Configuration/fieldCodingOverrides`` to control how specific fields
/// are mapped without modifying the model type.
///
/// This is mechanism C in the priority chain (lowest precedence); prefer
/// ``XMLAttribute`` / ``XMLChild`` wrappers or the `@XMLCodable` macro for
/// compile-time clarity.
public struct XMLFieldCodingOverrides: Sendable, Hashable, Codable {
    /// The raw mapping of coding-path keys to node kinds.
    public let mapping: [String: XMLFieldNodeKind]

    /// Creates a set of field coding overrides from an existing mapping dictionary.
    ///
    /// - Parameter mapping: Initial mapping. Defaults to an empty dictionary (no overrides).
    public init(mapping: [String: XMLFieldNodeKind] = [:]) {
        self.mapping = mapping
    }

    /// Returns a new `XMLFieldCodingOverrides` with the given key-path/node-kind pair added.
    ///
    /// - Parameters:
    ///   - path: The coding-path components leading to the parent container.
    ///   - key: The field name (the last path component).
    ///   - nodeKind: The desired node kind for this field.
    /// - Returns: A new overrides instance with the additional mapping.
    public func setting(path: [String], key: String, as nodeKind: XMLFieldNodeKind) -> XMLFieldCodingOverrides {
        var updated = mapping
        updated[Self.lookupKey(path: path, key: key)] = nodeKind
        return XMLFieldCodingOverrides(mapping: updated)
    }

    /// Returns the override for the given path and key, or `nil` if none is registered.
    ///
    /// - Parameters:
    ///   - path: The coding-path components leading to the parent container.
    ///   - key: The field name.
    public func nodeKind(for path: [String], key: String) -> XMLFieldNodeKind? {
        mapping[Self.lookupKey(path: path, key: key)]
    }

    func nodeKind(for codingPath: [CodingKey], key: String) -> XMLFieldNodeKind? {
        nodeKind(for: codingPath.map(\.stringValue), key: key)
    }

    /// Returns the dotted-path string used as the dictionary key for a given path and field name.
    ///
    /// - Parameters:
    ///   - path: The coding-path components.
    ///   - key: The field name.
    /// - Returns: A dotted string like `"root.child.fieldName"`.
    public static func lookupKey(path: [String], key: String) -> String {
        (path + [key]).joined(separator: ".")
    }
}

/// A type-level source of ``XMLFieldNodeKind`` overrides synthesised by the `@XMLCodable` macro.
///
/// The `@XMLCodable` macro generates an extension of your type conforming to this protocol,
/// providing a static dictionary that maps field names to node kinds based on the
/// `@XMLAttribute` and `@XMLChild` macro arguments you declared.
///
/// You typically do not implement this protocol manually — use the `@XMLCodable` macro instead.
/// Direct implementation is supported for advanced use cases.
///
/// This is mechanism B in the priority chain (second highest precedence after property wrappers).
public protocol XMLFieldCodingOverrideProvider {
    /// A static mapping from field name to ``XMLFieldNodeKind``, synthesised by `@XMLCodable`.
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { get }
}

public extension XMLFieldCodingOverrideProvider {
    /// Default implementation: no overrides.
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { [:] }
}

protocol _XMLFieldKindOverrideType {
    static var _xmlFieldNodeKindOverride: XMLFieldNodeKind { get }
}

protocol _XMLAttributeEncodableValue {
    func _xmlAttributeLexicalValue(
        using encoder: _XMLTreeEncoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> String
}

protocol _XMLAttributeDecodableValue {
    static func _xmlDecodeAttributeLexicalValue(
        _ lexicalValue: String,
        using decoder: _XMLTreeDecoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> Self
}

protocol _XMLTextContentEncodableValue {
    func _xmlTextContentLexicalValue(
        using encoder: _XMLTreeEncoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> String
}

protocol _XMLTextContentDecodableValue {
    static func _xmlDecodeTextContentLexicalValue(
        _ lexicalValue: String,
        using decoder: _XMLTreeDecoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> Self
}

/// A property wrapper that marks a `Codable` field as an XML attribute.
///
/// Wrap a field with `@XMLAttribute` to instruct ``XMLEncoder`` to emit it as an
/// XML attribute on the parent element rather than as a child element.
///
/// - Important: `@XMLAttribute` only works with scalar `Codable` types that can be
///   represented as a single string value (e.g. `String`, `Int`, `Bool`, `Double`,
///   `URL`, `UUID`). Compound types (structs, enums with associated values) will
///   cause an encode/decode error.
///
/// - Note: When the wrapped `Value` is optional and `nil`, the attribute is always
///   omitted from the output regardless of ``XMLEncoder/NilEncodingStrategy``.
///
///
/// ## Example
/// ```swift
/// @XMLCodable
/// struct Item: Codable {
///     @XMLAttribute var id: String    // → <Item id="…">
///     var name: String                // → <name>…</name>
/// }
/// ```
///
/// This is mechanism A (highest precedence) in the field-node-kind priority chain.
@propertyWrapper
public struct XMLAttribute<Value: Codable>: Codable {
    /// The wrapped `Codable` value.
    public var wrappedValue: Value

    /// Creates an `XMLAttribute` wrapper around the given value.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Decodes the wrapped value by delegating to `Value`'s `Decodable` conformance.
    public init(from decoder: Decoder) throws {
        self.wrappedValue = try Value(from: decoder)
    }

    /// Encodes the wrapped value by delegating to `Value`'s `Encodable` conformance.
    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension XMLAttribute: Equatable where Value: Equatable {}
extension XMLAttribute: Hashable where Value: Hashable {}

extension XMLAttribute: _XMLFieldKindOverrideType {
    static var _xmlFieldNodeKindOverride: XMLFieldNodeKind { .attribute }
}

extension XMLAttribute: _XMLAttributeEncodableValue {
    func _xmlAttributeLexicalValue(
        using encoder: _XMLTreeEncoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> String {
        guard let lexical = try encoder.boxedScalar(
            wrappedValue,
            codingPath: codingPath,
            localName: key,
            isAttribute: true
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_ENCODE_UNSUPPORTED] Unable to encode attribute '\(key)' from non-scalar value."
            )
        }
        return lexical
    }
}

extension XMLAttribute: _XMLAttributeDecodableValue {
    static func _xmlDecodeAttributeLexicalValue(
        _ lexicalValue: String,
        using decoder: _XMLTreeDecoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> XMLAttribute<Value> {
        guard let value = try decoder.decodeScalarFromLexical(
            lexicalValue,
            as: Value.self,
            codingPath: codingPath,
            localName: key,
            isAttribute: true
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_ATTRIBUTE_DECODE_UNSUPPORTED] Unable to decode attribute '\(key)' into target value type."
            )
        }
        return XMLAttribute(wrappedValue: value)
    }
}

/// A property wrapper that explicitly marks a `Codable` field as an XML child element.
///
/// Use `@XMLChild` when you want to be explicit about element mapping, or to override
/// an inherited ``XMLFieldCodingOverrideProvider`` or ``XMLFieldCodingOverrides`` setting.
/// Because `.element` is the default mapping, you rarely need this wrapper unless
/// clarifying intent or overriding a lower-priority setting.
///
/// This is mechanism A (highest precedence) in the field-node-kind priority chain.
@propertyWrapper
public struct XMLChild<Value: Codable>: Codable {
    /// The wrapped `Codable` value.
    public var wrappedValue: Value

    /// Creates an `XMLChild` wrapper around the given value.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Decodes the wrapped value by delegating to `Value`'s `Decodable` conformance.
    public init(from decoder: Decoder) throws {
        self.wrappedValue = try Value(from: decoder)
    }

    /// Encodes the wrapped value by delegating to `Value`'s `Encodable` conformance.
    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension XMLChild: Equatable where Value: Equatable {}
extension XMLChild: Hashable where Value: Hashable {}

extension XMLChild: _XMLFieldKindOverrideType {
    static var _xmlFieldNodeKindOverride: XMLFieldNodeKind { .element }
}

/// Deprecated alias for ``XMLChild``. Use `@XMLChild` instead.
///
/// - Note: `XMLElement` was renamed to `XMLChild` to avoid collision with
///   `Foundation.XMLElement`. The old name is preserved for source compatibility.
@available(*, deprecated, renamed: "XMLChild")
public typealias XMLElement<Value: Codable> = XMLChild<Value>

/// A property wrapper that marks a `Codable` field as the text content of the parent XML element.
///
/// Use `@XMLTextContent` when the XML element carries both attributes and a scalar value:
/// ```xml
/// <price currency="USD">9.99</price>
/// ```
/// ```swift
/// struct Price: Codable {
///     @XMLTextContent var value: Double
///     @XMLAttribute   var currency: String
/// }
/// ```
///
/// - Important: Only scalar `Codable` types that can be represented as a single string value
///   are supported (e.g. `String`, `Int`, `Bool`, `Double`, `URL`, `UUID`).
///   At most one `@XMLTextContent` field per type is meaningful; if multiple are present
///   the encoder writes the last value, and the decoder reads the same text for all of them.
///
/// - Note: Without `@XMLCodable` on the enclosing type this property wrapper is mechanism A
///   (highest precedence) in the field-node-kind priority chain.
@propertyWrapper
public struct XMLTextContent<Value: Codable>: Codable {
    /// The wrapped `Codable` value.
    public var wrappedValue: Value

    /// Creates an `XMLTextContent` wrapper around the given value.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Decodes the wrapped value by delegating to `Value`'s `Decodable` conformance.
    public init(from decoder: Decoder) throws {
        self.wrappedValue = try Value(from: decoder)
    }

    /// Encodes the wrapped value by delegating to `Value`'s `Encodable` conformance.
    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension XMLTextContent: Equatable where Value: Equatable {}
extension XMLTextContent: Hashable where Value: Hashable {}

extension XMLTextContent: _XMLFieldKindOverrideType {
    static var _xmlFieldNodeKindOverride: XMLFieldNodeKind { .textContent }
}

extension XMLTextContent: _XMLTextContentEncodableValue {
    func _xmlTextContentLexicalValue(
        using encoder: _XMLTreeEncoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> String {
        guard let lexical = try encoder.boxedScalar(
            wrappedValue,
            codingPath: codingPath,
            localName: key,
            isAttribute: false
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_TEXT_CONTENT_ENCODE_UNSUPPORTED] Unable to encode text content '\(key)' from non-scalar value."
            )
        }
        return lexical
    }
}

extension XMLTextContent: _XMLTextContentDecodableValue {
    static func _xmlDecodeTextContentLexicalValue(
        _ lexicalValue: String,
        using decoder: _XMLTreeDecoder,
        codingPath: [CodingKey],
        key: String
    ) throws -> XMLTextContent<Value> {
        guard let value = try decoder.decodeScalarFromLexical(
            lexicalValue,
            as: Value.self,
            codingPath: codingPath,
            localName: key,
            isAttribute: false
        ) else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_6_TEXT_CONTENT_DECODE_UNSUPPORTED] Unable to decode text content '\(key)' into target value type."
            )
        }
        return XMLTextContent(wrappedValue: value)
    }
}
