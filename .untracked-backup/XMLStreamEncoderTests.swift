import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamEncoderTests: XCTestCase {

    // MARK: - Fixtures

    private struct Simple: Codable, Equatable {
        var name: String
        var value: Int
    }

    private struct Nested: Codable, Equatable {
        var title: String
        var child: Simple
    }

    private struct WithArray: Codable, Equatable {
        var items: [String]
    }

    // MARK: - Document envelope

    func test_encode_firstEventIsStartDocument() throws {
        let encoder = XMLStreamEncoder()
        let events = try encoder.encode(Simple(name: "A", value: 1))
        XCTAssertEqual(events.first, .startDocument(version: nil, encoding: nil, standalone: nil))
    }

    func test_encode_lastEventIsEndDocument() throws {
        let encoder = XMLStreamEncoder()
        let events = try encoder.encode(Simple(name: "A", value: 1))
        XCTAssertEqual(events.last, .endDocument)
    }

    // MARK: - Simple struct

    func test_encode_simpleStruct_containsExpectedElementNames() throws {
        let encoder = XMLStreamEncoder()
        let events = try encoder.encode(Simple(name: "hello", value: 42))

        let elementNames = events.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertTrue(elementNames.contains("Simple"))
        XCTAssertTrue(elementNames.contains("name"))
        XCTAssertTrue(elementNames.contains("value"))
    }

    func test_encode_simpleStruct_textContentsPresent() throws {
        let encoder = XMLStreamEncoder()
        let events = try encoder.encode(Simple(name: "hello", value: 42))

        let texts = events.compactMap { (e: XMLStreamEvent) -> String? in
            if case .text(let s) = e { return s }; return nil
        }
        XCTAssertTrue(texts.contains("hello"))
        XCTAssertTrue(texts.contains("42"))
    }

    // MARK: - Nested struct

    func test_encode_nestedStruct_emitsNestedElements() throws {
        let encoder = XMLStreamEncoder()
        let value = Nested(title: "top", child: Simple(name: "inner", value: 99))
        let events = try encoder.encode(value)

        let elementNames = events.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertTrue(elementNames.contains("title"))
        XCTAssertTrue(elementNames.contains("child"))
        XCTAssertTrue(elementNames.contains("name"))
        XCTAssertTrue(elementNames.contains("value"))
    }

    // MARK: - Array field

    func test_encode_arrayField_emitsItemElements() throws {
        let encoder = XMLStreamEncoder()
        let value = WithArray(items: ["a", "b", "c"])
        let events = try encoder.encode(value)

        let itemStarts = events.filter { (e: XMLStreamEvent) -> Bool in
            if case .startElement(let n, _, _) = e { return n.localName == "item" }; return false
        }
        XCTAssertEqual(itemStarts.count, 3)
    }

    // MARK: - CDATA strategy

    func test_encode_cdataStrategy_emitsCDATAEvents() throws {
        var config = XMLEncoder.Configuration()
        config = XMLEncoder.Configuration(
            stringEncodingStrategy: .cdata
        )
        let encoder = XMLStreamEncoder(configuration: config)
        let events = try encoder.encode(Simple(name: "hello", value: 1))

        let cdataValues = events.compactMap { (e: XMLStreamEvent) -> String? in
            if case .cdata(let s) = e { return s }; return nil
        }
        XCTAssertTrue(cdataValues.contains("hello"), "Expected CDATA event for String field")
    }

    // MARK: - startElement / endElement symmetry

    func test_encode_startEndElementBalanced() throws {
        let encoder = XMLStreamEncoder()
        let value = Nested(title: "top", child: Simple(name: "inner", value: 1))
        let events = try encoder.encode(value)

        let starts = events.filter { if case .startElement = $0 { return true }; return false }.count
        let ends   = events.filter { if case .endElement   = $0 { return true }; return false }.count
        XCTAssertEqual(starts, ends)
    }

    // MARK: - Round-trip via XMLStreamWriter + XMLDecoder

    func test_encode_roundTrip_viaWriterAndDecoder() throws {
        let original = Simple(name: "roundtrip", value: 7)
        let events = try XMLStreamEncoder().encode(original)
        let data   = try XMLStreamWriter().write(events)
        let decoded = try XMLDecoder().decode(Simple.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - encodeAsync

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeAsync_emitsSameEventsAsSync() async throws {
        let encoder = XMLStreamEncoder()
        let value = Simple(name: "async", value: 5)

        let syncEvents = try encoder.encode(value)

        var asyncEvents: [XMLStreamEvent] = []
        for try await event in encoder.encodeAsync(value) {
            asyncEvents.append(event)
        }

        XCTAssertEqual(syncEvents, asyncEvents)
    }
}
