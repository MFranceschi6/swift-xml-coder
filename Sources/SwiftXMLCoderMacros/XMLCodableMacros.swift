import SwiftXMLCoder

/// Declares the XSD date format for a specific stored property, overriding the global
/// `dateEncodingStrategy` / `dateDecodingStrategy` on `XMLEncoder` / `XMLDecoder`.
///
/// Apply this macro to stored properties of type `Date` or `Date?` inside a type
/// also annotated with `@XMLCodable`. The owning type's `xmlPropertyDateHints` dictionary
/// (synthesised by `@XMLCodable`) will map the field's name to the specified hint,
/// causing the XML encoder and decoder to use that format for this property only.
///
/// ```swift
/// @XMLCodable
/// struct Schedule: Codable {
///     @XMLDateFormat(.xsdDate) var startDate: Date
///     @XMLDateFormat(.xsdTime) var startTime: Date
///     var createdAt: Date   // uses encoder-level strategy
/// }
/// ```
///
/// - Parameter hint: The ``XMLDateFormatHint`` that selects the XSD lexical format.
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLDateFormat(_ hint: XMLDateFormatHint) = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLDateFormatMacro"
)

/// Marks a stored `String` property to be encoded as a CDATA section when processed by `@XMLCodable`.
///
/// Apply this macro to stored properties of type `String` or `String?` inside a type
/// also annotated with `@XMLCodable`. The owning type's `xmlPropertyStringHints` dictionary
/// (synthesised by `@XMLCodable`) will map the field's name to `.cdata`,
/// causing the XML encoder to wrap that property's content in `<![CDATA[...]]>`.
///
/// ```swift
/// @XMLCodable
/// struct Article: Codable {
///     var title: String           // uses encoder-level stringEncodingStrategy
///     @XMLCDATA var body: String  // always emitted as <body><![CDATA[...]]></body>
/// }
/// ```
///
/// - Note: CDATA is not valid in XML attributes. Applying `@XMLCDATA` to a property
///   also annotated with `@XMLAttribute` compiles successfully but the CDATA hint is
///   silently ignored — attributes are always emitted as plain text.
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLCDATA() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLCDATAMacro"
)

/// Marks a stored property as an XML **attribute** when encoded or decoded by `@XMLCodable`.
///
/// Apply this macro to individual properties inside a type annotated with `@XMLCodable`.
/// The owning type's `xmlFieldNodeKinds` dictionary (synthesised by `@XMLCodable`) will
/// map this field's name to `.attribute`, causing the XML encoder and decoder to treat it
/// as an XML attribute rather than a child element.
///
/// ```swift
/// @XMLCodable
/// struct Item: Codable {
///     @XMLAttribute var id: Int      // encoded as <Item id="42">
///     @XMLChild  var name: String  // encoded as <name>Foo</name>
/// }
/// ```
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLAttribute() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLAttributeMacro"
)

/// Marks a stored property as an XML **child element** when encoded or decoded by `@XMLCodable`.
///
/// Apply this macro to individual properties inside a type annotated with `@XMLCodable`.
/// The owning type's `xmlFieldNodeKinds` dictionary (synthesised by `@XMLCodable`) will
/// map this field's name to `.element`.
///
/// Unannotated properties are not added to `xmlFieldNodeKinds`, so the encoder falls
/// back to its default resolution (currently `.element`).
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLChild() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLChildMacro"
)

/// Deprecated alias for ``XMLChild()``. Use `@XMLChild` instead.
@available(*, deprecated, renamed: "XMLChild")
@attached(peer)
public macro XMLElement() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLChildMacro"
)

/// Declares an XML namespace URI for the root element of a `Codable` type.
///
/// Apply this macro alongside `@XMLCodable` on a struct or class to automatically
/// generate a conformance to ``XMLRootNode`` that supplies a namespace URI for the
/// root element when encoding and decoding.
///
/// ```swift
/// @XMLCodable
/// @XMLRootNamespace("http://example.com/ns")
/// struct Order: Codable {
///     var id: String
///     var total: Double
/// }
/// // Encodes root element as: <Order xmlns="http://example.com/ns">
/// ```
///
/// To also set a custom element name, implement ``XMLRootNode/xmlRootElementName`` manually
/// alongside this macro.
///
/// - Parameter uri: The XML namespace URI to associate with the root element.
///   Must be a non-empty string literal; an empty URI is a compile-time error.
///
/// - Note: Only `struct` and `class` declarations are supported. Applying
///   `@XMLRootNamespace` to an `enum` or `actor` emits a compile-time error.
@attached(extension, conformances: XMLRootNode, names: named(xmlRootElementName), named(xmlRootElementNamespaceURI))
public macro XMLRootNamespace(_ uri: String) = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLNamespaceMacro"
)

/// Excludes a stored property from XML serialization and deserialization when processed by `@XMLCodable`.
///
/// Apply this macro to stored properties inside a type annotated with `@XMLCodable`.
/// The owning type's `xmlFieldNodeKinds` dictionary (synthesised by `@XMLCodable`) will
/// map this field's name to `.ignored`, causing the XML encoder to skip the field entirely
/// and the XML decoder to treat it as absent.
///
/// ```swift
/// @XMLCodable
/// struct Config: Codable {
///     var host: String
///     var port: Int
///     @XMLIgnore var _cache: [String: Any]? = nil  // not in XML
/// }
/// ```
///
/// - Important: Ignored fields must be `Optional` or have a default value so that the
///   Codable synthesised `init(from:)` does not throw when the key is absent from the XML.
///   Non-optional fields without a default value cause a decode error.
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLIgnore() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLIgnoreMacro"
)

/// Marks a stored property as the **text content** of the parent XML element when encoded or
/// decoded by `@XMLCodable`.
///
/// Use `@XMLText` when the element carries both XML attributes and a scalar value.
/// The annotated field is encoded as the text node of the parent element rather than
/// as a child element.
///
/// ```swift
/// @XMLCodable
/// struct Price: Codable {
///     @XMLAttribute var currency: String    // <price currency="USD">
///     @XMLText      var value: Double       //                       9.99</price>
/// }
/// ```
///
/// Encodes to: `<price currency="USD">9.99</price>`
///
/// - Important: Only scalar `Codable` types are supported. At most one `@XMLText` field
///   per type is meaningful; duplicate annotations encode the last value and decode the
///   same text into every annotated field.
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLText() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLTextMacro"
)

/// Forces a stored property's XML element to always be serialised in expanded form
/// (`<field></field>` instead of `<field/>`), even when the element has no content.
///
/// Apply this macro to stored properties inside a type annotated with `@XMLCodable`.
/// The owning type's `xmlPropertyExpandEmptyKeys` set (synthesised by `@XMLCodable`) will
/// include this field's name, causing the XML encoder to inject an empty text node into
/// child-less elements so that the writer emits the explicit open/close form.
///
/// ```swift
/// @XMLCodable
/// struct Envelope: Codable {
///     @XMLExpandEmpty var header: String?  // → <header></header>
///     var body: String                     // → <body/> if empty (global policy)
/// }
/// ```
///
/// - Note: The decoded value is identical whether the element is `<field/>` or
///   `<field></field>` — only the serialised form differs.
///
/// - Note: Without `@XMLCodable` on the enclosing type this annotation compiles
///   successfully but has no runtime effect — it is a pure syntax marker.
@attached(peer)
public macro XMLExpandEmpty() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLExpandEmptyMacro"
)

/// Synthesises `XMLFieldCodingOverrideProvider` conformance for a struct or class by
/// scanning its stored-property annotations.
///
/// `@XMLCodable` reads every `@XMLAttribute` and `@XMLChild` annotation present on the
/// type's stored properties at compile time and generates a static `xmlFieldNodeKinds`
/// dictionary used by the XML encoder and decoder to decide whether each field should be
/// serialised as an XML attribute or a child element.
///
/// ```swift
/// @XMLCodable
/// struct Order: Codable {
///     @XMLAttribute var orderId: String   // → attribute
///     @XMLChild   var total: Decimal    // → element
///     var currency: String                // → not in dict, encoder uses default
/// }
/// ```
///
/// Generates:
/// ```swift
/// extension Order: XMLFieldCodingOverrideProvider {
///     static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
///         ["orderId": .attribute, "total": .element]
///     }
/// }
/// ```
///
/// - Important: Only `struct` and `class` declarations are supported. Applying
///   `@XMLCodable` to an `enum` or `actor` emits a compile-time error.
@attached(
    extension,
    conformances: XMLFieldCodingOverrideProvider, XMLDateCodingOverrideProvider,
        XMLStringCodingOverrideProvider, XMLExpandEmptyProvider,
    names: named(xmlFieldNodeKinds), named(xmlPropertyDateHints),
        named(xmlPropertyStringHints), named(xmlPropertyExpandEmptyKeys)
)
public macro XMLCodable() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLCodableMacro"
)
