import Foundation

// MARK: - XMLDateFormatHint

/// Declares the XSD date format strategy for a specific property when used with `@XMLDateFormat`.
///
/// `XMLDateFormatHint` is the argument type for the `@XMLDateFormat` macro. It selects
/// which XSD date lexical format the encoder and decoder should use for a specific property,
/// overriding the global `dateEncodingStrategy` / `dateDecodingStrategy` on the encoder/decoder.
///
/// Only XSD temporal formats are supported. For custom closures or `DateFormatter`-based
/// strategies use the global encoder/decoder configuration.
///
/// ```swift
/// @XMLCodable
/// struct Schedule: Codable {
///     @XMLDateFormat(.xsdDate) var startDate: Date
///     @XMLDateFormat(.xsdTime) var startTime: Date
///     var createdAt: Date   // uses encoder-level strategy
/// }
/// ```
public enum XMLDateFormatHint: Sendable, Hashable, Codable {
    /// XSD `dateTime` format (`YYYY-MM-DDThh:mm:ssZ`).
    case xsdDateTime
    /// XSD `xs:date` format (`YYYY-MM-DD[Z/±HH:MM]`), UTC timezone.
    case xsdDate
    /// XSD `xs:date` format with an explicit timezone.
    case xsdDateWithTimezone(identifier: String)
    /// XSD `xs:time` format (`hh:mm:ss[.SSS][Z/±HH:MM]`), UTC timezone.
    case xsdTime
    /// XSD `xs:time` format with an explicit timezone.
    case xsdTimeWithTimezone(identifier: String)
    /// XSD `xs:gYear` format (`YYYY[Z/±HH:MM]`), UTC timezone.
    case xsdGYear
    /// XSD `xs:gYearMonth` format (`YYYY-MM[Z/±HH:MM]`), UTC timezone.
    case xsdGYearMonth
    /// XSD `xs:gMonth` format (`--MM[Z/±HH:MM]`), UTC timezone.
    case xsdGMonth
    /// XSD `xs:gDay` format (`---DD[Z/±HH:MM]`), UTC timezone.
    case xsdGDay
    /// XSD `xs:gMonthDay` format (`--MM-DD[Z/±HH:MM]`), UTC timezone.
    case xsdGMonthDay
    /// Seconds elapsed since Unix epoch (floating-point string).
    case secondsSince1970
    /// Milliseconds elapsed since Unix epoch (floating-point string).
    case millisecondsSince1970

    /// The corresponding `XMLEncoder.DateEncodingStrategy`.
    public var encodingStrategy: XMLEncoder.DateEncodingStrategy {
        switch self {
        case .xsdDateTime:
            return .xsdDateTimeISO8601
        case .xsdDate:
            return .xsdDate()
        case .xsdDateWithTimezone(let id):
            let timeZone = TimeZone(identifier: id) ?? .utc
            return .xsdDate(timeZone: timeZone)
        case .xsdTime:
            return .xsdTime()
        case .xsdTimeWithTimezone(let id):
            let timeZone = TimeZone(identifier: id) ?? .utc
            return .xsdTime(timeZone: timeZone)
        case .xsdGYear:
            return .xsdGYear()
        case .xsdGYearMonth:
            return .xsdGYearMonth()
        case .xsdGMonth:
            return .xsdGMonth()
        case .xsdGDay:
            return .xsdGDay()
        case .xsdGMonthDay:
            return .xsdGMonthDay()
        case .secondsSince1970:
            return .secondsSince1970
        case .millisecondsSince1970:
            return .millisecondsSince1970
        }
    }

    /// The corresponding `XMLDecoder.DateDecodingStrategy`.
    public var decodingStrategy: XMLDecoder.DateDecodingStrategy {
        switch self {
        case .xsdDateTime:
            return .xsdDateTimeISO8601
        case .xsdDate, .xsdDateWithTimezone:
            return .xsdDate
        case .xsdTime, .xsdTimeWithTimezone:
            return .xsdTime
        case .xsdGYear:
            return .xsdGYear
        case .xsdGYearMonth:
            return .xsdGYearMonth
        case .xsdGMonth:
            return .xsdGMonth
        case .xsdGDay:
            return .xsdGDay
        case .xsdGMonthDay:
            return .xsdGMonthDay
        case .secondsSince1970:
            return .secondsSince1970
        case .millisecondsSince1970:
            return .millisecondsSince1970
        }
    }
}

// MARK: - XMLDateCodingOverrideProvider

/// A type that declares per-property date format hints for use by `XMLEncoder` and `XMLDecoder`.
///
/// This protocol is synthesised automatically by `@XMLCodable` when one or more stored
/// properties are annotated with `@XMLDateFormat`. Do not conform to this protocol manually.
///
/// The encoder and decoder consult `xmlPropertyDateHints` before applying the global
/// `dateEncodingStrategy` / `dateDecodingStrategy`, so per-property annotations take
/// precedence.
public protocol XMLDateCodingOverrideProvider {
    /// A dictionary mapping stored-property names to their per-property date format hint.
    static var xmlPropertyDateHints: [String: XMLDateFormatHint] { get }
}
