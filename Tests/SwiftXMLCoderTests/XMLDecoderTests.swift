import Foundation
import SwiftXMLCoder
import XCTest

final class XMLDecoderTests: XCTestCase {
    func test_decode_roundtrip_keyedAndUnkeyedPayload() throws {
        struct Payload: Codable, Equatable {
            let message: String
            let numbers: [Int]
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        let input = Payload(message: "hello", numbers: [1, 2, 3])
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let decoded = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_decode_singleValuePayload() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Value"))
        let data = try encoder.encode("ciao")

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Value"))
        let decoded = try decoder.decode(String.self, from: data)
        XCTAssertEqual(decoded, "ciao")
    }

    func test_decode_rootElementName_usesXMLRootNodeWhenConfigurationIsUnset() throws {
        struct Payload: Codable, Equatable, XMLRootNode {
            static let xmlRootElementName = "ServiceEnvelope"
            let message: String
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "ServiceEnvelope"))
        let data = try encoder.encode(Payload(message: "hello"))

        let decoder = XMLDecoder()
        let decoded = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(decoded, Payload(message: "hello"))
    }

    func test_decode_rootElementName_configurationOverridesXMLRootNode() throws {
        struct Payload: Codable, Equatable, XMLRootNode {
            static let xmlRootElementName = "ImplicitEnvelope"
            let message: String
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "ExplicitEnvelope"))
        let data = try encoder.encode(Payload(message: "hello"))

        let decoder = XMLDecoder(configuration: .init(rootElementName: "ExplicitEnvelope"))
        let decoded = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(decoded, Payload(message: "hello"))
    }

    func test_decode_rootElementName_fromXMLRootNode_mismatchThrowsDeterministicError() throws {
        struct Payload: Codable, XMLRootNode {
            static let xmlRootElementName = "ExpectedEnvelope"
            let message: String
        }

        let xml = "<DifferentEnvelope><message>hello</message></DifferentEnvelope>"
        let decoder = XMLDecoder()
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed.")
            }
            XCTAssertTrue((message ?? "").contains("XML6_5_ROOT_MISMATCH"))
        }
    }

    func test_decode_rootElementName_withEmptyXMLRootNode_throwsDeterministicError() throws {
        struct Payload: Codable, XMLRootNode {
            static let xmlRootElementName = "   "
            let message: String
        }

        let xml = "<Payload><message>hello</message></Payload>"
        let decoder = XMLDecoder()
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed.")
            }
            XCTAssertTrue((message ?? "").contains("XML6_7_ROOT_NAME_EMPTY"))
        }
    }

    func test_decode_dateStrategy_multiple_supportsMixedFormatsInSamePayload() throws {
        struct Payload: Decodable {
            let iso: Date
            let seconds: Date
            let custom: Date
        }

        let xml = """
        <Payload>
          <iso>2026-03-07T20:10:30Z</iso>
          <seconds>12.5</seconds>
          <custom>07/03/2026 21:15:00</custom>
        </Payload>
        """
        let descriptor = XMLDateFormatterDescriptor(
            format: "dd/MM/yyyy HH:mm:ss",
            localeIdentifier: "en_US_POSIX",
            timeZoneIdentifier: "UTC"
        )
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .multiple([
                    .xsdDateTimeISO8601,
                    .secondsSince1970,
                    .formatter(descriptor)
                ])
            )
        )

        let payload = try decoder.decode(Payload.self, from: Data(xml.utf8))
        XCTAssertEqual(payload.iso.timeIntervalSince1970, 1_772_914_230, accuracy: 0.001)
        XCTAssertEqual(payload.seconds.timeIntervalSince1970, 12.5, accuracy: 0.001)
        XCTAssertEqual(payload.custom.timeIntervalSince1970, 1_772_918_100, accuracy: 0.001)
    }

    func test_decode_dateStrategy_millisecondsSince1970_parsesDedicatedMillisField() throws {
        struct Payload: Decodable {
            let millis: Date
        }

        let xml = "<Payload><millis>12500</millis></Payload>"
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .millisecondsSince1970
            )
        )

        let payload = try decoder.decode(Payload.self, from: Data(xml.utf8))
        XCTAssertEqual(payload.millis.timeIntervalSince1970, 12.5, accuracy: 0.001)
    }

    func test_decode_dateStrategy_custom_usesContext() throws {
        struct Payload: Decodable {
            let at: Date
        }

        let xml = "<Payload><at>unix:42</at></Payload>"
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .custom { lexicalValue, context in
                    guard context.localName == "at",
                          lexicalValue.hasPrefix("unix:"),
                          let seconds = Double(lexicalValue.replacingOccurrences(of: "unix:", with: ""))
                    else {
                        throw XMLParsingError.parseFailed(message: "[XML6_5C_DATE_PARSE_FAILED] invalid custom lexical value")
                    }
                    return Date(timeIntervalSince1970: seconds)
                }
            )
        )

        let payload = try decoder.decode(Payload.self, from: Data(xml.utf8))
        XCTAssertEqual(payload.at.timeIntervalSince1970, 42, accuracy: 0.001)
    }

    func test_decode_dateStrategy_invalidValue_throwsDeterministicCode() throws {
        struct Payload: Decodable {
            let at: Date
        }

        let xml = "<Payload><at>not-a-date</at></Payload>"
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .xsdDateTimeISO8601
            )
        )

        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case let XMLParsingError.decodeFailed(_, _, message) = error else {
                return XCTFail("Expected XMLParsingError.decodeFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_5C_DATE_PARSE_FAILED"))
        }
    }

    func test_decode_dataStrategy_hex_parsesHexPayload() throws {
        struct Payload: Decodable {
            let raw: Data
        }

        let xml = "<Payload><raw>4142</raw></Payload>"
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dataDecodingStrategy: .hex
            )
        )

        let payload = try decoder.decode(Payload.self, from: Data(xml.utf8))
        XCTAssertEqual(payload.raw, Data([0x41, 0x42]))
    }

    func test_decode_dataStrategy_base64_normalizesWhitespace() throws {
        struct Payload: Decodable {
            let raw: Data
        }

        let xml = "<Payload><raw>QU I= \n</raw></Payload>"
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dataDecodingStrategy: .base64
            )
        )

        let payload = try decoder.decode(Payload.self, from: Data(xml.utf8))
        XCTAssertEqual(payload.raw, Data([0x41, 0x42]))
    }

    // MARK: - H.1: userInfo

    func test_decode_userInfo_defaultIsEmpty() throws {
        let decoder = XMLDecoder()
        XCTAssertTrue(decoder.configuration.userInfo.isEmpty)
    }

    func test_decode_userInfo_isForwardedToDecodableImplementation() throws {
        let infoKey = CodingUserInfoKey(rawValue: "test.multiplier")!
        struct MultiplierPayload: Decodable {
            let value: Int
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let raw = try container.decode(Int.self, forKey: .value)
                let multiplier = decoder.userInfo[CodingUserInfoKey(rawValue: "test.multiplier")!] as? Int ?? 1
                self.value = raw * multiplier
            }
            enum CodingKeys: String, CodingKey { case value }
        }

        let xml = "<MultiplierPayload><value>7</value></MultiplierPayload>"
        let decoder = XMLDecoder(configuration: .init(userInfo: [infoKey: 3]))
        let result = try decoder.decode(MultiplierPayload.self, from: Data(xml.utf8))
        XCTAssertEqual(result.value, 21)
    }

    // MARK: - VII.5 Source position diagnostics

    func test_sourceLine_populatedAfterParsing() throws {
        let xml = """
            <Root>
                <Child>hello</Child>
            </Root>
            """
        let parser = XMLTreeParser()
        let doc = try parser.parse(data: Data(xml.utf8))
        XCTAssertNotNil(doc.root.metadata.sourceLine, "Root element should carry a source line number after parsing.")
    }

    func test_decode_keyNotFound_errorMessageIncludesLineNumber() throws {
        struct Payload: Decodable {
            let missing: String
        }
        // Line 1: <Root>, line 2: <name> — 'missing' is absent
        let xml = "<Root>\n<name>Alice</name>\n</Root>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.decodeFailed(_, let location, let message) = error else {
                return XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
            }
            // Location is now a structured XMLSourceLocation, not just embedded in the message.
            // The message still contains "line" for backward compatibility.
            let hasLineInMessage = (message ?? "").contains("line")
            let hasLineInLocation = location?.line != nil
            XCTAssertTrue(
                hasLineInMessage || hasLineInLocation,
                "Error should surface 'line' in message or location; message='\(message ?? "<nil>")' location=\(String(describing: location))"
            )
        }
    }

    func test_decode_attributeNotFound_errorMessageIncludesLineNumber() throws {
        struct Payload: Decodable {
            let id: String
            enum CodingKeys: String, CodingKey { case id }
        }
        let xml = "<Root>\n</Root>"
        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Root",
            fieldCodingOverrides: overrides
        ))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.decodeFailed(_, let location, let message) = error else {
                return XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
            }
            let hasLineInMessage = (message ?? "").contains("line")
            let hasLineInLocation = location?.line != nil
            XCTAssertTrue(
                hasLineInMessage || hasLineInLocation,
                "Attribute error should surface 'line' in message or location; message='\(message ?? "<nil>")' location=\(String(describing: location))"
            )
        }
    }
}
