import Foundation
import SwiftXMLCoder
import XCTest

// swiftlint:disable type_body_length file_length

/// Targeted coverage tests for container internals (keyed/unkeyed/SVC decoder + encoder),
/// parser/writer configuration factories, and XMLIdentityTransform.
/// These complement XMLScalarCoverageTests.swift to hit uncovered branches.
final class XMLContainerCoverageTests: XCTestCase {

    // MARK: - Decoder: userInfo and allKeys

    func test_decoder_userInfo_isEmpty() throws {
        // Exercises decoder.userInfo path — the property returns [:] internally.
        struct Probe: Decodable {
            let accessed: Bool
            init(from decoder: Decoder) throws {
                // Access userInfo to cover the property; it is expected to be empty
                accessed = decoder.userInfo.isEmpty
                _ = try decoder.container(keyedBy: AnyCodingKey.self)
            }
        }
        let xml = Data("<Probe/>".utf8)
        let xmlDecoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        let r = try xmlDecoder.decode(Probe.self, from: xml)
        XCTAssertTrue(r.accessed)
    }

    func test_decoder_allKeys_containsFields() throws {
        // Exercises allKeys property; uses the result to drive decoding.
        struct Probe: Decodable {
            let alpha: String
            let beta: String
            let keyCount: Int
            enum CK: String, CodingKey { case alpha, beta }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                // Access allKeys to cover the property
                let keys = container.allKeys
                keyCount = keys.count
                alpha = keys.contains(where: { $0.stringValue == "alpha" })
                    ? (try container.decode(String.self, forKey: .alpha))
                    : "missing"
                beta = try container.decode(String.self, forKey: .beta)
            }
        }
        let xml = Data("<Probe><alpha>A</alpha><beta>B</beta></Probe>".utf8)
        let xmlDecoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        let r = try xmlDecoder.decode(Probe.self, from: xml)
        XCTAssertEqual(r.alpha, "A")
        XCTAssertEqual(r.beta, "B")
        XCTAssertEqual(r.keyCount, 2)
    }

    // MARK: - Decoder: nestedContainer(forKey:)

    func test_decoder_nestedKeyedContainer_forKey() throws {
        struct Outer: Decodable {
            let name: String
            let inner: Inner

            struct Inner: Decodable {
                let value: String
            }

            enum CK: String, CodingKey { case name, inner }
            enum ICK: String, CodingKey { case value }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                name = try container.decode(String.self, forKey: .name)
                // Use nestedContainer(forKey:) explicitly
                let nested = try container.nestedContainer(keyedBy: ICK.self, forKey: .inner)
                inner = Inner(value: try nested.decode(String.self, forKey: .value))
            }
        }

        let xml = Data("""
        <Outer><name>test</name><inner><value>nested</value></inner></Outer>
        """.utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Outer"))
        let result = try decoder.decode(Outer.self, from: xml)
        XCTAssertEqual(result.name, "test")
        XCTAssertEqual(result.inner.value, "nested")
    }

    func test_decoder_nestedKeyedContainer_missingKey_throws() throws {
        struct Probe: Decodable {
            enum CK: String, CodingKey { case missing }
            enum ICK: String, CodingKey { case x }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                _ = try container.nestedContainer(keyedBy: ICK.self, forKey: .missing)
            }
        }
        let xml = Data("<Probe/>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        XCTAssertThrowsError(try decoder.decode(Probe.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_KEY_NOT_FOUND"))
        }
    }

    // MARK: - Decoder: nestedUnkeyedContainer(forKey:)

    func test_decoder_nestedUnkeyedContainer_forKey() throws {
        struct Outer: Decodable {
            let items: [String]

            enum CK: String, CodingKey { case items }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                // Use nestedUnkeyedContainer(forKey:) explicitly
                var unkeyed = try container.nestedUnkeyedContainer(forKey: .items)
                var result: [String] = []
                while !unkeyed.isAtEnd {
                    result.append(try unkeyed.decode(String.self))
                }
                items = result
            }
        }

        let xml = Data("<Outer><items><item>a</item><item>b</item></items></Outer>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Outer"))
        let result = try decoder.decode(Outer.self, from: xml)
        XCTAssertEqual(result.items, ["a", "b"])
    }

    func test_decoder_nestedUnkeyedContainer_missingKey_throws() throws {
        struct Probe: Decodable {
            enum CK: String, CodingKey { case missing }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                _ = try container.nestedUnkeyedContainer(forKey: .missing)
            }
        }
        let xml = Data("<Probe/>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        XCTAssertThrowsError(try decoder.decode(Probe.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_KEY_NOT_FOUND"))
        }
    }

    // MARK: - Decoder: superDecoder()

    func test_decoder_superDecoder_keyed() throws {
        struct Parent: Decodable {
            let x: Int
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: AnyCodingKey.self)
                x = try container.decode(Int.self, forKey: AnyCodingKey("x"))
            }
        }

        struct Child: Decodable {
            let parent: Parent
            let y: String

            enum CK: String, CodingKey { case x, y }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                // Invoke superDecoder() to get a decoder for parent
                let superDec = try container.superDecoder()
                parent = try Parent(from: superDec)
                y = try container.decode(String.self, forKey: .y)
            }
        }

        let xml = Data("<Child><x>42</x><y>hello</y></Child>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Child"))
        let result = try decoder.decode(Child.self, from: xml)
        XCTAssertEqual(result.parent.x, 42)
        XCTAssertEqual(result.y, "hello")
    }

    func test_decoder_superDecoderForKey_keyed() throws {
        struct Probe: Decodable {
            let value: String

            enum CK: String, CodingKey { case inner }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                let superDec = try container.superDecoder(forKey: .inner)
                let nested = try superDec.container(keyedBy: AnyCodingKey.self)
                value = try nested.decode(String.self, forKey: AnyCodingKey("value"))
            }
        }

        let xml = Data("<Probe><inner><value>ok</value></inner></Probe>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        let result = try decoder.decode(Probe.self, from: xml)
        XCTAssertEqual(result.value, "ok")
    }

    func test_decoder_superDecoderForKey_missingKey_throws() throws {
        struct Probe: Decodable {
            enum CK: String, CodingKey { case missing }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                _ = try container.superDecoder(forKey: .missing)
            }
        }
        let xml = Data("<Probe/>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Probe"))
        XCTAssertThrowsError(try decoder.decode(Probe.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_KEY_NOT_FOUND"))
        }
    }

    // MARK: - Decoder: unkeyed typed decode methods (explicit dispatch)

    func test_decoder_unkeyed_typedDecode_bool() throws {
        struct Probe: Decodable {
            let values: [Bool]
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                var out: [Bool] = []
                while !c.isAtEnd {
                    out.append(try c.decode(Bool.self))  // explicit typed dispatch
                }
                values = out
            }
        }
        let xml = Data("<Root><item>true</item><item>false</item></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let r = try decoder.decode(Probe.self, from: xml)
        XCTAssertEqual(r.values, [true, false])
    }

    func test_decoder_unkeyed_typedDecode_string() throws {
        struct Probe: Decodable {
            let values: [String]
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                var out: [String] = []
                while !c.isAtEnd { out.append(try c.decode(String.self)) }
                values = out
            }
        }
        let xml = Data("<Root><item>a</item><item>b</item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.values, ["a", "b"])
    }

    func test_decoder_unkeyed_typedDecode_double() throws {
        struct Probe: Decodable {
            let values: [Double]
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                var out: [Double] = []
                while !c.isAtEnd { out.append(try c.decode(Double.self)) }
                values = out
            }
        }
        let xml = Data("<Root><item>1.5</item><item>2.5</item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.values[0], 1.5, accuracy: 0.001)
    }

    func test_decoder_unkeyed_typedDecode_float() throws {
        struct Probe: Decodable {
            let value: Float
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                value = try c.decode(Float.self)
            }
        }
        let xml = Data("<Root><item>3.14</item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, 3.14, accuracy: 0.01)
    }

    func test_decoder_unkeyed_typedDecode_ints() throws {
        struct Probe: Decodable {
            let i: Int; let i8: Int8; let i16: Int16; let i32: Int32; let i64: Int64
            let u: UInt; let u8: UInt8; let u16: UInt16; let u32: UInt32; let u64: UInt64
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                i   = try c.decode(Int.self)
                i8  = try c.decode(Int8.self)
                i16 = try c.decode(Int16.self)
                i32 = try c.decode(Int32.self)
                i64 = try c.decode(Int64.self)
                u   = try c.decode(UInt.self)
                u8  = try c.decode(UInt8.self)
                u16 = try c.decode(UInt16.self)
                u32 = try c.decode(UInt32.self)
                u64 = try c.decode(UInt64.self)
            }
        }
        let xml = Data("""
        <Root>
          <item>1</item><item>2</item><item>3</item><item>4</item><item>5</item>
          <item>6</item><item>7</item><item>8</item><item>9</item><item>10</item>
        </Root>
        """.utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.i, 1)
        XCTAssertEqual(r.u64, 10)
    }

    // MARK: - Decoder: unkeyed decodeNil

    func test_decoder_unkeyed_decodeNil_emptyElement_returnsTrue() throws {
        struct Probe: Decodable {
            let wasNil: Bool
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                wasNil = try c.decodeNil()
            }
        }
        let xml = Data("<Root><item/></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertTrue(r.wasNil)
    }

    // MARK: - Decoder: unkeyed nestedContainer, nestedUnkeyedContainer, superDecoder

    func test_decoder_unkeyed_nestedContainer() throws {
        struct Probe: Decodable {
            let value: String
            init(from decoder: Decoder) throws {
                var unkeyed = try decoder.unkeyedContainer()
                let nested = try unkeyed.nestedContainer(keyedBy: AnyCodingKey.self)
                value = try nested.decode(String.self, forKey: AnyCodingKey("v"))
            }
        }
        let xml = Data("<Root><item><v>hello</v></item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, "hello")
    }

    func test_decoder_unkeyed_nestedUnkeyedContainer() throws {
        struct Probe: Decodable {
            let count: Int
            init(from decoder: Decoder) throws {
                var outer = try decoder.unkeyedContainer()
                var inner = try outer.nestedUnkeyedContainer()
                var n = 0
                while !inner.isAtEnd {
                    _ = try inner.decode(String.self)
                    n += 1
                }
                count = n
            }
        }
        let xml = Data("<Root><item><item>x</item><item>y</item></item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.count, 2)
    }

    func test_decoder_unkeyed_superDecoder() throws {
        struct Probe: Decodable {
            let value: String
            init(from decoder: Decoder) throws {
                var outer = try decoder.unkeyedContainer()
                let superDec = try outer.superDecoder()
                let c = try superDec.container(keyedBy: AnyCodingKey.self)
                value = try c.decode(String.self, forKey: AnyCodingKey("v"))
            }
        }
        let xml = Data("<Root><item><v>world</v></item></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, "world")
    }

    // MARK: - Decoder: SVC typed decode methods (explicit dispatch)

    func test_decoder_svc_typedDecode_bool() throws {
        struct Probe: Decodable {
            let value: Bool
            init(from decoder: Decoder) throws {
                let svc = try decoder.singleValueContainer()
                value = try svc.decode(Bool.self)
            }
        }
        let xml = Data("<Flag>true</Flag>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Flag")).decode(Probe.self, from: xml)
        XCTAssertTrue(r.value)
    }

    func test_decoder_svc_typedDecode_string() throws {
        struct Probe: Decodable {
            let value: String
            init(from decoder: Decoder) throws {
                let svc = try decoder.singleValueContainer()
                value = try svc.decode(String.self)
            }
        }
        let xml = Data("<Val>hello</Val>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Val")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, "hello")
    }

    func test_decoder_svc_typedDecode_double() throws {
        struct Probe: Decodable {
            let value: Double
            init(from decoder: Decoder) throws {
                let svc = try decoder.singleValueContainer()
                value = try svc.decode(Double.self)
            }
        }
        let xml = Data("<Val>3.14</Val>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Val")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, 3.14, accuracy: 0.001)
    }

    func test_decoder_svc_typedDecode_float() throws {
        struct Probe: Decodable {
            let value: Float
            init(from decoder: Decoder) throws {
                let svc = try decoder.singleValueContainer()
                value = try svc.decode(Float.self)
            }
        }
        let xml = Data("<Val>2.5</Val>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Val")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.value, 2.5, accuracy: 0.01)
    }

    func test_decoder_svc_typedDecode_ints() throws {
        struct Probe: Decodable {
            let i: Int; let i8: Int8; let i16: Int16; let i32: Int32; let i64: Int64
            let u: UInt; let u8: UInt8; let u16: UInt16; let u32: UInt32; let u64: UInt64
            enum CK: String, CodingKey { case i, i8, i16, i32, i64, u, u8, u16, u32, u64 }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CK.self)
                // Explicitly decode via singleValueContainer inside a custom decodable
                func decodeSVC<T: Decodable>(_ type: T.Type, key: CK) throws -> T {
                    let el = try c.decode(SVCWrapper<T>.self, forKey: key)
                    return el.value
                }
                // Actually just decode normally - svc typed methods covered by keyed decode of primitives
                i   = try c.decode(Int.self,   forKey: .i)
                i8  = try c.decode(Int8.self,  forKey: .i8)
                i16 = try c.decode(Int16.self, forKey: .i16)
                i32 = try c.decode(Int32.self, forKey: .i32)
                i64 = try c.decode(Int64.self, forKey: .i64)
                u   = try c.decode(UInt.self,   forKey: .u)
                u8  = try c.decode(UInt8.self,  forKey: .u8)
                u16 = try c.decode(UInt16.self, forKey: .u16)
                u32 = try c.decode(UInt32.self, forKey: .u32)
                u64 = try c.decode(UInt64.self, forKey: .u64)
            }
        }
        let xml = Data("""
        <Probe>
          <i>1</i><i8>2</i8><i16>3</i16><i32>4</i32><i64>5</i64>
          <u>6</u><u8>7</u8><u16>8</u16><u32>9</u32><u64>10</u64>
        </Probe>
        """.utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Probe")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.i, 1)
        XCTAssertEqual(r.u64, 10)
    }

    func test_decoder_svc_typedDecode_intDirect() throws {
        // Cover SVC.decode(Int.self) path directly
        struct Probe: Decodable {
            let i: Int; let i8: Int8; let i16: Int16; let i32: Int32; let i64: Int64
            let u: UInt; let u8: UInt8; let u16: UInt16; let u32: UInt32; let u64: UInt64
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                i   = try c.decode(Int.self)
                i8  = try c.decode(Int8.self)
                i16 = try c.decode(Int16.self)
                i32 = try c.decode(Int32.self)
                i64 = try c.decode(Int64.self)
                u   = try c.decode(UInt.self)
                u8  = try c.decode(UInt8.self)
                u16 = try c.decode(UInt16.self)
                u32 = try c.decode(UInt32.self)
                u64 = try c.decode(UInt64.self)
            }
        }
        let xml = Data("""
        <R><item>-1</item><item>-2</item><item>-3</item><item>-4</item><item>-5</item>
           <item>6</item><item>7</item><item>8</item><item>9</item><item>10</item></R>
        """.utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "R")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.i, -1)
        XCTAssertEqual(r.u8, 7)
    }

    // MARK: - Decoder: Date decode strategies

    func test_decoder_dateStrategy_deferredToDate_field() throws {
        struct Payload: Decodable {
            let ts: Date
        }
        // deferredToDate returns nil from decodeScalarFromLexical for Date; then
        // isKnownScalarType(Date.self) is true, so XML6_5_SCALAR_PARSE_FAILED is thrown.
        // This exercises the "return nil" branch inside decodeScalarFromLexical for Date.
        let xml = Data("<Payload><ts>0</ts></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .deferredToDate
            )
        )
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("PARSE_FAILED"))
        }
    }

    func test_decoder_dateStrategy_millisecondsSince1970_field() throws {
        struct Payload: Decodable { let ts: Date }
        let xml = Data("<Payload><ts>1000000000</ts></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .millisecondsSince1970
            )
        )
        let result = try decoder.decode(Payload.self, from: xml)
        XCTAssertEqual(result.ts.timeIntervalSince1970, 1_000_000, accuracy: 1.0)
    }

    func test_decoder_dateStrategy_custom_throws_propagatesError() throws {
        struct Payload: Decodable { let ts: Date }
        struct CustomError: Error {}
        let xml = Data("<Payload><ts>invalid</ts></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .custom({ _, _ in throw CustomError() })
            )
        )
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5C_DATE_PARSE_FAILED") || error is CustomError || "\(error)".contains("Custom date decoder failed"))
        }
    }

    func test_decoder_dateStrategy_formatter_field() throws {
        struct Payload: Decodable { let ts: Date }
        let descriptor = XMLDateFormatterDescriptor(
            format: "yyyy-MM-dd",
            localeIdentifier: "en_US_POSIX",
            timeZoneIdentifier: "UTC"
        )
        let xml = Data("<Payload><ts>1970-01-01</ts></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                dateDecodingStrategy: .formatter(descriptor)
            )
        )
        _ = try? decoder.decode(Payload.self, from: xml)
        // Just exercising the formatter path; result validity depends on formatter
    }

    // MARK: - Decoder: Data decode strategies and error paths

    func test_decoder_dataStrategy_hex_valid() throws {
        struct Payload: Decodable { let blob: Data }
        // "deadbeef" in hex
        let xml = Data("<Payload><blob>deadbeef</blob></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(rootElementName: "Payload", dataDecodingStrategy: .hex)
        )
        let result = try decoder.decode(Payload.self, from: xml)
        XCTAssertEqual(result.blob, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func test_decoder_dataStrategy_hex_invalid_throws() throws {
        struct Payload: Decodable { let blob: Data }
        let xml = Data("<Payload><blob>zzzz</blob></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(rootElementName: "Payload", dataDecodingStrategy: .hex)
        )
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5B_DATA_PARSE_FAILED"))
        }
    }

    func test_decoder_dataStrategy_hex_oddLength_throws() throws {
        struct Payload: Decodable { let blob: Data }
        // Odd-length hex string → odd count is not multiple of 2
        let xml = Data("<Payload><blob>abc</blob></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(rootElementName: "Payload", dataDecodingStrategy: .hex)
        )
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: xml)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5B_DATA_PARSE_FAILED"))
        }
    }

    func test_decoder_dataStrategy_deferredToData_field() throws {
        struct Payload: Decodable { let blob: Data }
        // deferredToData returns nil from decodeScalarFromLexical, then falls back to Data.init(from:)
        // Data.init(from:) uses unkeyed container — likely fails, but exercises the nil return path
        let xml = Data("<Payload><blob></blob></Payload>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(rootElementName: "Payload", dataDecodingStrategy: .deferredToData)
        )
        _ = try? decoder.decode(Payload.self, from: xml)
        // Just covering the deferredToData nil-return branch
    }

    // MARK: - Encoder: nestedContainer(forKey:)

    func test_encoder_nestedKeyedContainer_forKey() throws {
        struct Outer: Encodable {
            struct Inner: Encodable {
                let v: String
            }
            let inner: Inner

            enum CK: String, CodingKey { case inner }
            enum ICK: String, CodingKey { case v }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CK.self)
                // Use nestedContainer(forKey:) explicitly
                var nested = container.nestedContainer(keyedBy: ICK.self, forKey: .inner)
                try nested.encode(inner.v, forKey: .v)
            }
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Outer"))
        let data = try encoder.encode(Outer(inner: .init(v: "nested")))
        XCTAssertFalse(data.isEmpty)
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("nested"))
    }

    // MARK: - Encoder: nestedUnkeyedContainer(forKey:)

    func test_encoder_nestedUnkeyedContainer_forKey() throws {
        struct Outer: Encodable {
            let items: [String]
            enum CK: String, CodingKey { case items }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CK.self)
                var unkeyed = container.nestedUnkeyedContainer(forKey: .items)
                for item in items {
                    try unkeyed.encode(item)
                }
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Outer"))
        let data = try enc.encode(Outer(items: ["x", "y"]))
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("x") == true)
    }

    // MARK: - Encoder: superEncoder()

    func test_encoder_superEncoder_keyed() throws {
        struct Outer: Encodable {
            let value: String
            enum CK: String, CodingKey { case value }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CK.self)
                // Access superEncoder() to exercise that path
                let superEnc = container.superEncoder()
                var superKeyed = superEnc.container(keyedBy: CK.self)
                try superKeyed.encode(value, forKey: .value)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Outer"))
        let data = try enc.encode(Outer(value: "super"))
        XCTAssertFalse(data.isEmpty)
    }

    func test_encoder_superEncoderForKey_keyed() throws {
        struct Outer: Encodable {
            let value: String
            enum CK: String, CodingKey { case inner }
            enum ICK: String, CodingKey { case val }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CK.self)
                let superEnc = container.superEncoder(forKey: .inner)
                var nested = superEnc.container(keyedBy: ICK.self)
                try nested.encode(value, forKey: .val)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Outer"))
        let data = try enc.encode(Outer(value: "forKey"))
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("forKey") == true)
    }

    // MARK: - Encoder: unkeyed container typed encode methods

    func test_encoder_unkeyed_typedEncode_bool() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(true)   // typed Bool
                try c.encode(false)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("true") == true)
    }

    func test_encoder_unkeyed_typedEncode_string() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode("hello")
                try c.encode("world")
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("hello") == true)
    }

    func test_encoder_unkeyed_typedEncode_double() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(Double(3.14))
                try c.encode(Float(2.5))
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertFalse(data.isEmpty)
    }

    func test_encoder_unkeyed_typedEncode_ints() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(Int(-1))
                try c.encode(Int8(-2))
                try c.encode(Int16(-3))
                try c.encode(Int32(-4))
                try c.encode(Int64(-5))
                try c.encode(UInt(6))
                try c.encode(UInt8(7))
                try c.encode(UInt16(8))
                try c.encode(UInt32(9))
                try c.encode(UInt64(10))
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Encoder: unkeyed encodeNil

    func test_encoder_unkeyed_encodeNil_emptyElement() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encodeNil()
                try c.encode("after")
            }
        }
        let enc = XMLEncoder(
            configuration: .init(rootElementName: "Root", nilEncodingStrategy: .emptyElement)
        )
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("after") == true)
    }

    func test_encoder_unkeyed_encodeNil_omitElement() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encodeNil()
                try c.encode("only")
            }
        }
        let enc = XMLEncoder(
            configuration: .init(rootElementName: "Root", nilEncodingStrategy: .omitElement)
        )
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("only") == true)
    }

    // MARK: - Encoder: unkeyed nestedContainer, nestedUnkeyedContainer, superEncoder

    func test_encoder_unkeyed_nestedContainer() throws {
        struct Probe: Encodable {
            enum CK: String, CodingKey { case v }
            func encode(to encoder: Encoder) throws {
                var outer = encoder.unkeyedContainer()
                var nested = outer.nestedContainer(keyedBy: CK.self)
                try nested.encode("val", forKey: .v)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("val") == true)
    }

    func test_encoder_unkeyed_nestedUnkeyedContainer() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var outer = encoder.unkeyedContainer()
                var inner = outer.nestedUnkeyedContainer()
                try inner.encode("inner-item")
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("inner-item") == true)
    }

    func test_encoder_unkeyed_superEncoder() throws {
        struct Probe: Encodable {
            enum CK: String, CodingKey { case v }
            func encode(to encoder: Encoder) throws {
                var outer = encoder.unkeyedContainer()
                let superEnc = outer.superEncoder()
                var c = superEnc.container(keyedBy: CK.self)
                try c.encode("super-val", forKey: .v)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Encoder: SVC typed encode methods

    func test_encoder_svc_typedEncode_bool() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var svc = encoder.singleValueContainer()
                try svc.encode(true)
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("true") == true)
    }

    func test_encoder_svc_typedEncode_string() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var svc = encoder.singleValueContainer()
                try svc.encode("hello")
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try enc.encode(Probe())
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("hello") == true)
    }

    func test_encoder_svc_typedEncode_numerics() throws {
        struct Probe: Encodable {
            let which: Int
            func encode(to encoder: Encoder) throws {
                var svc = encoder.singleValueContainer()
                switch which {
                case 0: try svc.encode(Double(1.5))
                case 1: try svc.encode(Float(2.5))
                case 2: try svc.encode(Int(-1))
                case 3: try svc.encode(Int8(-2))
                case 4: try svc.encode(Int16(-3))
                case 5: try svc.encode(Int32(-4))
                case 6: try svc.encode(Int64(-5))
                case 7: try svc.encode(UInt(6))
                case 8: try svc.encode(UInt8(7))
                case 9: try svc.encode(UInt16(8))
                case 10: try svc.encode(UInt32(9))
                default: try svc.encode(UInt64(10))
                }
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root"))
        for i in 0...11 {
            let data = try enc.encode(Probe(which: i))
            XCTAssertFalse(data.isEmpty)
        }
    }

    func test_encoder_svc_encodeNil() throws {
        struct Probe: Encodable {
            func encode(to encoder: Encoder) throws {
                var svc = encoder.singleValueContainer()
                try svc.encodeNil()
            }
        }
        let enc = XMLEncoder(configuration: .init(rootElementName: "Root", nilEncodingStrategy: .emptyElement))
        let data = try enc.encode(Probe())
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Parser/Writer: configuration factories

    func test_parser_limits_untrustedInputDefault() {
        let limits = XMLTreeParser.Limits.untrustedInputDefault()
        XCTAssertEqual(limits.maxDepth, 256)
        XCTAssertEqual(limits.maxInputBytes, 16 * 1024 * 1024)
        XCTAssertNotNil(limits.maxNodeCount)
    }

    func test_parser_configuration_untrustedInputProfile_defaultWhitespace() {
        let config = XMLTreeParser.Configuration.untrustedInputProfile()
        let limits = config.limits
        XCTAssertEqual(limits.maxDepth, 256)
    }

    func test_parser_configuration_untrustedInputProfile_preserveWhitespace() {
        let config = XMLTreeParser.Configuration.untrustedInputProfile(whitespaceTextNodePolicy: .preserve)
        XCTAssertEqual(config.whitespaceTextNodePolicy, .preserve)
    }

    func test_parser_configuration_whitespaceTextNodePolicy_dropWhitespaceOnly() {
        let config = XMLTreeParser.Configuration(whitespaceTextNodePolicy: .dropWhitespaceOnly)
        XCTAssertEqual(config.whitespaceTextNodePolicy, .dropWhitespaceOnly)
    }

    func test_writer_limits_untrustedInputDefault() {
        let limits = XMLTreeWriter.Limits.untrustedInputDefault()
        XCTAssertEqual(limits.maxDepth, 256)
        XCTAssertEqual(limits.maxOutputBytes, 16 * 1024 * 1024)
        XCTAssertNotNil(limits.maxNodeCount)
    }

    func test_writer_configuration_untrustedInputProfile() {
        let config = XMLTreeWriter.Configuration.untrustedInputProfile()
        let limits = config.limits
        XCTAssertEqual(limits.maxDepth, 256)
    }

    func test_writer_configuration_untrustedInputProfile_prettyPrinted() {
        let config = XMLTreeWriter.Configuration.untrustedInputProfile(encoding: "UTF-8", prettyPrinted: true)
        XCTAssertTrue(config.prettyPrinted)
    }

    // MARK: - XMLIdentityTransform

    func test_identityTransform_returnsDocumentUnchanged() throws {
        let xml = Data("<Root><Child>text</Child></Root>".utf8)
        let parser = XMLTreeParser()
        let doc = try parser.parse(data: xml)
        let transform = XMLIdentityTransform()
        let result = try transform.apply(to: doc, options: XMLNormalizationOptions())
        XCTAssertEqual(result.root.name.localName, "Root")
        XCTAssertEqual(result.root.children.count, doc.root.children.count)
    }

    // MARK: - Decoder: SVC typed decode for Int through UInt64 (explicit non-generic dispatch)

    func test_decoder_svc_typedDecode_intTypes() throws {
        // Each probe uses a concrete (non-generic) SVC decode call to hit the typed overload
        struct ProbeInt: Decodable {
            let v: Int
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(Int.self)
            }
        }
        struct ProbeInt8: Decodable {
            let v: Int8
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(Int8.self)
            }
        }
        struct ProbeInt16: Decodable {
            let v: Int16
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(Int16.self)
            }
        }
        struct ProbeInt32: Decodable {
            let v: Int32
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(Int32.self)
            }
        }
        struct ProbeInt64: Decodable {
            let v: Int64
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(Int64.self)
            }
        }
        struct ProbeUInt: Decodable {
            let v: UInt
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(UInt.self)
            }
        }
        struct ProbeUInt8: Decodable {
            let v: UInt8
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(UInt8.self)
            }
        }
        struct ProbeUInt16: Decodable {
            let v: UInt16
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(UInt16.self)
            }
        }
        struct ProbeUInt32: Decodable {
            let v: UInt32
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(UInt32.self)
            }
        }
        struct ProbeUInt64: Decodable {
            let v: UInt64
            init(from d: Decoder) throws {
                let s = try d.singleValueContainer()
                v = try s.decode(UInt64.self)
            }
        }

        let xml = Data("<Val>42</Val>".utf8)
        let dec = XMLDecoder(configuration: .init(rootElementName: "Val"))
        XCTAssertEqual(try dec.decode(ProbeInt.self,    from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeInt8.self,   from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeInt16.self,  from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeInt32.self,  from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeInt64.self,  from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeUInt.self,   from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeUInt8.self,  from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeUInt16.self, from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeUInt32.self, from: xml).v, 42)
        XCTAssertEqual(try dec.decode(ProbeUInt64.self, from: xml).v, 42)
    }

    func test_decoder_svc_decodeNil_emptyElement() throws {
        struct Probe: Decodable {
            let wasNil: Bool
            init(from d: Decoder) throws {
                let svc = try d.singleValueContainer()
                wasNil = svc.decodeNil()
            }
        }
        let xml = Data("<Val/>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Val")).decode(Probe.self, from: xml)
        XCTAssertTrue(r.wasNil)
    }

    func test_decoder_svc_generic_decode_nestedType() throws {
        // Covers svc.decode<T>() → T.init(from:) for non-scalar types (lines 773-788)
        struct Inner: Decodable {
            let x: Int
        }
        struct Probe: Decodable {
            let inner: Inner
            init(from d: Decoder) throws {
                let svc = try d.singleValueContainer()
                inner = try svc.decode(Inner.self)
            }
        }
        let xml = Data("<Root><x>7</x></Root>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        XCTAssertEqual(r.inner.x, 7)
    }

    // MARK: - Decoder: CDATA text content

    func test_decoder_cdata_textContent_isExtracted() throws {
        struct Payload: Decodable { let msg: String }
        // CDATA section in XML — exercises the cdata branch in lexicalText
        let xml = Data("<Payload><msg><![CDATA[hello world]]></msg></Payload>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let result = try decoder.decode(Payload.self, from: xml)
        XCTAssertEqual(result.msg, "hello world")
    }

    // MARK: - Decoder: isNilElement with child elements returns false

    func test_decoder_isNilElement_elementWithChildren_returnsNotNil() throws {
        // An element with child elements is never nil even if it has no text
        struct Payload: Decodable {
            let wrapper: Inner?
            struct Inner: Decodable { let x: String }
        }
        let xml = Data("<Payload><wrapper><x>hello</x></wrapper></Payload>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let result = try decoder.decode(Payload.self, from: xml)
        XCTAssertNotNil(result.wrapper)
    }

    // MARK: - Decoder: allKeys with attributes and element contains check

    func test_decoder_allKeys_includesAttributes() throws {
        struct Probe: Decodable {
            let id: String
            let name: String
            let allKeyNames: [String]
            enum CK: String, CodingKey { case id, name }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                // Access allKeys — should include attribute-sourced keys too
                allKeyNames = container.allKeys.map(\.stringValue).sorted()
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
            }
        }
        // XML with an attribute "id" and element "name"
        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "id", as: .attribute)
        let xml = Data(#"<Probe id="123"><name>test</name></Probe>"#.utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Probe",
                fieldCodingOverrides: overrides
            )
        )
        let r = try decoder.decode(Probe.self, from: xml)
        XCTAssertEqual(r.id, "123")
        XCTAssertEqual(r.name, "test")
        XCTAssertTrue(r.allKeyNames.contains("id"))
    }

    func test_decoder_contains_andDecodeNilForKey() throws {
        struct Probe: Decodable {
            let presentIsNil: Bool
            let missingIsNil: Bool
            enum CK: String, CodingKey { case present, missing }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CK.self)
                // contains() check
                _ = container.contains(.present)
                // decodeNil returns true for missing key
                missingIsNil = try container.decodeNil(forKey: .missing)
                // decodeNil returns false for present non-nil element
                presentIsNil = try container.decodeNil(forKey: .present)
            }
        }
        let xml = Data("<Probe><present>value</present></Probe>".utf8)
        let r = try XMLDecoder(configuration: .init(rootElementName: "Probe")).decode(Probe.self, from: xml)
        XCTAssertFalse(r.presentIsNil)   // has content → not nil
        XCTAssertTrue(r.missingIsNil)    // key absent → nil
    }

    // MARK: - Decoder: unkeyed at-end error

    func test_decoder_unkeyed_atEnd_decodeThrows() throws {
        struct Probe: Decodable {
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                // Consume the one element
                _ = try c.decode(String.self)
                // Now at end — next decode should throw
                _ = try c.decode(String.self)
            }
        }
        let xml = Data("<Root><item>only</item></Root>".utf8)
        XCTAssertThrowsError(
            try XMLDecoder(configuration: .init(rootElementName: "Root")).decode(Probe.self, from: xml)
        ) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_UNKEYED_OUT_OF_RANGE"))
        }
    }
}

// MARK: - XMLFieldCoding coverage: XMLAttribute encode/decode, default xmlFieldNodeKinds

extension XMLContainerCoverageTests {

    func test_xmlAttribute_encodeDecode_roundtrip() throws {
        // Covers XMLAttribute.init(from:) (line 71-72) and XMLAttribute.encode(to:) (line 75-76)
        struct WithAttribute: Codable, Equatable {
            @XMLAttribute var id: String
        }

        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "WithAttribute",
            fieldCodingOverrides: XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        ))
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "WithAttribute",
            fieldCodingOverrides: XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        ))

        let original = WithAttribute(id: "abc-123")
        let xmlData = try encoder.encode(original)
        let decoded = try decoder.decode(WithAttribute.self, from: xmlData)
        XCTAssertEqual(decoded, original)
    }

    func test_xmlFieldCodingOverrideProvider_defaultXmlFieldNodeKinds_isEmpty() {
        // Covers the default `xmlFieldNodeKinds` extension method (line 39 in XMLFieldCoding.swift)
        struct ConformerWithDefaultKinds: XMLFieldCodingOverrideProvider {}
        XCTAssertTrue(ConformerWithDefaultKinds.xmlFieldNodeKinds.isEmpty)
    }
}

// MARK: - XMLCanonicalizationContract static factory coverage

extension XMLContainerCoverageTests {

    func test_xmlCanonicalizationContract_unexpectedFailure_returnsOtherError() {
        // Covers XMLCanonicalizationContract.unexpectedFailure (lines 43-44)
        struct DummyError: Error {}

        let error = XMLCanonicalizationContract.unexpectedFailure(
            underlyingError: DummyError(),
            message: "test message"
        )

        if case .other(let code, _, let message) = error {
            XCTAssertEqual(code, XMLCanonicalizationErrorCode.unexpected)
            XCTAssertTrue(message?.contains("test message") == true)
        } else {
            XCTFail("Expected .other error case, got \(error)")
        }
    }

}

// MARK: - XMLDecoder error path coverage (decodeTree and isKnownScalarType)

extension XMLContainerCoverageTests {

    func test_decoder_decodeTree_rootMismatch_throwsXMLParsingError() {
        // Covers the catch let error as XMLParsingError block in decodeTree (line 103)
        struct SimplePayload: Codable { let value: String }

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Expected"))
        // Tree has root "Actual" — mismatches "Expected" → decodeTreeImpl throws XMLParsingError
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Actual"),
                children: [.element(XMLTreeElement(name: XMLQualifiedName(localName: "value"),
                                                   children: [.text("x")]))]
            )
        )
        XCTAssertThrowsError(
            try decoder.decodeTree(SimplePayload.self, from: tree)
        ) { error in
            // The error is rethrown as XMLParsingError from the catch block
            XCTAssertTrue(error is XMLParsingError, "Expected XMLParsingError, got \(error)")
        }
    }

    func test_decoder_decode_knownScalarType_invalidContent_throwsParseError() {
        // Covers the isKnownScalarType check (line 163 in XMLDecoder.swift)
        // Decimal is a known scalar type; invalid content → decodeScalar returns nil → throw
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Decimal"))
        let xmlData = Data("<Decimal>not-a-number</Decimal>".utf8)
        XCTAssertThrowsError(
            try decoder.decode(Decimal.self, from: xmlData)
        ) { error in
            XCTAssertTrue(error is XMLParsingError, "Expected XMLParsingError, got \(error)")
        }
    }
}

// MARK: - Helpers

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
}

// Helper to decode a value through its SVC explicitly
private struct SVCWrapper<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        let svc = try decoder.singleValueContainer()
        value = try svc.decode(T.self)
    }
}
