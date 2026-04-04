import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamParserIOTests: XCTestCase {

    // MARK: - Helpers

    private func events(from xml: String) throws -> [XMLStreamEvent] {
        var result: [XMLStreamEvent] = []
        let data = Data(xml.utf8)
        try XMLStreamParser().parse(data: data) { result.append($0) }
        return result
    }

    private func eventsViaStream(from xml: String) throws -> [XMLStreamEvent] {
        var result: [XMLStreamEvent] = []
        let data = Data(xml.utf8)
        let stream = InputStream(data: data)
        try XMLStreamParser().parse(stream: stream) { result.append($0) }
        return result
    }

    // MARK: - InputStream parse: basic correctness

    func test_parse_inputStream_emitsStartEndDocument() throws {
        let evts = try eventsViaStream(from: "<Root/>")
        XCTAssertEqual(evts.first, .startDocument(version: nil, encoding: nil, standalone: nil))
        XCTAssertEqual(evts.last, .endDocument)
    }

    func test_parse_inputStream_emitsCorrectElements() throws {
        let evts = try eventsViaStream(from: "<Root><child>hello</child></Root>")
        let names = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertEqual(names, ["Root", "child"])
    }

    func test_parse_inputStream_emitsTextContent() throws {
        let evts = try eventsViaStream(from: "<Root><value>42</value></Root>")
        let texts = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .text(let s) = e { return s }; return nil
        }
        XCTAssertTrue(texts.contains("42"))
    }

    // MARK: - InputStream vs Data: event sequence matches

    func test_parse_inputStream_matchesDataParser() throws {
        let xml = "<Person><name>Alice</name><age>30</age></Person>"
        let dataEvents   = try events(from: xml)
        let streamEvents = try eventsViaStream(from: xml)
        XCTAssertEqual(dataEvents, streamEvents)
    }

    func test_parse_inputStream_attributes_matchesDataParser() throws {
        let xml = #"<Item id="1" label="test"><sub x="y"/></Item>"#
        let dataEvents   = try events(from: xml)
        let streamEvents = try eventsViaStream(from: xml)
        XCTAssertEqual(dataEvents, streamEvents)
    }

    // MARK: - InputStream round-trip via XMLStreamWriter

    func test_parse_inputStream_roundTrip_viaWriter() throws {
        let original = "<Envelope><header/><body><value>99</value></body></Envelope>"
        let originalData = Data(original.utf8)

        var collectedEvents: [XMLStreamEvent] = []
        let stream = InputStream(data: originalData)
        try XMLStreamParser().parse(stream: stream) { collectedEvents.append($0) }

        let rewritten = try XMLStreamWriter().write(collectedEvents)

        // Re-parse and compare event sequences (ignoring whitespace from pretty-printing)
        var rewrittenEvents: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: rewritten) { rewrittenEvents.append($0) }

        let startNames = { (evts: [XMLStreamEvent]) -> [String] in
            evts.compactMap { if case .startElement(let n, _, _) = $0 { return n.localName }; return nil }
        }
        XCTAssertEqual(startNames(collectedEvents), startNames(rewrittenEvents))
    }

    // MARK: - InputStream: invalid XML throws

    func test_parse_inputStream_invalidXML_throws() {
        let xml = "<unclosed"
        let stream = InputStream(data: Data(xml.utf8))
        XCTAssertThrowsError(
            try XMLStreamParser().parse(stream: stream) { _ in }
        ) { error in
            XCTAssertTrue(error is XMLParsingError)
        }
    }

    // MARK: - AsyncSequence<UInt8>

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_parse_asyncBytes_matchesDataParser() async throws {
        let xml = "<Greeting><message>Hello</message></Greeting>"
        let data = Data(xml.utf8)

        let dataEvents = try { () throws -> [XMLStreamEvent] in
            var result: [XMLStreamEvent] = []
            try XMLStreamParser().parse(data: data) { result.append($0) }
            return result
        }()

        var asyncEvents: [XMLStreamEvent] = []
        let byteStream = AsyncStream<UInt8> { continuation in
            for byte in data { continuation.yield(byte) }
            continuation.finish()
        }
        for try await event in XMLStreamParser().events(for: byteStream) {
            asyncEvents.append(event)
        }

        XCTAssertEqual(dataEvents, asyncEvents)
    }

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_parse_asyncBytes_invalidXML_throws() async {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Data("<broken".utf8) { continuation.yield(byte) }
            continuation.finish()
        }
        var threw = false
        do {
            for try await _ in XMLStreamParser().events(for: bytes) {}
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "Expected XMLParsingError for invalid XML bytes")
    }
}
