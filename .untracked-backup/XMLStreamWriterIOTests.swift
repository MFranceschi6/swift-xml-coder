import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamWriterIOTests: XCTestCase {

    // MARK: - Fixtures

    private struct Simple: Codable, Equatable {
        var name: String
        var value: Int
    }

    // MARK: - OutputStream: basic correctness

    func test_write_toOutputStream_producesNonEmptyBytes() throws {
        let xml = "<Root><child>hello</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let outputStream = OutputStream.toMemory()
        try XMLStreamWriter().write(events, to: outputStream)

        guard let written = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            return XCTFail("No data written to OutputStream")
        }
        XCTAssertGreaterThan(written.count, 0)
    }

    func test_write_toOutputStream_producesValidXML() throws {
        let xml = "<Root><child>hello</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let outputStream = OutputStream.toMemory()
        try XMLStreamWriter().write(events, to: outputStream)

        let written = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()

        // Re-parse to verify well-formedness
        var reparsed: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: written) { reparsed.append($0) }

        let names = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertEqual(names, ["Root", "child"])
    }

    // MARK: - OutputStream matches in-memory write

    func test_write_toOutputStream_matchesInMemoryWrite() throws {
        let xml = "<Envelope><body><value id=\"1\">data</value></body></Envelope>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        // In-memory reference
        let inMemoryData = try XMLStreamWriter().write(events)

        // OutputStream variant
        let outputStream = OutputStream.toMemory()
        try XMLStreamWriter().write(events, to: outputStream)
        let streamData = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()

        XCTAssertEqual(inMemoryData, streamData)
    }

    // MARK: - OutputStream round-trip via XMLDecoder

    func test_write_toOutputStream_roundTrip() throws {
        let original = Simple(name: "streamIO", value: 42)
        let events = try XMLStreamEncoder().encode(original)

        let outputStream = OutputStream.toMemory()
        try XMLStreamWriter().write(events, to: outputStream)

        let data = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()
        let decoded = try XMLDecoder().decode(Simple.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - writeChunked: chunks concatenate to valid XML

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_writeChunked_chunksReassembleToValidXML() async throws {
        let xml = "<Root><child>hello</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        var combined = Data()
        for try await chunk in XMLStreamWriter().writeChunked(AsyncStream.fromSequence(events)) {
            combined.append(chunk)
        }

        XCTAssertGreaterThan(combined.count, 0)
        var reparsed: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: combined) { reparsed.append($0) }
        let names = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertEqual(names, ["Root", "child"])
    }

    // MARK: - writeChunked matches in-memory write

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_writeChunked_matchesInMemoryWrite() async throws {
        let xml = "<Person><first>John</first><last>Doe</last></Person>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let inMemoryData = try XMLStreamWriter().write(events)

        var combined = Data()
        for try await chunk in XMLStreamWriter().writeChunked(AsyncStream.fromSequence(events)) {
            combined.append(chunk)
        }

        XCTAssertEqual(inMemoryData, combined)
    }

    // MARK: - writeChunked round-trip via XMLStreamDecoder

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_writeChunked_roundTrip() async throws {
        let original = Simple(name: "chunkedIO", value: 77)
        let events = try XMLStreamEncoder().encode(original)

        var combined = Data()
        for try await chunk in XMLStreamWriter().writeChunked(AsyncStream.fromSequence(events)) {
            combined.append(chunk)
        }

        let decoded = try XMLDecoder().decode(Simple.self, from: combined)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - AsyncStream helper for tests

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
private extension AsyncStream where Element: Sendable {
    /// Creates an `AsyncStream` that emits all elements of a `Sequence` then finishes.
    static func fromSequence<S: Sequence & Sendable>(_ sequence: S) -> AsyncStream<Element>
    where S.Element == Element {
        AsyncStream { continuation in
            for element in sequence { continuation.yield(element) }
            continuation.finish()
        }
    }
}
