import Foundation
import SwiftXMLCoder
import XCTest

// Tests for XMLStreamEventDecoder (II.6) — the event-cursor decoder that replaces
// the buildDocument → XMLTreeDocument → XMLDecoder pipeline in XMLStreamDecoder.
//
// All tests exercise the decoder through the public XMLStreamDecoder API, either
// by constructing event arrays manually or via XMLStreamParser/XMLStreamEncoder.

final class XMLStreamEventDecoderTests: XCTestCase {

    // MARK: - Fixtures

    private struct Simple: Codable, Equatable {
        var name: String
        var value: Int
    }

    private struct Nested: Codable, Equatable {
        var title: String
        var inner: Simple
    }

    private struct WithArray: Codable, Equatable {
        var items: [String]
    }

    private struct WithOptional: Codable, Equatable {
        var name: String
        var note: String?
    }

    private struct WithAttribute: Codable, Equatable {
        var id: XMLAttribute<String>
        var name: String
    }

    private struct WithCDATA: Codable, Equatable {
        var content: String
    }

    private struct Reordered: Codable, Equatable {
        // Declared order: b, a — but XML will have a before b
        var b: String
        var a: String
    }

    // MARK: - Helpers

    private static func se(_ localName: String) -> XMLStreamEvent {
        .startElement(name: XMLQualifiedName(localName: localName), attributes: [], namespaceDeclarations: [])
    }

    private static func ee(_ localName: String) -> XMLStreamEvent {
        .endElement(name: XMLQualifiedName(localName: localName))
    }

    // MARK: - 1. Simple struct from manually built events

    func test_decode_simpleStruct_fromEvents() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            Self.se("Simple"),
            Self.se("name"), .text("hello"), Self.ee("name"),
            Self.se("value"), .text("42"), Self.ee("value"),
            Self.ee("Simple"),
            .endDocument
        ]
        let decoded = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(decoded, Simple(name: "hello", value: 42))
    }

    // MARK: - 2. Nested struct

    func test_decode_nestedStruct() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            Self.se("Nested"),
            Self.se("title"), .text("test"), Self.ee("title"),
            Self.se("inner"),
            Self.se("name"), .text("inner-name"), Self.ee("name"),
            Self.se("value"), .text("7"), Self.ee("value"),
            Self.ee("inner"),
            Self.ee("Nested"),
            .endDocument
        ]
        let decoded = try XMLStreamDecoder().decode(Nested.self, from: events)
        XCTAssertEqual(decoded, Nested(title: "test", inner: Simple(name: "inner-name", value: 7)))
    }

    // MARK: - 3. Array field

    func test_decode_arrayField() throws {
        let xml = "<WithArray><items><item>a</item><item>b</item><item>c</item></items></WithArray>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let decoded = try XMLStreamDecoder().decode(WithArray.self, from: events)
        XCTAssertEqual(decoded.items, ["a", "b", "c"])
    }

    // MARK: - 4. Optional absent → nil

    func test_decode_optionalAbsent() throws {
        let events: [XMLStreamEvent] = [
            Self.se("WithOptional"),
            Self.se("name"), .text("Alice"), Self.ee("name"),
            // no <note> element
            Self.ee("WithOptional")
        ]
        let decoded = try XMLStreamDecoder().decode(WithOptional.self, from: events)
        XCTAssertEqual(decoded, WithOptional(name: "Alice", note: nil))
    }

    // MARK: - 5. Optional present → value

    func test_decode_optionalPresent() throws {
        let events: [XMLStreamEvent] = [
            Self.se("WithOptional"),
            Self.se("name"), .text("Bob"), Self.ee("name"),
            Self.se("note"), .text("a note"), Self.ee("note"),
            Self.ee("WithOptional")
        ]
        let decoded = try XMLStreamDecoder().decode(WithOptional.self, from: events)
        XCTAssertEqual(decoded, WithOptional(name: "Bob", note: "a note"))
    }

    // MARK: - 6. XML attributes

    func test_decode_attributes() throws {
        let original = WithAttribute(id: XMLAttribute(wrappedValue: "item-1"), name: "Widget")
        let events = try XMLStreamEncoder().encode(original)
        let decoded = try XMLStreamDecoder().decode(WithAttribute.self, from: events)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - 7. Out-of-order fields

    func test_decode_outOfOrderFields() throws {
        // XML has <a> then <b>, but Reordered declares b before a.
        // The cursor decoder's ChildIndex handles this without backtracking.
        let events: [XMLStreamEvent] = [
            Self.se("Reordered"),
            Self.se("a"), .text("alpha"), Self.ee("a"),
            Self.se("b"), .text("beta"),  Self.ee("b"),
            Self.ee("Reordered")
        ]
        let decoded = try XMLStreamDecoder().decode(Reordered.self, from: events)
        XCTAssertEqual(decoded, Reordered(b: "beta", a: "alpha"))
    }

    // MARK: - 8. CDATA content as scalar value

    func test_decode_cdataContent() throws {
        let events: [XMLStreamEvent] = [
            Self.se("WithCDATA"),
            Self.se("content"), .cdata("Hello & World"), Self.ee("content"),
            Self.ee("WithCDATA")
        ]
        let decoded = try XMLStreamDecoder().decode(WithCDATA.self, from: events)
        XCTAssertEqual(decoded.content, "Hello & World")
    }

    // MARK: - 9. Mixed text and CDATA concatenation

    func test_decode_mixedTextAndCdata() throws {
        let events: [XMLStreamEvent] = [
            Self.se("WithCDATA"),
            Self.se("content"),
            .text("Hello "),
            .cdata("World"),
            .text("!"),
            Self.ee("content"),
            Self.ee("WithCDATA")
        ]
        let decoded = try XMLStreamDecoder().decode(WithCDATA.self, from: events)
        XCTAssertEqual(decoded.content, "Hello World!")
    }

    // MARK: - 10. Round-trip via encoder

    func test_decode_roundTrip_viaEncoder() throws {
        let original = Simple(name: "round-trip", value: 99)
        let events = try XMLStreamEncoder().encode(original)
        let decoded = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - 11. Matches XMLDecoder on classic XML

    func test_decode_roundTrip_matchesXMLDecoder() throws {
        let original = Simple(name: "compare", value: 123)
        let data = try XMLEncoder().encode(original)

        // Decode via classical XMLDecoder
        let viaTree = try XMLDecoder().decode(Simple.self, from: data)

        // Decode via XMLStreamDecoder (uses XMLStreamEventDecoder internally)
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: data) { events.append($0) }
        let viaStream = try XMLStreamDecoder().decode(Simple.self, from: events)

        XCTAssertEqual(viaTree, viaStream)
    }

    // MARK: - 12. Malformed stream (no root element)

    func test_decode_invalidEvents_throws() {
        let events: [XMLStreamEvent] = [.startDocument(version: "1.0", encoding: nil, standalone: nil)]
        XCTAssertThrowsError(try XMLStreamDecoder().decode(Simple.self, from: events)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .parseFailed(let msg) = xmlError else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
            XCTAssertTrue(msg?.contains("STREAM_DEC_002") == true, "Unexpected message: \(msg ?? "<nil>")")
        }
    }
}
