import Foundation
import XCTest

@testable import SwiftXMLCoder

// MARK: - Test fixtures

// NOTE: The @XMLCodable + @XMLDateFormat macros are only available when building with
// Swift 5.9+ toolchains. Integration tests here exercise the runtime path directly by
// manually conforming to XMLDateCodingOverrideProvider, which mirrors what @XMLCodable
// synthesises, but is available on all supported Swift versions.

// Simulates what @XMLCodable + @XMLDateFormat(.xsdDate) generates on Schedule.startDate.
private struct Schedule: Codable {
    var startDate: Date   // should encode/decode as xs:date
    var startTime: Date   // should encode/decode as xs:time
    var createdAt: Date   // uses encoder-level strategy (xsdDateTime default)
}

extension Schedule: XMLFieldCodingOverrideProvider {
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { [:] }
}

extension Schedule: XMLDateCodingOverrideProvider {
    static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
        [
            "startDate": .xsdDate,
            "startTime": .xsdTime
        ]
    }
}

// A type with a single date property using .xsdGYear override.
private struct YearEvent: Codable {
    var year: Date
}

extension YearEvent: XMLFieldCodingOverrideProvider {
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { [:] }
}

extension YearEvent: XMLDateCodingOverrideProvider {
    static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
        ["year": .xsdGYear]
    }
}

// A type with no date overrides — global strategy must still apply.
private struct NoOverride: Codable {
    var timestamp: Date
}

// MARK: - Tests

final class XMLDateFormatMacroIntegrationTests: XCTestCase {

    // MARK: - XMLDateFormatHint conversions

    func test_hint_encodingStrategy_xsdDate() {
        let hint = XMLDateFormatHint.xsdDate
        if case .xsdDate = hint.encodingStrategy { } else {
            XCTFail("Expected .xsdDate encoding strategy")
        }
    }

    func test_hint_decodingStrategy_xsdDate() {
        let hint = XMLDateFormatHint.xsdDate
        if case .xsdDate = hint.decodingStrategy { } else {
            XCTFail("Expected .xsdDate decoding strategy")
        }
    }

    func test_hint_encodingStrategy_xsdTime() {
        let hint = XMLDateFormatHint.xsdTime
        if case .xsdTime = hint.encodingStrategy { } else {
            XCTFail("Expected .xsdTime encoding strategy")
        }
    }

    func test_hint_encodingStrategy_xsdDateTime() {
        let hint = XMLDateFormatHint.xsdDateTime
        if case .xsdDateTimeISO8601 = hint.encodingStrategy { } else {
            XCTFail("Expected .xsdDateTimeISO8601 encoding strategy")
        }
    }

    func test_hint_encodingStrategy_secondsSince1970() {
        let hint = XMLDateFormatHint.secondsSince1970
        if case .secondsSince1970 = hint.encodingStrategy { } else {
            XCTFail("Expected .secondsSince1970 encoding strategy")
        }
    }

    func test_hint_xsdDateWithTimezone_usesSpecifiedTimezone() {
        let hint = XMLDateFormatHint.xsdDateWithTimezone(identifier: "America/New_York")
        if case .xsdDate(let tz) = hint.encodingStrategy {
            XCTAssertEqual(tz.identifier, "America/New_York")
        } else {
            XCTFail("Expected .xsdDate(timeZone:) encoding strategy")
        }
    }

    func test_hint_xsdDateWithTimezone_unknownIdentifier_fallsBackToUTC() {
        let hint = XMLDateFormatHint.xsdDateWithTimezone(identifier: "Not/ATimezone")
        if case .xsdDate(let tz) = hint.encodingStrategy {
            XCTAssertEqual(tz.secondsFromGMT(), 0)
        } else {
            XCTFail("Expected .xsdDate(timeZone:) encoding strategy")
        }
    }

    // MARK: - Encoding: per-property hint overrides global strategy

    func test_encode_perPropertyHint_overridesGlobalStrategy() throws {
        // Global strategy: xsdDateTimeISO8601 (default).
        // Per-property: startDate → xsdDate, startTime → xsdTime.
        let encoder = XMLEncoder(configuration: .init(dateEncodingStrategy: .xsdDateTimeISO8601))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        comps.hour = 10; comps.minute = 30; comps.second = 0
        let date = try XCTUnwrap(cal.date(from: comps))

        let schedule = Schedule(startDate: date, startTime: date, createdAt: date)
        let xml = try XCTUnwrap(String(data: encoder.encode(schedule), encoding: .utf8))

        // startDate must be xs:date format
        XCTAssertTrue(xml.contains("<startDate>2024-03-15"), "Expected xs:date in startDate, got: \(xml)")
        // startTime must be xs:time format (no date part)
        XCTAssertTrue(xml.contains("<startTime>10:30:00"), "Expected xs:time in startTime, got: \(xml)")
        // createdAt must be xsdDateTime (contains 'T')
        XCTAssertTrue(xml.contains("<createdAt>2024-03-15T"), "Expected xsdDateTime in createdAt, got: \(xml)")
    }

    func test_encode_gYear_hint() throws {
        let encoder = XMLEncoder(configuration: .init(dateEncodingStrategy: .xsdDateTimeISO8601))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var comps = DateComponents()
        comps.year = 2024; comps.month = 6; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        let date = try XCTUnwrap(cal.date(from: comps))

        let event = YearEvent(year: date)
        let xml = try XCTUnwrap(String(data: encoder.encode(event), encoding: .utf8))

        XCTAssertTrue(xml.contains("<year>2024"), "Expected xs:gYear in year, got: \(xml)")
    }

    // MARK: - Decoding: per-property hint overrides global strategy

    func test_decode_perPropertyHint_overridesGlobalStrategy() throws {
        // XML uses xs:date for startDate, xs:time for startTime, xsdDateTime for createdAt.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Schedule>
            <startDate>2024-03-15Z</startDate>
            <startTime>10:30:00Z</startTime>
            <createdAt>2024-03-15T10:30:00Z</createdAt>
        </Schedule>
        """.data(using: .utf8) ?? Data()

        // Global strategy: xsdDateTime. Per-property hints override startDate and startTime.
        let decoder = XMLDecoder(configuration: .init(
            dateDecodingStrategy: .xsdDateTimeISO8601
        ))

        let schedule = try decoder.decode(Schedule.self, from: xml)

        // startDate: parsed as xs:date → midnight UTC on 2024-03-15
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let startDateComponents = cal.dateComponents([.year, .month, .day], from: schedule.startDate)
        XCTAssertEqual(startDateComponents.year, 2024)
        XCTAssertEqual(startDateComponents.month, 3)
        XCTAssertEqual(startDateComponents.day, 15)

        // startTime: parsed as xs:time → fixed date 2000-01-01, time 10:30:00
        let startTimeComponents = cal.dateComponents([.hour, .minute, .second], from: schedule.startTime)
        XCTAssertEqual(startTimeComponents.hour, 10)
        XCTAssertEqual(startTimeComponents.minute, 30)
        XCTAssertEqual(startTimeComponents.second, 0)

        // createdAt: parsed as xsdDateTime → full timestamp
        let createdAtComponents = cal.dateComponents([.year, .month, .day, .hour], from: schedule.createdAt)
        XCTAssertEqual(createdAtComponents.year, 2024)
        XCTAssertEqual(createdAtComponents.month, 3)
        XCTAssertEqual(createdAtComponents.hour, 10)
    }

    // MARK: - Roundtrip: encode then decode recovers correct dates

    func test_roundtrip_schedule() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        comps.hour = 10; comps.minute = 30; comps.second = 0
        let date = try XCTUnwrap(cal.date(from: comps))

        let original = Schedule(startDate: date, startTime: date, createdAt: date)

        let encoder = XMLEncoder()
        let decoder = XMLDecoder()

        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(Schedule.self, from: encoded)

        // startDate: xs:date round-trip — midnight on the same date
        let startComps = cal.dateComponents([.year, .month, .day], from: decoded.startDate)
        XCTAssertEqual(startComps.year, 2024)
        XCTAssertEqual(startComps.month, 3)
        XCTAssertEqual(startComps.day, 15)

        // startTime: xs:time round-trip — time components preserved
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: decoded.startTime)
        XCTAssertEqual(timeComps.hour, 10)
        XCTAssertEqual(timeComps.minute, 30)
        XCTAssertEqual(timeComps.second, 0)
    }

    // MARK: - No-override type uses global strategy unaffected

    func test_noOverride_usesGlobalStrategy() throws {
        let encoder = XMLEncoder(configuration: .init(dateEncodingStrategy: .secondsSince1970))
        let date = Date(timeIntervalSince1970: 1_000_000)
        let value = NoOverride(timestamp: date)
        let xml = try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
        XCTAssertTrue(xml.contains("<timestamp>1000000"), "Expected secondsSince1970 in timestamp, got: \(xml)")
    }

    // MARK: - XMLDateFormatHint is Codable / Equatable / Hashable

    func test_dateFormatHint_codableRoundtrip() throws {
        let hints: [XMLDateFormatHint] = [
            .xsdDate,
            .xsdTime,
            .xsdDateTime,
            .xsdGYear,
            .xsdGYearMonth,
            .xsdGMonth,
            .xsdGDay,
            .xsdGMonthDay,
            .secondsSince1970,
            .millisecondsSince1970,
            .xsdDateWithTimezone(identifier: "America/New_York"),
            .xsdTimeWithTimezone(identifier: "Europe/Rome")
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for hint in hints {
            let data = try encoder.encode(hint)
            let decoded = try decoder.decode(XMLDateFormatHint.self, from: data)
            XCTAssertEqual(hint, decoded, "Codable roundtrip failed for hint \(hint)")
        }
    }
}
