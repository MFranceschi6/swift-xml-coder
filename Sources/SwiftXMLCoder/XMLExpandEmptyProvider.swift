import Foundation

// MARK: - XMLExpandEmptyProvider

/// A type that declares per-property expand-empty serialisation hints for use by `XMLEncoder`.
///
/// This protocol is synthesised automatically by `@XMLCodable` when one or more stored
/// properties are annotated with `@XMLExpandEmpty`. Do not conform to this protocol manually.
///
/// The encoder consults `xmlPropertyExpandEmptyKeys` after encoding each field.  If the
/// encoded element has no children and the field name is in this set, an empty text node is
/// injected so that the XML writer emits `<field></field>` instead of `<field/>`.
///
/// ```swift
/// @XMLCodable
/// struct Envelope: Codable {
///     @XMLExpandEmpty var header: String?  // → <header></header>
///     var body: String                     // → <body/> if empty (uses global policy)
/// }
/// ```
public protocol XMLExpandEmptyProvider {
    /// The set of stored-property names that should always be serialised in expanded form.
    static var xmlPropertyExpandEmptyKeys: Set<String> { get }
}
