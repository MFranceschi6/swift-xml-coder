import XCTest
@testable import SwiftXMLCoder

final class XMLTemporalTypesTests: XCTestCase {

    // MARK: - XMLTimezoneOffset

    func test_timezoneOffset_utc_lexicalValue() {
        XCTAssertEqual(XMLTimezoneOffset.utc.lexicalValue, "Z")
    }

    func test_timezoneOffset_positive_lexicalValue() {
        XCTAssertEqual(XMLTimezoneOffset(hours: 5, minutes: 30).lexicalValue, "+05:30")
    }

    func test_timezoneOffset_negative_lexicalValue() {
        XCTAssertEqual(XMLTimezoneOffset(hours: -8).lexicalValue, "-08:00")
    }

    func test_timezoneOffset_parse_utc() {
        XCTAssertEqual(XMLTimezoneOffset.parse("Z"), .utc)
    }

    func test_timezoneOffset_parse_positive() {
        let tz = XMLTimezoneOffset.parse("+05:30")
        XCTAssertEqual(tz?.secondsFromUTC, 5 * 3600 + 30 * 60)
    }

    func test_timezoneOffset_parse_negative() {
        let tz = XMLTimezoneOffset.parse("-08:00")
        XCTAssertEqual(tz?.secondsFromUTC, -8 * 3600)
    }

    func test_timezoneOffset_parse_invalid_returnsNil() {
        XCTAssertNil(XMLTimezoneOffset.parse("bad"))
        XCTAssertNil(XMLTimezoneOffset.parse("+25:00"))
    }

    func test_timezoneOffset_standardTimeOf_rome_is_plus1() {
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return }
        let offset = XMLTimezoneOffset(standardTimeOf: rome)
        XCTAssertEqual(offset.secondsFromUTC, 3600)
        XCTAssertEqual(offset.lexicalValue, "+01:00")
    }

    func test_timezoneOffset_at_rome_summer_is_plus2() {
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return }
        // June 15 2024 noon UTC — DST active in Rome (+02:00)
        let summerDate = Date(timeIntervalSince1970: 1_718_445_600)
        let offset = XMLTimezoneOffset(timeZone: rome, at: summerDate)
        XCTAssertEqual(offset.secondsFromUTC, 7200)
        XCTAssertEqual(offset.lexicalValue, "+02:00")
    }

    func test_timezoneOffset_at_rome_winter_is_plus1() {
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return }
        // January 15 2024 noon UTC — standard time in Rome (+01:00)
        let winterDate = Date(timeIntervalSince1970: 1_705_320_000)
        let offset = XMLTimezoneOffset(timeZone: rome, at: winterDate)
        XCTAssertEqual(offset.secondsFromUTC, 3600)
        XCTAssertEqual(offset.lexicalValue, "+01:00")
    }

    // MARK: - XMLGYear

    func test_gYear_lexicalValue_noTimezone() {
        XCTAssertEqual(XMLGYear(year: 2024).lexicalValue, "2024")
    }

    func test_gYear_lexicalValue_utc() {
        XCTAssertEqual(XMLGYear(year: 2024, timezoneOffset: .utc).lexicalValue, "2024Z")
    }

    func test_gYear_parse_valid() {
        let val = XMLGYear(lexicalValue: "2024")
        XCTAssertEqual(val?.year, 2024)
        XCTAssertNil(val?.timezoneOffset)
    }

    func test_gYear_parse_withTimezone() {
        let val = XMLGYear(lexicalValue: "2024+02:00")
        XCTAssertEqual(val?.year, 2024)
        XCTAssertEqual(val?.timezoneOffset?.secondsFromUTC, 2 * 3600)
    }

    func test_gYear_parse_invalid_returnsNil() {
        XCTAssertNil(XMLGYear(lexicalValue: "20"))
        XCTAssertNil(XMLGYear(lexicalValue: "notayear"))
    }

    func test_gYear_roundtrip() throws {
        let original = XMLGYear(year: 1999, timezoneOffset: .utc)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLGYear.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_gYear_toDate_returnsFirstInstantOfYear() {
        let year = XMLGYear(year: 2024, timezoneOffset: .utc)
        let date = year.toDate()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        XCTAssertEqual(cal.component(.year, from: date), 2024)
        XCTAssertEqual(cal.component(.month, from: date), 1)
        XCTAssertEqual(cal.component(.day, from: date), 1)
    }

    func test_gYear_initFromDate() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        let date = try XCTUnwrap(cal.date(from: DateComponents(year: 2024, month: 6, day: 15)))
        let year = XMLGYear(date: date, timeZone: .utc)
        XCTAssertEqual(year.year, 2024)
    }

    func test_gYear_initFromDate_namedTimezone_usesStandardTimeOffset() throws {
        // Europe/Rome is UTC+1 in winter (standard), UTC+2 in summer (DST).
        // A date in summer (June) should still yield +01:00 offset (standard time).
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rome
        let summerDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2024, month: 6, day: 15)))
        let year = XMLGYear(date: summerDate, timeZone: rome)
        // Standard time offset for Rome is +3600 (+01:00)
        XCTAssertEqual(year.timezoneOffset?.secondsFromUTC, 3600)
        XCTAssertEqual(year.timezoneOffset?.lexicalValue, "+01:00")
    }

    // MARK: - XMLGYearMonth

    func test_gYearMonth_lexicalValue() {
        XCTAssertEqual(XMLGYearMonth(year: 2024, month: 3).lexicalValue, "2024-03")
    }

    func test_gYearMonth_parse_valid() {
        let val = XMLGYearMonth(lexicalValue: "2024-03")
        XCTAssertEqual(val?.year, 2024)
        XCTAssertEqual(val?.month, 3)
    }

    func test_gYearMonth_parse_withTimezone() {
        let val = XMLGYearMonth(lexicalValue: "2024-12Z")
        XCTAssertEqual(val?.year, 2024)
        XCTAssertEqual(val?.month, 12)
        XCTAssertEqual(val?.timezoneOffset, .utc)
    }

    func test_gYearMonth_parse_invalid() {
        XCTAssertNil(XMLGYearMonth(lexicalValue: "2024-13"))
        XCTAssertNil(XMLGYearMonth(lexicalValue: "2024"))
    }

    func test_gYearMonth_roundtrip() throws {
        let original = XMLGYearMonth(year: 2024, month: 7, timezoneOffset: .utc)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLGYearMonth.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLGMonth

    func test_gMonth_lexicalValue() {
        XCTAssertEqual(XMLGMonth(month: 3).lexicalValue, "--03")
    }

    func test_gMonth_lexicalValue_utc() {
        XCTAssertEqual(XMLGMonth(month: 12, timezoneOffset: .utc).lexicalValue, "--12Z")
    }

    func test_gMonth_parse_valid() {
        let val = XMLGMonth(lexicalValue: "--06")
        XCTAssertEqual(val?.month, 6)
    }

    func test_gMonth_parse_invalid() {
        XCTAssertNil(XMLGMonth(lexicalValue: "--00"))
        XCTAssertNil(XMLGMonth(lexicalValue: "--13"))
        XCTAssertNil(XMLGMonth(lexicalValue: "-03"))
    }

    func test_gMonth_roundtrip() throws {
        let original = XMLGMonth(month: 11)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLGMonth.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLGDay

    func test_gDay_lexicalValue() {
        XCTAssertEqual(XMLGDay(day: 15).lexicalValue, "---15")
    }

    func test_gDay_parse_valid() {
        let val = XMLGDay(lexicalValue: "---01")
        XCTAssertEqual(val?.day, 1)
    }

    func test_gDay_parse_withTimezone() {
        let val = XMLGDay(lexicalValue: "---31Z")
        XCTAssertEqual(val?.day, 31)
        XCTAssertEqual(val?.timezoneOffset, .utc)
    }

    func test_gDay_parse_invalid() {
        XCTAssertNil(XMLGDay(lexicalValue: "---00"))
        XCTAssertNil(XMLGDay(lexicalValue: "---32"))
        XCTAssertNil(XMLGDay(lexicalValue: "--15"))
    }

    func test_gDay_roundtrip() throws {
        let original = XMLGDay(day: 7)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLGDay.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLGMonthDay

    func test_gMonthDay_lexicalValue() {
        XCTAssertEqual(XMLGMonthDay(month: 3, day: 15).lexicalValue, "--03-15")
    }

    func test_gMonthDay_parse_valid() {
        let val = XMLGMonthDay(lexicalValue: "--12-31")
        XCTAssertEqual(val?.month, 12)
        XCTAssertEqual(val?.day, 31)
    }

    func test_gMonthDay_parse_invalid() {
        XCTAssertNil(XMLGMonthDay(lexicalValue: "--13-01"))
        XCTAssertNil(XMLGMonthDay(lexicalValue: "--03-32"))
        XCTAssertNil(XMLGMonthDay(lexicalValue: "03-15"))
    }

    func test_gMonthDay_roundtrip() throws {
        let original = XMLGMonthDay(month: 2, day: 29)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLGMonthDay.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLTime

    func test_time_lexicalValue_noFraction() {
        XCTAssertEqual(XMLTime(hour: 14, minute: 30, second: 0).lexicalValue, "14:30:00")
    }

    func test_time_lexicalValue_withTimezone() {
        XCTAssertEqual(XMLTime(hour: 9, minute: 0, second: 0, timezoneOffset: .utc).lexicalValue, "09:00:00Z")
    }

    func test_time_parse_simple() {
        let val = XMLTime(lexicalValue: "14:30:00")
        XCTAssertEqual(val?.hour, 14)
        XCTAssertEqual(val?.minute, 30)
        XCTAssertEqual(val?.second, 0)
        XCTAssertNil(val?.timezoneOffset)
    }

    func test_time_parse_withFraction() {
        let val = XMLTime(lexicalValue: "14:30:00.5Z")
        XCTAssertEqual(val?.hour, 14)
        XCTAssertEqual(val?.fractionalSeconds ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(val?.timezoneOffset, .utc)
    }

    func test_time_parse_invalid() {
        XCTAssertNil(XMLTime(lexicalValue: "25:00:00"))
        XCTAssertNil(XMLTime(lexicalValue: "14:60:00"))
        XCTAssertNil(XMLTime(lexicalValue: "not-a-time"))
    }

    func test_time_roundtrip() throws {
        let original = XMLTime(hour: 23, minute: 59, second: 59, timezoneOffset: .utc)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLTime.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_time_toDate_setsReferenceDate2000() {
        let time = XMLTime(hour: 12, minute: 0, second: 0, timezoneOffset: .utc)
        let date = time.toDate()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        XCTAssertEqual(cal.component(.year, from: date), 2000)
        XCTAssertEqual(cal.component(.hour, from: date), 12)
    }

    func test_time_initFromDate_namedTimezone_usesDSTAwareOffset() throws {
        // Europe/Rome in summer (June) is UTC+2 (DST active).
        // XMLTime.init(date:timeZone:) should capture the DST-aware offset.
        guard let rome = TimeZone(identifier: "Europe/Rome") else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rome
        let summerDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2024, month: 6, day: 15, hour: 14, minute: 0, second: 0)))
        let time = XMLTime(date: summerDate, timeZone: rome)
        // In summer, Rome is UTC+2 = 7200 seconds
        XCTAssertEqual(time.timezoneOffset?.secondsFromUTC, 7200)
        XCTAssertEqual(time.timezoneOffset?.lexicalValue, "+02:00")
    }

    // MARK: - XMLDuration

    func test_duration_lexicalValue_full() {
        let dur = XMLDuration(years: 1, months: 2, days: 3, hours: 4, minutes: 5, seconds: 6)
        XCTAssertEqual(dur.lexicalValue, "P1Y2M3DT4H5M6S")
    }

    func test_duration_lexicalValue_negative() {
        let dur = XMLDuration(isNegative: true, days: 10)
        XCTAssertEqual(dur.lexicalValue, "-P10D")
    }

    func test_duration_lexicalValue_timeOnly() {
        let dur = XMLDuration(minutes: 30)
        XCTAssertEqual(dur.lexicalValue, "PT30M")
    }

    func test_duration_lexicalValue_empty_fallsBackToP0D() {
        let dur = XMLDuration()
        XCTAssertEqual(dur.lexicalValue, "P0D")
    }

    func test_duration_parse_full() {
        let dur = XMLDuration(lexicalValue: "P1Y2M3DT4H5M6S")
        XCTAssertEqual(dur?.years, 1)
        XCTAssertEqual(dur?.months, 2)
        XCTAssertEqual(dur?.days, 3)
        XCTAssertEqual(dur?.hours, 4)
        XCTAssertEqual(dur?.minutes, 5)
        XCTAssertEqual(dur?.seconds, 6)
        XCTAssertFalse(dur?.isNegative ?? true)
    }

    func test_duration_parse_negative() {
        let dur = XMLDuration(lexicalValue: "-P10D")
        XCTAssertTrue(dur?.isNegative ?? false)
        XCTAssertEqual(dur?.days, 10)
    }

    func test_duration_parse_timeOnly() {
        let dur = XMLDuration(lexicalValue: "PT30M")
        XCTAssertEqual(dur?.minutes, 30)
        XCTAssertEqual(dur?.years, 0)
    }

    func test_duration_parse_invalid() {
        XCTAssertNil(XMLDuration(lexicalValue: "not-duration"))
        XCTAssertNil(XMLDuration(lexicalValue: "1Y2M"))  // missing P
    }

    func test_duration_roundtrip() throws {
        let original = XMLDuration(isNegative: false, years: 2, months: 6, days: 15)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XMLDuration.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_duration_toTimeInterval_daysOnly() {
        let dur = XMLDuration(days: 1)
        let interval = dur.toTimeInterval(referenceDate: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(interval, 86400, accuracy: 1)
    }

    func test_duration_toTimeInterval_negative() {
        let dur = XMLDuration(isNegative: true, days: 1)
        let interval = dur.toTimeInterval(referenceDate: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(interval, -86400, accuracy: 1)
    }

    // MARK: - DateEncodingStrategy.xsdDate / DateDecodingStrategy.xsdDate via XMLEncoder/XMLDecoder

    func test_encode_dateStrategy_xsdDate_producesCorrectLexical() throws {
        struct Wrapper: Codable { var date: Date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        let date = try XCTUnwrap(cal.date(from: DateComponents(year: 2024, month: 3, day: 15)))
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "Wrapper",
            dateEncodingStrategy: .xsdDate()
        ))
        let data = try encoder.encode(Wrapper(date: date))
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("2024-03-15"), "Expected xs:date in output, got: \(xml)")
    }

    func test_decode_dateStrategy_xsdDate_parsesCorrectly() throws {
        struct Wrapper: Codable { var date: Date }
        let xml = Data("<Wrapper><date>2024-03-15Z</date></Wrapper>".utf8)
        let decoder = XMLDecoder(configuration: .init(dateDecodingStrategy: .xsdDate))
        let result = try decoder.decode(Wrapper.self, from: xml)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        XCTAssertEqual(cal.component(.year, from: result.date), 2024)
        XCTAssertEqual(cal.component(.month, from: result.date), 3)
        XCTAssertEqual(cal.component(.day, from: result.date), 15)
    }

    func test_decode_dateStrategy_xsdGYear_parsesCorrectly() throws {
        struct Wrapper: Codable { var date: Date }
        let xml = Data("<Wrapper><date>2024Z</date></Wrapper>".utf8)
        let decoder = XMLDecoder(configuration: .init(dateDecodingStrategy: .xsdGYear))
        let result = try decoder.decode(Wrapper.self, from: xml)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        XCTAssertEqual(cal.component(.year, from: result.date), 2024)
    }

    // MARK: - XMLValidationPolicy

    func test_validationPolicy_default_isLenient() {
        XCTAssertFalse(XMLValidationPolicy.default.validateElementNames)
        XCTAssertFalse(XMLValidationPolicy.default.validateXSDTemporalValues)
    }

    func test_validationPolicy_strict_enablesAll() {
        XCTAssertTrue(XMLValidationPolicy.strict.validateElementNames)
        XCTAssertTrue(XMLValidationPolicy.strict.validateXSDTemporalValues)
    }

    func test_validationPolicy_lenient_disablesAll() {
        XCTAssertFalse(XMLValidationPolicy.lenient.validateElementNames)
        XCTAssertFalse(XMLValidationPolicy.lenient.validateXSDTemporalValues)
    }

    func test_validationPolicy_lenient_doesNotThrowOnInvalidFieldName() throws {
        struct BadKeys: Encodable {
            enum CodingKeys: String, CodingKey { case field = "my field" }
            let field: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(field, forKey: .field)
            }
        }
        // lenient policy — no validation, no throw
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root", validationPolicy: .lenient))
        XCTAssertNoThrow(try encoder.encodeTree(BadKeys(field: "v")))
    }

    func test_validationPolicy_strict_throwsOnInvalidFieldName() throws {
        struct BadKeys: Encodable {
            enum CodingKeys: String, CodingKey { case field = "my field" }
            let field: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(field, forKey: .field)
            }
        }
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root", validationPolicy: .strict))
        XCTAssertThrowsError(try encoder.encodeTree(BadKeys(field: "v")))
    }

    // MARK: - TimeZone.utc

    func test_timeZone_utc_isUTC() {
        XCTAssertEqual(TimeZone.utc.secondsFromGMT(), 0)
    }
}
