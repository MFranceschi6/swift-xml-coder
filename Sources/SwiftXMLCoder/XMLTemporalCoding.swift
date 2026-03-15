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

    /// Formats a `Date` as an XSD `xs:date` string (`YYYY-MM-DD[Z/±HH:MM]`).
    ///
    /// The timezone offset reflects the **DST-aware** offset at the specific `date` instant,
    /// because `xs:date` represents a specific calendar day and the offset should match that moment.
    static func formatXSDDate(_ date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let tzOffset = XMLTimezoneOffset(timeZone: timeZone, at: date)
        return String(format: "%04d-%02d-%02d", year, month, day) + tzOffset.lexicalValue
    }

    /// Parses an XSD `xs:date` string (`YYYY-MM-DD[Z/±HH:MM]`) into a `Foundation.Date`.
    static func parseXSDDate(_ value: String) -> Date? {
        let (base, tz) = _XMLTemporalParser.splitTimezone(value)
        let parts = base.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              month >= 1, month <= 12,
              day >= 1, day <= 31 else { return nil }
        let timeZone = tz?.timeZone ?? .utc
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return cal.date(from: comps)
    }
}
