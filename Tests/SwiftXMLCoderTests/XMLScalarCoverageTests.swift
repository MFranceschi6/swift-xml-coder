import Foundation
import SwiftXMLCoder
import XCTest

// swiftlint:disable type_body_length

/// Coverage tests for scalar type encode/decode paths in XMLEncoder+Codable and XMLDecoder+Codable.
/// These exercise keyed container, unkeyed container, single-value container, optional/nil detection,
/// and error paths for each supported primitive type.
final class XMLScalarCoverageTests: XCTestCase {

    // MARK: - Keyed container: all scalar types roundtrip

    func test_encodeDecode_allScalarTypes_roundtrip() throws {
        struct AllScalars: Codable, Equatable {
            let flag: Bool
            let int: Int
            let int8: Int8
            let int16: Int16
            let int32: Int32
            let int64: Int64
            let uint: UInt
            let uint8: UInt8
            let uint16: UInt16
            let uint32: UInt32
            let uint64: UInt64
            let float: Float
            let double: Double
            let text: String
        }

        let input = AllScalars(
            flag: true,
            int: -42,
            int8: -8,
            int16: -16,
            int32: -32,
            int64: -64,
            uint: 10,
            uint8: 8,
            uint16: 16,
            uint32: 32,
            uint64: 64,
            float: 3.14,
            double: 2.718,
            text: "hello"
        )

        let encoder = XMLEncoder(configuration: .init(rootElementName: "AllScalars"))
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "AllScalars"))
        let decoded = try decoder.decode(AllScalars.self, from: data)

        XCTAssertEqual(decoded.flag, input.flag)
        XCTAssertEqual(decoded.int, input.int)
        XCTAssertEqual(decoded.int8, input.int8)
        XCTAssertEqual(decoded.int16, input.int16)
        XCTAssertEqual(decoded.int32, input.int32)
        XCTAssertEqual(decoded.int64, input.int64)
        XCTAssertEqual(decoded.uint, input.uint)
        XCTAssertEqual(decoded.uint8, input.uint8)
        XCTAssertEqual(decoded.uint16, input.uint16)
        XCTAssertEqual(decoded.uint32, input.uint32)
        XCTAssertEqual(decoded.uint64, input.uint64)
        XCTAssertEqual(decoded.float, input.float, accuracy: 0.001)
        XCTAssertEqual(decoded.double, input.double, accuracy: 0.0001)
        XCTAssertEqual(decoded.text, input.text)
    }

    func test_encodeDecode_urlAndUUID_roundtrip() throws {
        struct URIPayload: Codable, Equatable {
            let url: URL
            let id: UUID
        }

        let input = URIPayload(
            url: try XCTUnwrap(URL(string: "https://example.com/soap")),
            id: try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        )

        let encoder = XMLEncoder(configuration: .init(rootElementName: "URIPayload"))
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "URIPayload"))
        let decoded = try decoder.decode(URIPayload.self, from: data)

        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_decimal_roundtrip() throws {
        struct DecimalPayload: Codable, Equatable {
            let amount: Decimal
        }

        let input = DecimalPayload(amount: try XCTUnwrap(Decimal(string: "12345.67")))

        let encoder = XMLEncoder(configuration: .init(rootElementName: "DecimalPayload"))
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "DecimalPayload"))
        let decoded = try decoder.decode(DecimalPayload.self, from: data)

        XCTAssertEqual(decoded, input)
    }

    // MARK: - Unkeyed container: array of scalars roundtrip

    func test_encodeDecode_arrayOfBool_roundtrip() throws {
        let input = [true, false, true]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Bools"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Bools"))
        let decoded = try decoder.decode([Bool].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfDouble_roundtrip() throws {
        let input = [1.1, 2.2, 3.3]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Doubles"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Doubles"))
        let decoded = try decoder.decode([Double].self, from: data)
        XCTAssertEqual(decoded[0], input[0], accuracy: 0.001)
        XCTAssertEqual(decoded[1], input[1], accuracy: 0.001)
        XCTAssertEqual(decoded[2], input[2], accuracy: 0.001)
    }

    func test_encodeDecode_arrayOfFloat_roundtrip() throws {
        let input: [Float] = [1.5, 2.5]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Floats"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Floats"))
        let decoded = try decoder.decode([Float].self, from: data)
        XCTAssertEqual(decoded[0], input[0], accuracy: 0.001)
        XCTAssertEqual(decoded[1], input[1], accuracy: 0.001)
    }

    func test_encodeDecode_arrayOfInt8_roundtrip() throws {
        let input: [Int8] = [-1, 0, 127]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Int8s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Int8s"))
        let decoded = try decoder.decode([Int8].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfUInt8_roundtrip() throws {
        let input: [UInt8] = [0, 128, 255]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "UInt8s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "UInt8s"))
        let decoded = try decoder.decode([UInt8].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfInt16_roundtrip() throws {
        let input: [Int16] = [-1000, 0, 1000]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Int16s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Int16s"))
        let decoded = try decoder.decode([Int16].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfInt32_roundtrip() throws {
        let input: [Int32] = [-100000, 0, 100000]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Int32s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Int32s"))
        let decoded = try decoder.decode([Int32].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfInt64_roundtrip() throws {
        let input: [Int64] = [-1_000_000_000, 0, 1_000_000_000]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Int64s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Int64s"))
        let decoded = try decoder.decode([Int64].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfUInt_roundtrip() throws {
        let input: [UInt] = [0, 100, 200]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "UInts"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "UInts"))
        let decoded = try decoder.decode([UInt].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfUInt16_roundtrip() throws {
        let input: [UInt16] = [0, 65535]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "UInt16s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "UInt16s"))
        let decoded = try decoder.decode([UInt16].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfUInt32_roundtrip() throws {
        let input: [UInt32] = [0, 4_294_967_295]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "UInt32s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "UInt32s"))
        let decoded = try decoder.decode([UInt32].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_encodeDecode_arrayOfUInt64_roundtrip() throws {
        let input: [UInt64] = [0, 1_000_000_000_000]
        let encoder = XMLEncoder(configuration: .init(rootElementName: "UInt64s"))
        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "UInt64s"))
        let decoded = try decoder.decode([UInt64].self, from: data)
        XCTAssertEqual(decoded, input)
    }

    // MARK: - Single-value container roundtrip

    func test_encodeDecode_singleBool_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Flag"))
        let data = try encoder.encode(true)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Flag"))
        let decoded = try decoder.decode(Bool.self, from: data)
        XCTAssertTrue(decoded)
    }

    func test_encodeDecode_singleDouble_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Val"))
        let data = try encoder.encode(Double(3.14))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        let decoded = try decoder.decode(Double.self, from: data)
        XCTAssertEqual(decoded, 3.14, accuracy: 0.001)
    }

    func test_encodeDecode_singleFloat_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Val"))
        let data = try encoder.encode(Float(1.5))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        let decoded = try decoder.decode(Float.self, from: data)
        XCTAssertEqual(decoded, 1.5, accuracy: 0.001)
    }

    func test_encodeDecode_singleInt8_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Val"))
        let data = try encoder.encode(Int8(-12))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        let decoded = try decoder.decode(Int8.self, from: data)
        XCTAssertEqual(decoded, -12)
    }

    func test_encodeDecode_singleUInt8_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Val"))
        let data = try encoder.encode(UInt8(200))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        let decoded = try decoder.decode(UInt8.self, from: data)
        XCTAssertEqual(decoded, 200)
    }

    func test_encodeDecode_singleURL_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Endpoint"))
        let url = try XCTUnwrap(URL(string: "https://api.example.com/v1"))
        let data = try encoder.encode(url)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Endpoint"))
        let decoded = try decoder.decode(URL.self, from: data)
        XCTAssertEqual(decoded, url)
    }

    func test_encodeDecode_singleUUID_roundtrip() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "ID"))
        let uuid = try XCTUnwrap(UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000"))
        let data = try encoder.encode(uuid)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "ID"))
        let decoded = try decoder.decode(UUID.self, from: data)
        XCTAssertEqual(decoded, uuid)
    }

    // MARK: - Optional / nil detection (isNilElement)

    func test_decode_optionalField_presentElement_decodesValue() throws {
        struct Payload: Codable, Equatable {
            let name: String?
        }

        let xml = Data("<Payload><name>hello</name></Payload>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let decoded = try decoder.decode(Payload.self, from: xml)
        XCTAssertEqual(decoded.name, "hello")
    }

    func test_decode_optionalField_emptyElement_decodesNil() throws {
        struct Payload: Codable, Equatable {
            let name: String?
        }

        let xml = Data("<Payload><name></name></Payload>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let decoded = try decoder.decode(Payload.self, from: xml)
        XCTAssertNil(decoded.name)
    }

    // MARK: - Error paths: invalid scalar values

    func test_decode_invalidBool_throwsParseFailed() throws {
        let xml = Data("<Flag>notabool</Flag>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Flag"))
        XCTAssertThrowsError(try decoder.decode(Bool.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_BOOL_PARSE_FAILED"))
        }
    }

    func test_decode_invalidDouble_throwsParseFailed() throws {
        let xml = Data("<Val>notanumber</Val>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        XCTAssertThrowsError(try decoder.decode(Double.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_DOUBLE_PARSE_FAILED"))
        }
    }

    func test_decode_invalidFloat_throwsParseFailed() throws {
        let xml = Data("<Val>notanumber</Val>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        XCTAssertThrowsError(try decoder.decode(Float.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_FLOAT_PARSE_FAILED"))
        }
    }

    func test_decode_invalidDecimal_throwsParseFailed() throws {
        let xml = Data("<Val>not-a-decimal</Val>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        XCTAssertThrowsError(try decoder.decode(Decimal.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_DECIMAL_PARSE_FAILED"))
        }
    }

    func test_decode_invalidURL_throwsParseFailed() throws {
        // URL(string:) percent-encodes most strings; use an unclosed IPv6 bracket to force nil.
        let xml = Data("<Endpoint>http://[invalid</Endpoint>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Endpoint"))
        XCTAssertThrowsError(try decoder.decode(URL.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_URL_PARSE_FAILED"))
        }
    }

    func test_decode_urlWithSpaces_percentEncodesAndSucceeds() throws {
        // On Linux swift-corelibs-foundation (Swift < 6) spaces are not auto-encoded by
        // URL(string:), so _xmlParityDecodeURL must encode them explicitly.
        // On Darwin and Swift 6+ Foundation, URL(string:) already handles this correctly.
        // The test verifies the decoded URL carries percent-encoded spaces on all platforms.
        let xml = Data("<Endpoint>https://example.com/path with spaces</Endpoint>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Endpoint"))
        let decoded = try decoder.decode(URL.self, from: xml)
        XCTAssertEqual(decoded.absoluteString, "https://example.com/path%20with%20spaces")
    }

    func test_decode_invalidUUID_throwsParseFailed() throws {
        let xml = Data("<ID>not-a-uuid</ID>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "ID"))
        XCTAssertThrowsError(try decoder.decode(UUID.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_UUID_PARSE_FAILED"))
        }
    }

    func test_decode_invalidInt_throwsParseFailed() throws {
        let xml = Data("<Val>notanint</Val>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Val"))
        XCTAssertThrowsError(try decoder.decode(Int.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_INTEGER_PARSE_FAILED") || "\(error)".contains("PARSE_FAILED"))
        }
    }

    // MARK: - Date encoding strategies

    func test_encode_dateStrategy_millisecondsSince1970() throws {
        struct Payload: Encodable {
            let ts: Date
        }

        let date = Date(timeIntervalSince1970: 1_000_000)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .millisecondsSince1970
            )
        )
        let tree = try encoder.encodeTree(Payload(ts: date))
        let tsElement = tree.root.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node, e.name.localName == "ts" { return e }
            return nil
        }.first
        let text = tsElement?.children.compactMap { node -> String? in
            if case .text(let t) = node { return t }
            return nil
        }.first
        XCTAssertEqual(text, "1000000000.0")
    }

    func test_encode_dateStrategy_xsdDateTime() throws {
        struct Payload: Encodable {
            let ts: Date
        }

        let date = Date(timeIntervalSince1970: 0)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .xsdDateTimeISO8601
            )
        )
        let tree = try encoder.encodeTree(Payload(ts: date))
        let tsElement = tree.root.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node, e.name.localName == "ts" { return e }
            return nil
        }.first
        let text = tsElement?.children.compactMap { node -> String? in
            if case .text(let t) = node { return t }
            return nil
        }.first
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("1970") == true)
    }

    func test_encode_dateStrategy_iso8601() throws {
        let date = Date(timeIntervalSince1970: 0)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Date",
                dateEncodingStrategy: .iso8601
            )
        )
        let data = try encoder.encode(date)
        XCTAssertFalse(data.isEmpty)
    }

    func test_encode_dateStrategy_deferredToDate() throws {
        let date = Date(timeIntervalSince1970: 12345)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Date",
                dateEncodingStrategy: .deferredToDate
            )
        )
        let data = try encoder.encode(date)
        XCTAssertFalse(data.isEmpty)
    }

    func test_encode_dateStrategy_custom_errorPath() throws {
        struct Payload: Encodable {
            let ts: Date
        }

        struct TestError: Error {}

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .custom({ _, _ in throw TestError() })
            )
        )
        XCTAssertThrowsError(try encoder.encode(Payload(ts: Date()))) { error in
            // error is wrapped in XMLParsingError
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("XML6_5C_DATE_ENCODE_CUSTOM_FAILED") || error is TestError || msg.contains("Custom date encoder failed"))
        }
    }

    // MARK: - Nested keyed/unkeyed containers (encoder side)

    func test_encode_nestedKeyedContainer_producesNestedElement() throws {
        struct Outer: Encodable {
            struct Inner: Encodable {
                struct DeepInner: Encodable {
                    let value: String
                }
                let deep: DeepInner
            }
            let inner: Inner
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Outer"))
        let tree = try encoder.encodeTree(Outer(inner: Outer.Inner(deep: .init(value: "nested"))))

        let innerElement = tree.root.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node, e.name.localName == "inner" { return e }
            return nil
        }.first
        XCTAssertNotNil(innerElement)

        let deepElement = innerElement?.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node, e.name.localName == "deep" { return e }
            return nil
        }.first
        XCTAssertNotNil(deepElement)
    }

    func test_encode_nilEncodingStrategy_omitElement_skipsNilField() throws {
        struct Payload: Encodable {
            let required: String

            enum CodingKeys: String, CodingKey {
                case required
                case optional
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(required, forKey: .required)
                try container.encodeNil(forKey: .optional)
            }
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                nilEncodingStrategy: .omitElement
            )
        )
        let tree = try encoder.encodeTree(Payload(required: "yes"))
        let children = tree.root.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node { return e }
            return nil
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name.localName, "required")
    }

    func test_encode_nilEncodingStrategy_emptyElement_includesNilField() throws {
        struct Payload: Encodable {
            let required: String

            enum CodingKeys: String, CodingKey {
                case required
                case optional
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(required, forKey: .required)
                try container.encodeNil(forKey: .optional)
            }
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                nilEncodingStrategy: .emptyElement
            )
        )
        let tree = try encoder.encodeTree(Payload(required: "yes"))
        let children = tree.root.children.compactMap { node -> XMLTreeElement? in
            if case .element(let e) = node { return e }
            return nil
        }
        XCTAssertEqual(children.count, 2)
    }
}

// swiftlint:enable function_body_length type_body_length file_length
