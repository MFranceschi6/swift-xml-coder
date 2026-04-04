import Foundation
import SwiftXMLCoder
import XCTest

// Tests for XMLStreamEncoder.encodeEach (II.7) — streaming encode of AsyncSequence.
// All tests require macOS 12+ / iOS 15+ for AsyncThrowingStream and async iteration.

final class XMLStreamEncoderSequenceTests: XCTestCase {

    // MARK: - Fixtures

    private struct Simple: Codable, Equatable {
        var name: String
        var value: Int
    }

    private struct Header: Codable {
        var title: String
    }

    // MARK: - Helpers

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    private func makeAsync<T: Sendable>(_ array: [T]) -> AsyncStream<T> {
        AsyncStream { continuation in
            for item in array { continuation.yield(item) }
            continuation.finish()
        }
    }

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    private func collect(
        _ stream: AsyncThrowingStream<XMLStreamEvent, Error>
    ) async throws -> [XMLStreamEvent] {
        var result: [XMLStreamEvent] = []
        for try await event in stream { result.append(event) }
        return result
    }

    // MARK: - 1. Items are emitted in document order

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_emitsItemsInOrder() async throws {
        let items = [Simple(name: "a", value: 1), Simple(name: "b", value: 2), Simple(name: "c", value: 3)]
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(makeAsync(items), wrappedIn: "Root")
        let events = try await collect(stream)

        let texts = events.compactMap { event -> String? in
            if case .text(let str) = event { return str }
            return nil
        }
        XCTAssertEqual(texts, ["a", "1", "b", "2", "c", "3"])
    }

    // MARK: - 2. Empty sequence emits only preamble + postamble

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_emptySequence_onlyPreamblePostamble() async throws {
        let preamble: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: [])
        ]
        let postamble: [XMLStreamEvent] = [
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let empty = makeAsync([Simple]())
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(empty, preamble: preamble, postamble: postamble)
        let events = try await collect(stream)

        XCTAssertEqual(events, preamble + postamble)
    }

    // MARK: - 3. Preamble appears before first item, postamble after last

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_preamblePostamble_positionedCorrectly() async throws {
        let preamble: [XMLStreamEvent] = [
            .startElement(name: XMLQualifiedName(localName: "Wrapper"), attributes: [], namespaceDeclarations: [])
        ]
        let postamble: [XMLStreamEvent] = [
            .endElement(name: XMLQualifiedName(localName: "Wrapper"))
        ]
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(makeAsync([Simple(name: "x", value: 9)]),
                                          preamble: preamble, postamble: postamble)
        let events = try await collect(stream)

        XCTAssertEqual(events.first, preamble.first)
        XCTAssertEqual(events.last, postamble.last)
        guard events.count > 2,
              case .startElement(let name, _, _) = events[1],
              name.localName == "Simple" else {
            return XCTFail("Expected item startElement at index 1")
        }
    }

    // MARK: - 4. wrappedIn produces reparsable XML

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_wrappedIn_producesReparsableXML() async throws {
        let items = [Simple(name: "hello", value: 42), Simple(name: "world", value: 7)]
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(makeAsync(items), wrappedIn: "Items")
        let events = try await collect(stream)

        let data = try XMLStreamWriter().write(events)
        var reparsedEvents: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: data) { reparsedEvents.append($0) }

        let startElementNames = reparsedEvents.compactMap { event -> String? in
            if case .startElement(let name, _, _) = event { return name.localName }
            return nil
        }
        XCTAssertEqual(startElementNames.first, "Items")
        XCTAssertEqual(startElementNames.filter { $0 == "Simple" }.count, 2)
    }

    // MARK: - 5. wrappedIn with attributes sets wrapper attributes

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_wrappedIn_withAttributes_setsWrapperAttributes() async throws {
        let attr = XMLTreeAttribute(
            name: XMLQualifiedName(localName: "source"),
            value: "db"
        )
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(
                makeAsync([Simple(name: "item", value: 1)]),
                wrappedIn: "Items",
                attributes: [attr]
            )
        let events = try await collect(stream)

        let wrapperEvent = events.first { event -> Bool in
            if case .startElement(let name, _, _) = event { return name.localName == "Items" }
            return false
        }
        guard case .startElement(_, let attributes, _) = wrapperEvent else {
            return XCTFail("Wrapper startElement not found")
        }
        XCTAssertEqual(attributes.first?.value, "db")
    }

    // MARK: - 6. wrappedIn includeDocument:false omits document events

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_wrappedIn_includeDocumentFalse_noDocumentEvents() async throws {
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(
                makeAsync([Simple(name: "x", value: 0)]),
                wrappedIn: "Items",
                includeDocument: false
            )
        let events = try await collect(stream)

        let hasStartDoc = events.contains { if case .startDocument = $0 { return true }; return false }
        let hasEndDoc   = events.contains { if case .endDocument  = $0 { return true }; return false }
        XCTAssertFalse(hasStartDoc, "Should have no startDocument when includeDocument is false")
        XCTAssertFalse(hasEndDoc, "Should have no endDocument when includeDocument is false")

        let hasWrapper = events.contains { event -> Bool in
            if case .startElement(let name, _, _) = event { return name.localName == "Items" }
            return false
        }
        XCTAssertTrue(hasWrapper)
    }

    // MARK: - 7. Custom encodeItem overrides default encoding

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_customEncodeItem_overridesDefault() async throws {
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(
                makeAsync([Simple(name: "ignored", value: 99)]),
                preamble: [],
                postamble: []
            ) { (_: Simple) throws -> [XMLStreamEvent] in
                [
                    .startElement(name: XMLQualifiedName(localName: "Custom"),
                                  attributes: [], namespaceDeclarations: []),
                    .text("custom-content"),
                    .endElement(name: XMLQualifiedName(localName: "Custom"))
                ]
            }
        let events = try await collect(stream)

        let startElementNames = events.compactMap { event -> String? in
            if case .startElement(let name, _, _) = event { return name.localName }
            return nil
        }
        XCTAssertEqual(startElementNames, ["Custom"])
        let texts = events.compactMap { event -> String? in
            if case .text(let str) = event { return str }
            return nil
        }
        XCTAssertEqual(texts, ["custom-content"])
    }

    // MARK: - 8. Preamble from encoder.encode(header)

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_preambleFromEncodedHeader() async throws {
        let encoder = XMLStreamEncoder()
        let headerEvents = try encoder.encode(Header(title: "My Report"))

        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            encoder.encodeEach(makeAsync([Simple(name: "row1", value: 10)]), preamble: headerEvents)
        let events = try await collect(stream)

        for (idx, expected) in headerEvents.enumerated() {
            XCTAssertEqual(events[idx], expected, "Preamble event at \(idx) mismatch")
        }
        let afterPreamble = Array(events.dropFirst(headerEvents.count))
        let startNames = afterPreamble.compactMap { event -> String? in
            if case .startElement(let name, _, _) = event { return name.localName }
            return nil
        }
        XCTAssertTrue(startNames.contains("Simple"))
    }

    // MARK: - 9. Round-trip: encodeEach → XMLStreamWriter → XMLStreamDecoder per item

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_roundTrip_collect_decode() async throws {
        let original = [Simple(name: "alpha", value: 1), Simple(name: "beta", value: 2)]
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(makeAsync(original), wrappedIn: "Root")
        let events = try await collect(stream)

        // Decode each Simple element individually using XMLStreamDecoder
        let decoder = XMLStreamDecoder()
        var decoded: [Simple] = []
        var idx = 0
        while idx < events.count {
            if case .startElement(let name, _, _) = events[idx], name.localName == "Simple" {
                var depth = 1
                var end = idx + 1
                while depth > 0 && end < events.count {
                    if case .startElement = events[end] { depth += 1 } else if case .endElement = events[end] { depth -= 1 }
                    end += 1
                }
                // Wrap the element slice in document events for XMLStreamDecoder
                let slice: [XMLStreamEvent] =
                    [.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil)]
                    + Array(events[idx..<end])
                    + [.endDocument]
                decoded.append(try decoder.decode(Simple.self, from: slice))
            }
            idx += 1
        }
        XCTAssertEqual(decoded, original)
    }

    // MARK: - 10. Early exit from stream does not hang

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_earlyExit_doesNotHang() async throws {
        let manyItems = Array(repeating: Simple(name: "item", value: 0), count: 100)
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(makeAsync(manyItems), wrappedIn: "Root")

        var consumed = 0
        for try await _ in stream {
            consumed += 1
            if consumed >= 10 { break }
        }
        XCTAssertEqual(consumed, 10)
    }

    // MARK: - 11. Error in encodeItem propagates as stream error

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_encodeEach_errorInEncodeItem_propagates() async throws {
        struct EncodeError: Error {}

        // Trigger the error based on item content — avoids captured `var` in @Sendable closure
        let stream: AsyncThrowingStream<XMLStreamEvent, Error> =
            XMLStreamEncoder().encodeEach(
                makeAsync([Simple(name: "ok", value: 1), Simple(name: "fail", value: 2)]),
                preamble: [],
                postamble: []
            ) { (item: Simple) throws -> [XMLStreamEvent] in
                if item.name == "fail" { throw EncodeError() }
                return try XMLStreamEncoder().encode(item)
            }

        do {
            for try await _ in stream { /* consume until error */ }
            XCTFail("Expected stream to throw EncodeError")
        } catch is EncodeError {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
