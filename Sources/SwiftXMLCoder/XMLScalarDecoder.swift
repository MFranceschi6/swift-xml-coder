import Foundation

struct _XMLScalarDecoder {
    let options: _XMLDecoderOptions
    let fail: (_ codingPath: [CodingKey], _ message: String) -> XMLParsingError

    func isKnownScalarType(_ type: Any.Type) -> Bool {
        type == Bool.self ||
            type == String.self ||
            type == Double.self ||
            type == Float.self ||
            type == Int.self ||
            type == Int8.self ||
            type == Int16.self ||
            type == Int32.self ||
            type == Int64.self ||
            type == UInt.self ||
            type == UInt8.self ||
            type == UInt16.self ||
            type == UInt32.self ||
            type == UInt64.self ||
            type == Decimal.self ||
            type == URL.self ||
            type == UUID.self ||
            type == Date.self ||
            type == Data.self
    }

    func decodeScalarFromLexical<T: Decodable>(
        _ lexical: String,
        as type: T.Type,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> T? {
        if type == String.self {
            return lexical as? T
        }

        if type == Bool.self {
            guard let parsed = parseBool(lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_BOOL_PARSE_FAILED] Unable to parse Bool from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
        }
        if type == Int.self { return try parseInteger(lexical, as: Int.self, codingPath: codingPath) as? T }
        if type == Int8.self { return try parseInteger(lexical, as: Int8.self, codingPath: codingPath) as? T }
        if type == Int16.self { return try parseInteger(lexical, as: Int16.self, codingPath: codingPath) as? T }
        if type == Int32.self { return try parseInteger(lexical, as: Int32.self, codingPath: codingPath) as? T }
        if type == Int64.self { return try parseInteger(lexical, as: Int64.self, codingPath: codingPath) as? T }
        if type == UInt.self { return try parseInteger(lexical, as: UInt.self, codingPath: codingPath) as? T }
        if type == UInt8.self { return try parseInteger(lexical, as: UInt8.self, codingPath: codingPath) as? T }
        if type == UInt16.self { return try parseInteger(lexical, as: UInt16.self, codingPath: codingPath) as? T }
        if type == UInt32.self { return try parseInteger(lexical, as: UInt32.self, codingPath: codingPath) as? T }
        if type == UInt64.self { return try parseInteger(lexical, as: UInt64.self, codingPath: codingPath) as? T }

        if type == Double.self {
            guard let parsed = Double(lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_DOUBLE_PARSE_FAILED] Unable to parse Double from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
        }

        if type == Float.self {
            guard let parsed = Float(lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_FLOAT_PARSE_FAILED] Unable to parse Float from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
        }

        if type == Decimal.self {
            guard let parsed = Decimal(string: lexical, locale: Locale(identifier: "en_US_POSIX")) else {
                throw fail(codingPath,
                    "[XML6_5C_DECIMAL_PARSE_FAILED] Unable to parse Decimal from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
        }

        if type == URL.self {
            #if !canImport(Darwin) && swift(<6.0)
            guard let parsed = _xmlParityDecodeURL(lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_URL_PARSE_FAILED] Unable to parse URL from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
            #else
            guard let parsed = URL(string: lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_URL_PARSE_FAILED] Unable to parse URL from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
            #endif
        }

        if type == UUID.self {
            guard let parsed = UUID(uuidString: lexical) else {
                throw fail(codingPath,
                    "[XML6_5C_UUID_PARSE_FAILED] Unable to parse UUID from '\(lexical)' at path '\(renderCodingPath(codingPath))'.")
            }
            return parsed as? T
        }

        if type == Date.self {
            if case .deferredToDate = options.dateDecodingStrategy {
                return nil
            }
            let parsed = try parseDate(
                lexical,
                codingPath: codingPath,
                localName: localName,
                isAttribute: isAttribute
            )
            return parsed as? T
        }

        if type == Data.self {
            if case .deferredToData = options.dataDecodingStrategy {
                return nil
            }
            let parsed = try parseData(lexical, codingPath: codingPath)
            return parsed as? T
        }

        return nil
    }

    private func parseInteger<T: LosslessStringConvertible>(
        _ value: String,
        as type: T.Type,
        codingPath: [CodingKey]
    ) throws -> T {
        guard let parsed = T(value) else {
            throw fail(codingPath,
                "[XML6_5C_INTEGER_PARSE_FAILED] Unable to parse integer from '\(value)' at path '\(renderCodingPath(codingPath))'.")
        }
        return parsed
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1":
            return true
        case "false", "0":
            return false
        default:
            return nil
        }
    }

    private func parseDate(
        _ lexicalValue: String,
        codingPath: [CodingKey],
        localName: String?,
        isAttribute: Bool
    ) throws -> Date {
        let context = XMLDateCodingContext(
            codingPath: codingPath.map(\.stringValue),
            localName: localName,
            namespaceURI: nil,
            isAttribute: isAttribute
        )
        let effectiveStrategy: XMLDecoder.DateDecodingStrategy
        if let name = localName, let hint = options.perPropertyDateHints[name] {
            options.logger.trace(
                "Per-property date hint applied",
                metadata: ["field": "\(name)", "hint": "\(hint)"]
            )
            effectiveStrategy = hint.decodingStrategy
        } else {
            effectiveStrategy = options.dateDecodingStrategy
        }
        if let parsed = try attemptParseDate(lexicalValue, strategy: effectiveStrategy, context: context) {
            return parsed
        }
        throw fail(codingPath,
            "[XML6_5C_DATE_PARSE_FAILED] Unable to parse Date from '\(lexicalValue)' at path '\(renderCodingPath(codingPath))'.")
    }

    private func attemptParseDate(
        _ lexicalValue: String,
        strategy: XMLDecoder.DateDecodingStrategy,
        context: XMLDateCodingContext
    ) throws -> Date? {
        switch strategy {
        case .deferredToDate:
            return nil
        case .secondsSince1970:
            guard let seconds = Double(lexicalValue) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        case .millisecondsSince1970:
            guard let millis = Double(lexicalValue) else { return nil }
            return Date(timeIntervalSince1970: millis / 1000.0)
        case .xsdDateTimeISO8601, .iso8601:
            return _XMLTemporalFoundationSupport.parseISO8601(lexicalValue)
        case .xsdDate:
            return _XMLTemporalFoundationSupport.parseXSDDate(lexicalValue)
        case .xsdTime:
            return XMLTime(lexicalValue: lexicalValue)?.toDate()
        case .xsdGYear:
            return XMLGYear(lexicalValue: lexicalValue)?.toDate()
        case .xsdGYearMonth:
            return XMLGYearMonth(lexicalValue: lexicalValue)?.toDate()
        case .xsdGMonth:
            guard let gMonth = XMLGMonth(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gMonth.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000
            comps.month = gMonth.month
            comps.day = 1
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            return cal.date(from: comps)
        case .xsdGDay:
            guard let gDay = XMLGDay(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gDay.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000
            comps.month = 1
            comps.day = gDay.day
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            return cal.date(from: comps)
        case .xsdGMonthDay:
            guard let gMonthDay = XMLGMonthDay(lexicalValue: lexicalValue) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = gMonthDay.timezoneOffset?.timeZone ?? .utc
            var comps = DateComponents()
            comps.year = 2000
            comps.month = gMonthDay.month
            comps.day = gMonthDay.day
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            return cal.date(from: comps)
        case .formatter(let descriptor):
            return _XMLTemporalFoundationSupport.makeDateFormatter(from: descriptor).date(from: lexicalValue)
        case .multiple(let strategies):
            for strategy in strategies {
                if let parsed = try attemptParseDate(lexicalValue, strategy: strategy, context: context) {
                    return parsed
                }
            }
            return nil
        case .custom(let closure):
            do {
                return try closure(lexicalValue, context)
            } catch let error as XMLParsingError {
                throw error
            } catch {
                throw fail(
                    context.codingPath.compactMap { _XMLDecodingKey(stringValue: $0) },
                    "[XML6_5C_DATE_PARSE_FAILED] Custom date decoder failed at path '\(context.codingPath.joined(separator: "."))': \(error)."
                )
            }
        }
    }

    private func parseData(_ lexicalValue: String, codingPath: [CodingKey]) throws -> Data {
        switch options.dataDecodingStrategy {
        case .deferredToData:
            let path = renderCodingPath(codingPath)
            throw fail(codingPath,
                "[XML6_5B_DATA_UNSUPPORTED_STRATEGY] Data strategy deferredToData requires deferred decoding at path '\(path)'.")
        case .base64:
            let normalized = lexicalValue.filter { $0.isWhitespace == false }
            guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else {
                throw fail(codingPath,
                    "[XML6_5B_DATA_PARSE_FAILED] Unable to parse base64 Data at path '\(renderCodingPath(codingPath))'.")
            }
            return data
        case .hex:
            guard let data = decodeHex(lexicalValue.filter { $0.isWhitespace == false }) else {
                throw fail(codingPath,
                    "[XML6_5B_DATA_PARSE_FAILED] Unable to parse hex Data at path '\(renderCodingPath(codingPath))'.")
            }
            return data
        }
    }

    private func decodeHex(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else {
            return nil
        }
        var data = Data(capacity: value.count / 2)
        var cursor = value.startIndex
        while cursor < value.endIndex {
            let next = value.index(cursor, offsetBy: 2)
            let byteString = value[cursor..<next]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            cursor = next
        }
        return data
    }

    private func renderCodingPath(_ codingPath: [CodingKey]) -> String {
        let rendered = codingPath.map(\.stringValue).joined(separator: ".")
        return rendered.isEmpty ? "<root>" : rendered
    }
}
