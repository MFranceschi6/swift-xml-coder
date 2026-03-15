import SwiftXMLCoder

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
///     @XMLElement  var name: String  // encoded as <name>Foo</name>
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

/// Marks a stored property as an XML **element** when encoded or decoded by `@XMLCodable`.
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
public macro XMLElement() = #externalMacro(
    module: "SwiftXMLCoderMacroImplementation",
    type: "XMLElementMacro"
)

/// Synthesises `XMLFieldCodingOverrideProvider` conformance for a struct or class by
/// scanning its stored-property annotations.
///
/// `@XMLCodable` reads every `@XMLAttribute` and `@XMLElement` annotation present on the
/// type's stored properties at compile time and generates a static `xmlFieldNodeKinds`
/// dictionary used by the XML encoder and decoder to decide whether each field should be
/// serialised as an XML attribute or a child element.
///
/// ```swift
/// @XMLCodable
/// struct Order: Codable {
///     @XMLAttribute var orderId: String   // → attribute
///     @XMLElement   var total: Decimal    // → element
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
