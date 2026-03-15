import Foundation

// MARK: - XMLStringEncodingHint

/// Declares the string encoding strategy for a specific property when used with `@XMLCDATA`.
///
/// `XMLStringEncodingHint` is the internal representation synthesised by `@XMLCodable`
/// for properties annotated with `@XMLCDATA`. It overrides the global `stringEncodingStrategy`
/// on the encoder for that specific property.
///
/// ```swift
/// @XMLCodable
/// struct Article: Codable {
///     var title: String          // uses global stringEncodingStrategy
///     @XMLCDATA var body: String  // always emitted as <body><![CDATA[...]]></body>
/// }
/// ```
public enum XMLStringEncodingHint: Sendable, Hashable, Codable {
    /// Emit the string as plain XML text (special characters are escaped).
    case text
    /// Wrap the string in a CDATA section (`<![CDATA[...]]>`).
    case cdata
}

// MARK: - XMLStringCodingOverrideProvider

/// A type that declares per-property string encoding hints for use by `XMLEncoder`.
///
/// This protocol is synthesised automatically by `@XMLCodable` when one or more stored
/// properties are annotated with `@XMLCDATA`. Do not conform to this protocol manually.
///
/// The encoder consults `xmlPropertyStringHints` before applying the global
/// `stringEncodingStrategy`, so per-property annotations take precedence.
public protocol XMLStringCodingOverrideProvider {
    /// A dictionary mapping stored-property names to their per-property string encoding hint.
    static var xmlPropertyStringHints: [String: XMLStringEncodingHint] { get }
}
