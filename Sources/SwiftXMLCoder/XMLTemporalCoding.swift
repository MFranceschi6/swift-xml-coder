import Foundation

public struct XMLDateFormatterDescriptor: Sendable, Hashable, Codable {
    public let format: String
    public let localeIdentifier: String
    public let timeZoneIdentifier: String

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

public struct XMLDateCodingContext: Sendable, Equatable {
    public let codingPath: [String]
    public let localName: String?
    public let namespaceURI: String?
    public let isAttribute: Bool

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

public typealias XMLDateEncodingClosure =
    @Sendable (_ date: Date, _ context: XMLDateCodingContext) throws -> String

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
