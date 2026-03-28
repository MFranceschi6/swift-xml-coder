import Foundation
import SwiftXMLCoder
import XCTest

// MARK: - Event encoder correctness tests
//
// These tests verify that `XMLEncoder.encode(_:)` (which uses `_XMLEventEncoder` internally)
// produces structurally correct XML for a variety of model shapes.  Round-trip tests
// (encode → decode → compare) are the primary correctness signal; structural tests verify
// specific XML features (attributes, CDATA, nil encoding, namespaces).

// MARK: - Top-level model fixtures (must be at file scope for extension support)

private struct DocWithXMLRoot: Codable, Equatable {
    var title: String
    var count: Int
}
extension DocWithXMLRoot: XMLRootNode {
    static var xmlRootElementName: String { "document" }
}

// MARK: - Tests

final class XMLEncoderEventTests: XCTestCase {

    // MARK: - Helpers

    private func encode<T: Encodable>(
        _ value: T,
        configuration: XMLEncoder.Configuration = .init()
    ) throws -> Data {
        try XMLEncoder(configuration: configuration).encode(value)
    }

    private func roundTrip<T: Codable & Equatable>(
        _ value: T,
        configuration: XMLEncoder.Configuration = .init()
    ) throws -> T {
        let data = try encode(value, configuration: configuration)
        return try XMLDecoder().decode(T.self, from: data)
    }

    // MARK: - Scalar roots

    func test_encode_stringRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "root")
        XCTAssertEqual(try roundTrip("hello", configuration: config), "hello")
    }

    func test_encode_intRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "value")
        XCTAssertEqual(try roundTrip(42, configuration: config), 42)
    }

    func test_encode_boolRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "flag")
        XCTAssertEqual(try roundTrip(true, configuration: config), true)
    }

    func test_encode_doubleRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "num")
        XCTAssertEqual(try roundTrip(3.14, configuration: config), 3.14)
    }

    // MARK: - Flat struct

    func test_encode_flatStruct_roundTrips() throws {
        struct Flat: Codable, Equatable { let id: Int; let name: String; let active: Bool }
        let original = Flat(id: 1, name: "widget", active: true)
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "flat")),
            original
        )
    }

    func test_encode_flatStruct_producesExpectedElements() throws {
        struct Flat: Codable { let id: Int; let name: String }
        let data = try encode(Flat(id: 7, name: "hello"), configuration: .init(rootElementName: "flat"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<id>7</id>"), "Expected <id>7</id> in \(xml)")
        XCTAssert(xml.contains("<name>hello</name>"), "Expected <name>hello</name> in \(xml)")
    }

    // MARK: - Nested struct

    func test_encode_nestedStruct_roundTrips() throws {
        struct Inner: Codable, Equatable { let x: Int; let y: String }
        struct Outer: Codable, Equatable { let id: Int; let inner: Inner }
        let original = Outer(id: 7, inner: Inner(x: 3, y: "hi"))
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "outer")),
            original
        )
    }

    func test_encode_deepNesting_roundTrips() throws {
        struct L3: Codable, Equatable { let v: String }
        struct L2: Codable, Equatable { let l3: L3; let tag: Int }
        struct L1: Codable, Equatable { let l2: L2; let name: String }
        let original = L1(l2: L2(l3: L3(v: "deep"), tag: 99), name: "top")
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "l1")),
            original
        )
    }

    // MARK: - Arrays / unkeyed containers

    func test_encode_array_roundTrips() throws {
        struct Coll: Codable, Equatable { let items: [String] }
        let original = Coll(items: ["a", "b", "c"])
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "coll")),
            original
        )
    }

    func test_encode_arrayOfStructs_roundTrips() throws {
        struct Tag: Codable, Equatable { let label: String }
        struct Post: Codable, Equatable { let title: String; let tags: [Tag] }
        let original = Post(title: "Hello", tags: [Tag(label: "swift"), Tag(label: "xml")])
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "post")),
            original
        )
    }

    func test_encode_largeArray_roundTrips() throws {
        struct Row: Codable, Equatable { let id: Int; let value: String }
        struct Table: Codable, Equatable { let rows: [Row] }
        let original = Table(rows: (1...500).map { Row(id: $0, value: "v\($0)") })
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "table")),
            original
        )
    }

    // MARK: - Optionals

    func test_encode_optionalNil_omitStrategy_omitsElement() throws {
        struct Opt: Codable { let name: String? }
        let data = try encode(
            Opt(name: nil),
            configuration: .init(rootElementName: "opt", nilEncodingStrategy: .omitElement)
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(xml.contains("<name>"), "Expected no <name> element with omitElement strategy in \(xml)")
    }

    func test_encode_optionalNil_emptyElement_producesEmptyElement() throws {
        struct Opt: Codable { let name: String? }
        let data = try encode(
            Opt(name: nil),
            configuration: .init(rootElementName: "opt", nilEncodingStrategy: .emptyElement)
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<name"), "Expected <name> element with emptyElement strategy in \(xml)")
    }

    func test_encode_optionalPresent_roundTrips() throws {
        struct Opt: Codable, Equatable { let name: String? }
        let original = Opt(name: "hello")
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "opt")),
            original
        )
    }

    // MARK: - Attributes (via property wrapper)

    func test_encode_xmlAttributeWrapper_emitsAttribute() throws {
        struct Item: Codable {
            @XMLAttribute var id: Int
            var name: String
        }
        let data = try encode(Item(id: 5, name: "widget"), configuration: .init(rootElementName: "item"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("id=\"5\""), "Expected id attribute in \(xml)")
        XCTAssert(xml.contains("<name>widget</name>"), "Expected name element in \(xml)")
    }

    func test_encode_xmlAttributeWrapper_roundTrips() throws {
        struct Item: Codable, Equatable {
            @XMLAttribute var id: Int
            var name: String
        }
        let original = Item(id: 5, name: "widget")
        let rt = try roundTrip(original, configuration: .init(rootElementName: "item"))
        XCTAssertEqual(original.id, rt.id)
        XCTAssertEqual(original.name, rt.name)
    }

    // MARK: - CDATA

    func test_encode_cdataStrategy_producesCDATASection() throws {
        struct Payload: Codable { let html: String }
        let data = try encode(
            Payload(html: "<b>bold</b>"),
            configuration: .init(rootElementName: "payload", stringEncodingStrategy: .cdata)
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("CDATA"), "Expected CDATA section in \(xml)")
    }

    // MARK: - Key transform

    func test_encode_camelCaseToSnakeCase_roundTrips() throws {
        struct Model: Codable, Equatable { let firstName: String; let lastName: String }
        let original = Model(firstName: "John", lastName: "Doe")
        let config = XMLEncoder.Configuration(rootElementName: "model", keyTransformStrategy: .convertToSnakeCase)
        let decoderConfig = XMLDecoder.Configuration(keyTransformStrategy: .convertToSnakeCase)
        let data = try encode(original, configuration: config)
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(Model.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLRootNode conformance

    func test_encode_xmlRootNode_usesStaticRootName() throws {
        let original = DocWithXMLRoot(title: "Hello", count: 42)
        let data = try encode(original)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<document"), "Expected <document> root in \(xml)")
        XCTAssertEqual(try roundTrip(original), original)
    }

    // MARK: - Multiple scalar types

    func test_encode_allScalarTypes_roundTrip() throws {
        struct AllScalars: Codable, Equatable {
            let b: Bool; let i: Int; let i8: Int8; let i16: Int16; let i32: Int32; let i64: Int64
            let u: UInt; let u8: UInt8; let u16: UInt16; let u32: UInt32; let u64: UInt64
            let f: Float; let d: Double; let s: String
        }
        let original = AllScalars(
            b: true, i: -1, i8: -8, i16: -16, i32: -32, i64: -64,
            u: 1, u8: 8, u16: 16, u32: 32, u64: 64,
            f: 1.5, d: 2.5, s: "text"
        )
        XCTAssertEqual(
            try roundTrip(original, configuration: .init(rootElementName: "scalars")),
            original
        )
    }

    // MARK: - Nil in array

    func test_encode_nilInArray_omitStrategy() throws {
        struct WithArray: Codable {
            let values: [String?]
        }
        // encodeIfPresent on array elements: nil items omitted with omitElement
        let data = try encode(
            WithArray(values: ["a", nil, "b"]),
            configuration: .init(rootElementName: "root", nilEncodingStrategy: .omitElement)
        )
        let decoded = try XMLDecoder().decode(WithArray.self, from: data)
        XCTAssertEqual(decoded.values.compactMap { $0 }, ["a", "b"])
    }
}
