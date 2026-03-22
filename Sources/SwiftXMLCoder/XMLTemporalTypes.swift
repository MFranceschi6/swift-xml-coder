import Foundation

// MARK: - XSD Temporal Value Types
//
// This file defines Swift value types that correspond to the XSD partial-date
// temporal types. Each type:
//   - serialises/deserialises as its canonical XSD lexical string via Codable
//   - is Sendable, Equatable, Hashable
//   - provides an explicit opt-in bridge to Foundation.Date where meaningful
//
// `xs:date` is NOT modelled as a dedicated type — it maps directly to
// Foundation.Date via DateEncodingStrategy.xsdDate / DateDecodingStrategy.xsdDate.
//
// `xs:dateTime` is already covered by the existing .xsdDateTimeISO8601 strategy.

// MARK: - Timezone offset helper

/// An XML timezone offset, as used in XSD date/time lexical representations.
///
/// XSD allows three forms: `Z` (UTC), `+HH:MM`, or `-HH:MM`.
public struct XMLTimezoneOffset: Sendable, Equatable, Hashable, Codable {
    /// Total offset in seconds from UTC. Positive = east of UTC.
    public let secondsFromUTC: Int

    /// Creates a timezone offset from total seconds from UTC.
    public init(secondsFromUTC: Int) {
        self.secondsFromUTC = secondsFromUTC
    }

    /// UTC (`Z`).
    public static let utc = XMLTimezoneOffset(secondsFromUTC: 0)

    /// Creates a timezone offset from hours and minutes.
    /// - Parameters:
    ///   - hours: Hours offset (positive = east, negative = west).
    ///   - minutes: Additional minutes offset (0–59). Always treated as positive.
    public init(hours: Int, minutes: Int = 0) {
        let sign = hours < 0 ? -1 : 1
        self.secondsFromUTC = (abs(hours) * 3600 + abs(minutes) * 60) * sign
    }

    /// A `Foundation.TimeZone` equivalent (fixed-offset, no DST rules).
    public var timeZone: TimeZone { TimeZone(secondsFromGMT: secondsFromUTC) ?? .utc }

    /// Creates an `XMLTimezoneOffset` from a `Foundation.TimeZone` using its **standard-time**
    /// (non-DST) offset.
    ///
    /// This is the recommended way to convert a named timezone (e.g. `"Europe/Rome"`) to an XSD
    /// offset when no specific date is available. The standard-time offset is stable and
    /// unambiguous — it does not vary with daylight-saving transitions.
    ///
    /// If you need the DST-aware offset at a specific instant, use
    /// ``init(timeZone:at:)`` instead.
    ///
    /// - Parameter timeZone: The timezone whose standard (winter) offset to use.
    public init(standardTimeOf timeZone: TimeZone) {
        self.secondsFromUTC = timeZone.secondsFromGMT(for: _XMLSolarReferenceDate.winter(in: timeZone))
    }

    /// Creates an `XMLTimezoneOffset` from a `Foundation.TimeZone` at a specific instant,
    /// using the DST-aware offset for that moment.
    ///
    /// Use this when you are converting a `Date` and want the offset to reflect whether DST
    /// was active at that moment (e.g. `+02:00` for Rome in summer, `+01:00` in winter).
    ///
    /// - Parameters:
    ///   - timeZone: The timezone.
    ///   - date: The instant at which to evaluate the DST offset.
    public init(timeZone: TimeZone, at date: Date) {
        self.secondsFromUTC = timeZone.secondsFromGMT(for: date)
    }

    /// XSD lexical form: `Z`, `+HH:MM`, or `-HH:MM`.
    public var lexicalValue: String {
        if secondsFromUTC == 0 { return "Z" }
        let sign = secondsFromUTC >= 0 ? "+" : "-"
        let total = abs(secondsFromUTC)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }

    /// Parses `Z`, `+HH:MM`, or `-HH:MM`.
    static func parse(_ string: String) -> XMLTimezoneOffset? {
        if string == "Z" { return .utc }
        guard string.count == 6,
              let sign = string.first,
              sign == "+" || sign == "-" else { return nil }
        let parts = string.dropFirst().split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              hours <= 14, minutes <= 59 else { return nil }
        let total = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return XMLTimezoneOffset(secondsFromUTC: total)
    }
}

// MARK: - XMLGYear

/// An XSD `xs:gYear` value — a year without month or day.
///
/// Lexical form: `YYYY` or `YYYY[Z/±HH:MM]` (e.g. `"2024"`, `"2024Z"`, `"2024+02:00"`).
///
/// ## Foundation.Date bridge
///
/// ```swift
/// let year = XMLGYear(year: 2024)
/// let date = year.toDate()          // Jan 1 00:00:00 UTC 2024
/// let back = XMLGYear(date: date)   // XMLGYear(year: 2024)
/// ```
public struct XMLGYear: Sendable, Equatable, Hashable, Codable {
    /// The year component.
    public let year: Int
    /// The timezone offset, if present in the source lexical value.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLGYear`.
    public init(year: Int, timezoneOffset: XMLTimezoneOffset? = nil) {
        self.year = year
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        let base = String(format: "%04d", year)
        return base + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:gYear` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        guard let year = Int(base), base.count == 4 || (base.count == 5 && base.hasPrefix("-")) else { return nil }
        self.year = year
        self.timezoneOffset = tz
    }

    // MARK: Codable

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLGYear(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:gYear lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }

    // MARK: Foundation.Date bridge

    /// Returns the first instant of this year in the given timezone.
    /// - Parameter timeZone: The timezone to use for conversion. Defaults to the offset stored in
    ///   this value, falling back to UTC.
    public func toDate(timeZone: TimeZone? = nil) -> Date {
        let tz = timeZone ?? timezoneOffset?.timeZone ?? .utc
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Creates an `XMLGYear` from a `Foundation.Date`, extracting the year in the given timezone.
    ///
    /// The timezone offset stored in the result reflects the **standard-time** (non-DST) offset
    /// of `timeZone`, making the serialised value stable regardless of when in the year the
    /// conversion happens. To capture the DST-aware offset at the exact `date` instant, create
    /// the offset explicitly: `XMLTimezoneOffset(timeZone: tz, at: date)`.
    public init(date: Date, timeZone: TimeZone = .utc) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.year = cal.component(.year, from: date)
        self.timezoneOffset = XMLTimezoneOffset(standardTimeOf: timeZone)
    }
}

// MARK: - XMLGYearMonth

/// An XSD `xs:gYearMonth` value — a year and month without a day.
///
/// Lexical form: `YYYY-MM[Z/±HH:MM]` (e.g. `"2024-03"`, `"2024-03Z"`).
public struct XMLGYearMonth: Sendable, Equatable, Hashable, Codable {
    /// The year component.
    public let year: Int
    /// The month component (1–12).
    public let month: Int
    /// The timezone offset, if present.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLGYearMonth`.
    public init(year: Int, month: Int, timezoneOffset: XMLTimezoneOffset? = nil) {
        self.year = year
        self.month = month
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        String(format: "%04d-%02d", year, month) + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:gYearMonth` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        let parts = base.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              month >= 1, month <= 12 else { return nil }
        self.year = year
        self.month = month
        self.timezoneOffset = tz
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLGYearMonth(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:gYearMonth lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }

    /// Returns the first instant of this year-month in the given timezone.
    public func toDate(timeZone: TimeZone? = nil) -> Date {
        let tz = timeZone ?? timezoneOffset?.timeZone ?? .utc
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Creates an `XMLGYearMonth` from a `Foundation.Date`.
    ///
    /// The timezone offset uses the **standard-time** offset of `timeZone`. See ``XMLGYear/init(date:timeZone:)``
    /// for rationale and the DST-aware alternative.
    public init(date: Date, timeZone: TimeZone = .utc) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.year = cal.component(.year, from: date)
        self.month = cal.component(.month, from: date)
        self.timezoneOffset = XMLTimezoneOffset(standardTimeOf: timeZone)
    }
}

// MARK: - XMLGMonth

/// An XSD `xs:gMonth` value — a month without year or day.
///
/// Lexical form: `--MM[Z/±HH:MM]` (e.g. `"--03"`, `"--12Z"`).
public struct XMLGMonth: Sendable, Equatable, Hashable, Codable {
    /// The month component (1–12).
    public let month: Int
    /// The timezone offset, if present.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLGMonth`.
    public init(month: Int, timezoneOffset: XMLTimezoneOffset? = nil) {
        self.month = month
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        String(format: "--%02d", month) + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:gMonth` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        guard base.hasPrefix("--"), base.count == 4,
              let month = Int(base.dropFirst(2)),
              month >= 1, month <= 12 else { return nil }
        self.month = month
        self.timezoneOffset = tz
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLGMonth(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:gMonth lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }
}

// MARK: - XMLGDay

/// An XSD `xs:gDay` value — a day-of-month without year or month.
///
/// Lexical form: `---DD[Z/±HH:MM]` (e.g. `"---15"`, `"---01Z"`).
public struct XMLGDay: Sendable, Equatable, Hashable, Codable {
    /// The day-of-month component (1–31).
    public let day: Int
    /// The timezone offset, if present.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLGDay`.
    public init(day: Int, timezoneOffset: XMLTimezoneOffset? = nil) {
        self.day = day
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        String(format: "---%02d", day) + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:gDay` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        guard base.hasPrefix("---"), base.count == 5,
              let day = Int(base.dropFirst(3)),
              day >= 1, day <= 31 else { return nil }
        self.day = day
        self.timezoneOffset = tz
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLGDay(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:gDay lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }
}

// MARK: - XMLGMonthDay

/// An XSD `xs:gMonthDay` value — a month and day without a year.
///
/// Lexical form: `--MM-DD[Z/±HH:MM]` (e.g. `"--03-15"`, `"--12-31Z"`).
public struct XMLGMonthDay: Sendable, Equatable, Hashable, Codable {
    /// The month component (1–12).
    public let month: Int
    /// The day-of-month component (1–31).
    public let day: Int
    /// The timezone offset, if present.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLGMonthDay`.
    public init(month: Int, day: Int, timezoneOffset: XMLTimezoneOffset? = nil) {
        self.month = month
        self.day = day
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        String(format: "--%02d-%02d", month, day) + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:gMonthDay` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        // format: --MM-DD
        guard base.hasPrefix("--"), base.count == 7 else { return nil }
        let inner = base.dropFirst(2) // MM-DD
        let parts = inner.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              month >= 1, month <= 12,
              day >= 1, day <= 31 else { return nil }
        self.month = month
        self.day = day
        self.timezoneOffset = tz
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLGMonthDay(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:gMonthDay lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }
}

// MARK: - XMLTime

/// An XSD `xs:time` value — a time-of-day without a date.
///
/// Lexical form: `hh:mm:ss[.SSS][Z/±HH:MM]`
/// (e.g. `"14:30:00"`, `"14:30:00.500Z"`, `"09:00:00+05:30"`).
///
/// ## Foundation.Date bridge
///
/// Converts to/from `Foundation.Date` using a fixed reference date (2000-01-01 UTC).
/// The date component is discarded.
///
/// ```swift
/// let time = XMLTime(hour: 14, minute: 30, second: 0)
/// let date = time.toDate()
/// let back = XMLTime(date: date)
/// ```
public struct XMLTime: Sendable, Equatable, Hashable, Codable {
    /// The hour component (0–23).
    public let hour: Int
    /// The minute component (0–59).
    public let minute: Int
    /// The second component (0–59).
    public let second: Int
    /// The fractional seconds (0.0 ..< 1.0).
    public let fractionalSeconds: Double
    /// The timezone offset, if present.
    public let timezoneOffset: XMLTimezoneOffset?

    /// Creates an `XMLTime`.
    public init(
        hour: Int,
        minute: Int,
        second: Int,
        fractionalSeconds: Double = 0,
        timezoneOffset: XMLTimezoneOffset? = nil
    ) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.fractionalSeconds = fractionalSeconds
        self.timezoneOffset = timezoneOffset
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        var base = String(format: "%02d:%02d:%02d", hour, minute, second)
        if fractionalSeconds > 0 {
            // Format fractional part, trimming trailing zeros
            let fracStr = String(format: "%.9f", fractionalSeconds).dropFirst() // ".NNN..."
            let trimmed = fracStr.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            if !trimmed.isEmpty && trimmed != "." {
                base += trimmed
            }
        }
        return base + (timezoneOffset?.lexicalValue ?? "")
    }

    /// Parses an XSD `xs:time` lexical string.
    public init?(lexicalValue: String) {
        let (base, tz) = _XMLTemporalParser.splitTimezone(lexicalValue)
        // base: hh:mm:ss[.SSS...]
        let dotIdx = base.firstIndex(of: ".")
        let wholePart = dotIdx.map { String(base[..<$0]) } ?? base
        let fracPart = dotIdx.map { String(base[base.index(after: $0)...]) }

        let parts = wholePart.split(separator: ":")
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]),
              hour <= 23, minute <= 59, second <= 59 else { return nil }

        self.hour = hour
        self.minute = minute
        self.second = second
        self.fractionalSeconds = fracPart.flatMap { Double("0.\($0)") } ?? 0
        self.timezoneOffset = tz
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLTime(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:time lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }

    // MARK: Foundation.Date bridge

    /// Converts this time to a `Foundation.Date` on the XSD epoch reference date (2000-01-01).
    /// The date component is always 2000-01-01; only the time is meaningful.
    public func toDate(timeZone: TimeZone? = nil) -> Date {
        let tz = timeZone ?? timezoneOffset?.timeZone ?? .utc
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = 2000; comps.month = 1; comps.day = 1
        comps.hour = hour; comps.minute = minute; comps.second = second
        let base = cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        return base.addingTimeInterval(fractionalSeconds)
    }

    /// Creates an `XMLTime` from a `Foundation.Date`, extracting only the time components.
    ///
    /// The timezone offset uses the **DST-aware** offset at the exact `date` instant, because
    /// `XMLTime` represents a specific time of day — the offset should match the moment being
    /// described. For example, `14:30:00+02:00` correctly reflects Rome summer time.
    public init(date: Date, timeZone: TimeZone = .utc) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.hour = cal.component(.hour, from: date)
        self.minute = cal.component(.minute, from: date)
        self.second = cal.component(.second, from: date)
        let truncated = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)) ?? date
        self.fractionalSeconds = date.timeIntervalSince(truncated)
        self.timezoneOffset = XMLTimezoneOffset(timeZone: timeZone, at: date)
    }
}

// MARK: - XMLDuration

/// An XSD `xs:duration` value.
///
/// Lexical form: `[-]P[nY][nM][nD][T[nH][nM][nS]]`
/// (e.g. `"P1Y2M3DT4H5M6S"`, `"-P10D"`, `"PT30M"`).
///
/// XSD duration deliberately mixes calendar units (years, months) and clock units
/// (days, hours, minutes, seconds). Because months have variable length,
/// `toTimeInterval(referenceDate:)` requires a reference point.
///
/// ## Foundation.Date bridge
///
/// ```swift
/// let duration = XMLDuration(years: 1, months: 6)
/// let interval = duration.toTimeInterval(referenceDate: Date())
/// ```
public struct XMLDuration: Sendable, Equatable, Hashable, Codable {
    /// `true` for negative durations (prefix `-`).
    public let isNegative: Bool
    /// Years component.
    public let years: Int
    /// Months component (0–11 semantically, but any non-negative integer is valid in XSD).
    public let months: Int
    /// Days component.
    public let days: Int
    /// Hours component.
    public let hours: Int
    /// Minutes component.
    public let minutes: Int
    /// Seconds component (integer part).
    public let seconds: Int
    /// Fractional seconds (0.0 ..< 1.0).
    public let fractionalSeconds: Double

    /// Creates an `XMLDuration`.
    public init(
        isNegative: Bool = false,
        years: Int = 0,
        months: Int = 0,
        days: Int = 0,
        hours: Int = 0,
        minutes: Int = 0,
        seconds: Int = 0,
        fractionalSeconds: Double = 0
    ) {
        self.isNegative = isNegative
        self.years = years
        self.months = months
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.fractionalSeconds = fractionalSeconds
    }

    /// The XSD canonical lexical representation.
    public var lexicalValue: String {
        var result = isNegative ? "-P" : "P"
        if years != 0 { result += "\(years)Y" }
        if months != 0 { result += "\(months)M" }
        if days != 0 { result += "\(days)D" }
        let hasTime = hours != 0 || minutes != 0 || seconds != 0 || fractionalSeconds != 0
        if hasTime {
            result += "T"
            if hours != 0 { result += "\(hours)H" }
            if minutes != 0 { result += "\(minutes)M" }
            if seconds != 0 || fractionalSeconds != 0 {
                if fractionalSeconds != 0 {
                    let fracStr = String(format: "%.9f", fractionalSeconds).dropFirst() // ".NNN..."
                    let trimmed = fracStr.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                    result += "\(seconds)\(trimmed)S"
                } else {
                    result += "\(seconds)S"
                }
            }
        }
        // P with no components → P0D (XSD requires at least one designator)
        if result == "P" || result == "-P" { result += "0D" }
        return result
    }

    /// Parses an XSD `xs:duration` lexical string.
    public init?(lexicalValue: String) {
        var rest = lexicalValue[...]
        var negative = false
        if rest.hasPrefix("-") {
            negative = true
            rest = rest.dropFirst()
        }
        guard rest.hasPrefix("P") else { return nil }
        rest = rest.dropFirst()

        var years = 0, months = 0, days = 0, hours = 0, minutes = 0, seconds = 0
        var fractionalSeconds: Double = 0

        // Parse date part (before 'T')
        let tIdx = rest.firstIndex(of: "T")
        let datePart = tIdx.map { rest[..<$0] } ?? rest
        let timePart = tIdx.map { rest[rest.index(after: $0)...] }

        if let parsed = _XMLTemporalParser.parseDurationDatePart(String(datePart)) {
            (years, months, days) = parsed
        } else if !datePart.isEmpty {
            return nil
        }

        if let tp = timePart {
            if let parsed = _XMLTemporalParser.parseDurationTimePart(String(tp)) {
                hours = parsed.hours
                minutes = parsed.minutes
                seconds = parsed.seconds
                fractionalSeconds = parsed.frac
            } else {
                return nil
            }
        }

        self.isNegative = negative
        self.years = years; self.months = months; self.days = days
        self.hours = hours; self.minutes = minutes; self.seconds = seconds
        self.fractionalSeconds = fractionalSeconds
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = XMLDuration(lexicalValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid xs:duration lexical value: '\(raw)'"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(lexicalValue)
    }

    // MARK: Foundation.Date bridge

    /// Converts this duration to a `TimeInterval` using a reference date to resolve
    /// calendar-dependent components (years, months).
    ///
    /// Because XSD years and months have variable length (e.g. February, leap years),
    /// this conversion requires a reference point. Days, hours, minutes, and seconds
    /// are converted exactly.
    ///
    /// - Parameter referenceDate: The date from which to measure year and month components.
    /// - Returns: The equivalent `TimeInterval`, negative for negative durations.
    public func toTimeInterval(referenceDate: Date) -> TimeInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .utc
        var comps = DateComponents()
        comps.year = years
        comps.month = months
        comps.day = days
        comps.hour = hours
        comps.minute = minutes
        comps.second = seconds
        let endDate = cal.date(byAdding: comps, to: referenceDate) ?? referenceDate
        let rawInterval = endDate.timeIntervalSince(referenceDate)
            + fractionalSeconds
        return isNegative ? -rawInterval : rawInterval
    }
}

// MARK: - Internal parsing helpers

enum _XMLTemporalParser {
    /// Splits a lexical value into (base, timezoneOffset?).
    /// Timezone suffix is `Z`, `+HH:MM`, or `-HH:MM` at the end.
    static func splitTimezone(_ value: String) -> (base: String, tz: XMLTimezoneOffset?) {
        if value.hasSuffix("Z") {
            return (String(value.dropLast()), .utc)
        }
        // Try ±HH:MM at end (6 chars)
        if value.count > 6 {
            let suffixStart = value.index(value.endIndex, offsetBy: -6)
            let suffix = String(value[suffixStart...])
            if let tz = XMLTimezoneOffset.parse(suffix) {
                return (String(value[..<suffixStart]), tz)
            }
        }
        return (value, nil)
    }

    /// Parses the date portion of a duration (`nYnMnD`).
    static func parseDurationDatePart(_ part: String) -> (years: Int, months: Int, days: Int)? {
        var years = 0, months = 0, days = 0
        var remaining = part[...]
        while !remaining.isEmpty {
            guard let (num, unit, rest) = consumeDurationComponent(remaining) else { return nil }
            switch unit {
            case "Y": years = num
            case "M": months = num
            case "D": days = num
            default: return nil
            }
            remaining = rest
        }
        return (years, months, days)
    }

    struct DurationTimeParts {
        var hours: Int
        var minutes: Int
        var seconds: Int
        var frac: Double
    }

    /// Parses the time portion of a duration (`nHnMnS`).
    static func parseDurationTimePart(_ part: String) -> DurationTimeParts? {
        var result = DurationTimeParts(hours: 0, minutes: 0, seconds: 0, frac: 0)
        var remaining = part[...]
        while !remaining.isEmpty {
            guard let (num, unit, rest) = consumeDurationComponent(remaining) else { return nil }
            switch unit {
            case "H": result.hours = num
            case "M": result.minutes = num
            case "S":
                result.seconds = num
                // fractional part embedded in the num string is handled below
            default: return nil
            }
            remaining = rest
            // If unit is S, check if the original token had a decimal
            if unit == "S" {
                // Re-examine the original token for fractional seconds
                let tokenStr = String(part[part.startIndex...])
                if let sRange = tokenStr.range(of: "S"),
                   let dotRange = tokenStr.range(of: "."),
                   dotRange.lowerBound < sRange.lowerBound {
                    let fracDigits = tokenStr[tokenStr.index(after: dotRange.lowerBound)..<sRange.lowerBound]
                    result.frac = Double("0.\(fracDigits)") ?? 0
                }
            }
        }
        return result
    }

    /// Consumes one `nnn[U]` component from a duration string slice.
    /// Returns (number, unit, remainder) or nil.
    private static func consumeDurationComponent(_ slice: Substring) -> (Int, Character, Substring)? {
        var end = slice.startIndex
        var hasDot = false
        while end < slice.endIndex {
            let ch = slice[end]
            if ch.isNumber {
                end = slice.index(after: end)
            } else if ch == "." && !hasDot {
                hasDot = true
                end = slice.index(after: end)
            } else {
                break
            }
        }
        guard end > slice.startIndex, end < slice.endIndex else { return nil }
        let numStr = String(slice[..<end])
        let unit = slice[end]
        let rest = slice[slice.index(after: end)...]
        // For seconds we allow decimal; for others only integer
        if hasDot {
            guard unit == "S", let _ = Double(numStr) else { return nil }
            return (Int(numStr.components(separatedBy: ".")[0]) ?? 0, unit, rest)
        }
        guard let num = Int(numStr) else { return nil }
        return (num, unit, rest)
    }
}

// MARK: - Solar reference date helper

/// Returns a reference `Date` guaranteed to fall in standard time (non-DST) for a given timezone.
/// Used to compute the stable winter offset from a named timezone.
enum _XMLSolarReferenceDate {
    /// Returns January 15 of the current year at noon UTC — reliably winter in the Northern
    /// Hemisphere. For Southern-Hemisphere timezones this is summer, but Foundation's
    /// `isDaylightSavingTime(for:)` is used to find a valid winter date regardless.
    static func winter(in timeZone: TimeZone) -> Date {
        // Use a fixed reference: Jan 15 of year 2000, noon UTC.
        // For timezones that observe DST in January (Southern Hemisphere), we shift to July.
        let jan15 = Date(timeIntervalSince1970: 948_369_600)  // 2000-01-20 00:00:00 UTC (approx)
        if timeZone.isDaylightSavingTime(for: jan15) {
            // Southern Hemisphere — use July instead
            return Date(timeIntervalSince1970: 963_532_800)  // 2000-07-14 00:00:00 UTC (approx)
        }
        return jan15
    }
}

// MARK: - TimeZone convenience

extension TimeZone {
    /// UTC timezone (`Identifier: "UTC"`).
    public static let utc = TimeZone(identifier: "UTC")!
}
