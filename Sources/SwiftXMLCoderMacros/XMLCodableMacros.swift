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
@attached(extension, conformances: XMLFieldCodingOverrideProvider, names: named(xmlFieldNodeKinds))
public macro XMLCodable() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLCodableMacro"
)
