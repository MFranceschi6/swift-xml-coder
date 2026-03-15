import Foundation

/// A value-type descriptor for a `DateFormatter` configuration.
///
/// Use this type with ``XMLEncoder/DateEncodingStrategy/formatted(_:)`` and
/// ``XMLDecoder/DateDecodingStrategy/formatted(_:)`` to specify a custom date format string.
public struct XMLDateFormatterDescriptor: Sendable, Hashable, Codable {
    /// The `DateFormatter`-compatible format string (e.g. `"yyyy-MM-dd"`).
    public let format: String
    /// The locale identifier used when parsing/formatting. Defaults to `"en_US_POSIX"`.
    public let localeIdentifier: String
    /// The time-zone identifier used when parsing/formatting. Defaults to `"UTC"`.
    public let timeZoneIdentifier: String

    /// Creates a date formatter descriptor.
    ///
    /// - Parameters:
    ///   - format: A `DateFormatter`-compatible format string.
    ///   - localeIdentifier: A locale identifier. Defaults to `"en_US_POSIX"`.
    ///   - timeZoneIdentifier: A time-zone identifier. Defaults to `"UTC"`.
    public init(
        format: String,
        localeIdentifier: String = "en_US_POSIX",
        timeZoneIdentifier: String = "UTC"
    ) {
        self.format = format
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// Contextual information provided to custom date encoding/decoding closures.
///
/// Passed to ``XMLDateEncodingClosure`` and ``XMLDateDecodingClosure`` so that
/// closures can apply field-specific formatting rules based on the coding path or element name.
public struct XMLDateCodingContext: Sendable, Equatable {
    /// The coding path components leading to this date value.
    public let codingPath: [String]
    /// The local XML element or attribute name, if available.
    public let localName: String?
    /// The namespace URI of the element or attribute, if any.
    public let namespaceURI: String?
    /// `true` when the date value is encoded as an XML attribute; `false` for element content.
    public let isAttribute: Bool

    /// Creates a date coding context.
    public init(
        codingPath: [String],
        localName: String?,
        namespaceURI: String? = nil,
        isAttribute: Bool
    ) {
        self.codingPath = codingPath
        self.localName = localName
        self.namespaceURI = namespaceURI
        self.isAttribute = isAttribute
    }
}

/// A closure that converts a `Date` to its XML lexical string representation.
///
/// Receives the date and an ``XMLDateCodingContext`` describing where in the document
/// the date will be written.
public typealias XMLDateEncodingClosure =
    @Sendable (_ date: Date, _ context: XMLDateCodingContext) throws -> String

/// A closure that parses an XML lexical string into a `Date`.
///
/// Receives the raw string value and an ``XMLDateCodingContext`` describing where in
/// the document the date was read from.
public typealias XMLDateDecodingClosure =
    @Sendable (_ lexicalValue: String, _ context: XMLDateCodingContext) throws -> Date

enum _XMLTemporalFoundationSupport {
    static func makeDateFormatter(from descriptor: XMLDateFormatterDescriptor) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = descriptor.format
        formatter.locale = Locale(identifier: descriptor.localeIdentifier)
        formatter.timeZone = TimeZone(identifier: descriptor.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return plainFormatter.date(from: value)
    }
}
