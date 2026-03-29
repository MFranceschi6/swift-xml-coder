import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamDecoderTests: XCTestCase {

    // MARK: - Fixtures

    private struct Simple: Codable, Equatable {
        var name: String
        var value: Int
    }

    private struct WithArray: Codable, Equatable {
        var items: [String]
    }

    // MARK: - Decode from XMLStreamParser events

    func test_decode_fromParserEvents_producesCorrectValue() throws {
        let xml = "<Simple><name>hello</name><value>42</value></Simple>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let decoded = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(decoded.name, "hello")
        XCTAssertEqual(decoded.value, 42)
    }

    // MARK: - Encoder → Decoder round-trip

    func test_decode_encoderDecoderRoundTrip() throws {
        let original = Simple(name: "roundtrip", value: 99)
        let events = try XMLStreamEncoder().encode(original)
        let decoded  = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Array field

    func test_decode_arrayField_fromParserEvents() throws {
        let xml = "<WithArray><items><item>a</item><item>b</item><item>c</item></items></WithArray>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let decoded = try XMLStreamDecoder().decode(WithArray.self, from: events)
        XCTAssertEqual(decoded.items, ["a", "b", "c"])
    }

    // MARK: - comment and processingInstruction are ignored

    func test_decode_commentAndPI_ignoredSilently() throws {
        // Comments and PIs interspersed in the stream should be ignored.
        let xml = """
        <?xml version="1.0"?>\
        <!-- a comment -->\
        <Simple><name>hi</name><value>1</value></Simple>
        """
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let hasComment = events.contains { if case .comment = $0 { return true }; return false }
        XCTAssertTrue(hasComment, "Parser should have emitted a comment event")

        // Decoding must succeed despite the comment event.
        let decoded = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(decoded.name, "hi")
        XCTAssertEqual(decoded.value, 1)
    }

    // MARK: - Empty stream → parseFailed

    func test_decode_emptyStream_throwsParseError() {
        let events: [XMLStreamEvent] = []
        XCTAssertThrowsError(try XMLStreamDecoder().decode(Simple.self, from: events)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .parseFailed(let msg) = xmlError else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
            XCTAssertTrue(msg?.contains("STREAM_DEC_002") == true)
        }
    }

    // MARK: - Stream without endDocument still decodes

    func test_decode_streamWithoutEndDocument_decodesRoot() throws {
        // A stream that ends after the root element closes (no .endDocument) must still succeed.
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Simple"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "name"), attributes: [], namespaceDeclarations: []),
            .text("no-doc-end"),
            .endElement(name: XMLQualifiedName(localName: "name")),
            .startElement(name: XMLQualifiedName(localName: "value"), attributes: [], namespaceDeclarations: []),
            .text("0"),
            .endElement(name: XMLQualifiedName(localName: "value")),
            .endElement(name: XMLQualifiedName(localName: "Simple"))
            // intentionally no .endDocument
        ]
        let decoded = try XMLStreamDecoder().decode(Simple.self, from: events)
        XCTAssertEqual(decoded.name, "no-doc-end")
        XCTAssertEqual(decoded.value, 0)
    }

    // MARK: - Async: decode from XMLStreamParser.events(for:)

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_decode_async_fromParserAsyncStream() async throws {
        let original = Simple(name: "asynctest", value: 77)
        let encoded  = try XMLEncoder().encode(original)

        let decoded = try await XMLStreamDecoder().decode(
            Simple.self,
            from: XMLStreamParser().events(for: encoded)
        )
        XCTAssertEqual(original, decoded)
    }
}
