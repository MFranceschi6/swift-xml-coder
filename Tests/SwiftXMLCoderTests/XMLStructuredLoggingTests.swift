import Foundation
import Logging
import XCTest

@testable import SwiftXMLCoder
@testable import SwiftXMLCoderTestSupport

// MARK: - Test fixtures

private struct SimpleModel: Codable {
    var name: String
    var value: Int
}

private struct DateModel: Codable {
    var timestamp: Date
}

// Mirrors what @XMLCodable + @XMLDateFormat generates.
extension DateModel: XMLDateCodingOverrideProvider {
    static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
        ["timestamp": .xsdDate]
    }
}

// A type whose name needs sanitisation in lenient mode (leading digit).
private struct _3DPoint: Codable, XMLRootNode {
    static let xmlRootElementName = "3DPoint"
    var x: Double
}

// MARK: - XMLStructuredLoggingTests

final class XMLStructuredLoggingTests: XCTestCase {

    // MARK: Encoder — lifecycle

    func testEncoderEncodeStartCarriesTypeAndRootElement() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Item", logger: logger))

        _ = try encoder.encode(SimpleModel(name: "hello", value: 42))

        let entry = handler.entries(at: .debug).first { $0.message == "XML encode started" }
        XCTAssertNotNil(entry, "Expected 'XML encode started' debug entry")
        XCTAssertEqual(entry?.metadata["type"], "SimpleModel")
        XCTAssertEqual(entry?.metadata["rootElement"], "Item")
    }

    func testEncoderEncodeCompletedCarriesRootElementAndChildCount() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))

        // SimpleModel has 2 fields → 2 child elements
        _ = try encoder.encode(SimpleModel(name: "hello", value: 42))

        let entry = handler.entries(at: .debug).first { $0.message == "XML encode completed" }
        XCTAssertNotNil(entry, "Expected 'XML encode completed' debug entry")
        XCTAssertNotNil(entry?.metadata["rootElement"])
        XCTAssertEqual(entry?.metadata["childCount"], "2")
    }

    func testEncoderRootNameDerivedFromTypeName() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))

        _ = try encoder.encode(SimpleModel(name: "a", value: 1))

        // No explicit rootElementName → derived from type, debug log emitted
        XCTAssertTrue(
            handler.hasEntry(at: .debug, containing: "Root element name derived from type name"),
            "Expected type-name derivation debug log, got: \(handler.entries.map(\.message))"
        )
    }

    func testEncoderWarnsWhenRootElementNameSanitized() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        // "1bad" starts with a digit → sanitized to "_1bad" in lenient mode
        let encoder = XMLEncoder(configuration: .init(rootElementName: "1bad", logger: logger))

        _ = try encoder.encode(SimpleModel(name: "a", value: 1))

        XCTAssertTrue(
            handler.hasEntry(at: .warning, containing: "rootElementName sanitized"),
            "Expected rootElementName sanitization warning, got: \(handler.entries.map(\.message))"
        )
        let entry = handler.entries(at: .warning).first { $0.message.contains("rootElementName sanitized") }
        XCTAssertEqual(entry?.metadata["original"], "1bad")
    }

    // MARK: Encoder — per-property date hint

    func testEncoderEmitsTraceForPerPropertyDateHint() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))
        let date = Date(timeIntervalSince1970: 0)

        _ = try encoder.encode(DateModel(timestamp: date))

        XCTAssertTrue(
            handler.hasEntry(at: .trace, containing: "Per-property date hint applied"),
            "Expected per-property hint trace log, got: \(handler.entries.map(\.message))"
        )
    }

    func testEncoderHintTraceContainsFieldAndHintMetadata() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))
        let date = Date(timeIntervalSince1970: 0)

        _ = try encoder.encode(DateModel(timestamp: date))

        let entry = handler.entries(at: .trace).first { $0.message.contains("Per-property date hint applied") }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.metadata["field"], "timestamp")
        XCTAssertNotNil(entry?.metadata["hint"])
    }

    func testEncoderNoHintLogWhenNoOverride() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))

        _ = try encoder.encode(SimpleModel(name: "a", value: 1))

        let hintEntries = handler.entries.filter { $0.message.contains("Per-property date hint applied") }
        XCTAssertTrue(hintEntries.isEmpty, "Should not emit hint log for types without date overrides")
    }

    // MARK: Decoder — lifecycle

    func testDecoderDecodeStartCarriesTypeAndRootElement() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let decoder = XMLDecoder(configuration: .init(logger: logger))
        let xml = Data("<SimpleModel><name>hi</name><value>7</value></SimpleModel>".utf8)

        _ = try decoder.decode(SimpleModel.self, from: xml)

        let entry = handler.entries(at: .debug).first { $0.message == "XML decode started" }
        XCTAssertNotNil(entry, "Expected 'XML decode started' debug entry")
        XCTAssertEqual(entry?.metadata["type"], "SimpleModel")
        XCTAssertEqual(entry?.metadata["rootElement"], "SimpleModel")
    }

    func testDecoderDecodeCompletedCarriesRootElementAndChildCount() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let decoder = XMLDecoder(configuration: .init(logger: logger))
        let xml = Data("<SimpleModel><name>hi</name><value>7</value></SimpleModel>".utf8)

        _ = try decoder.decode(SimpleModel.self, from: xml)

        let entry = handler.entries(at: .debug).first { $0.message == "XML decode completed" }
        XCTAssertNotNil(entry, "Expected 'XML decode completed' debug entry")
        XCTAssertEqual(entry?.metadata["rootElement"], "SimpleModel")
        XCTAssertEqual(entry?.metadata["childCount"], "2")
    }

    func testDecoderEmitsErrorOnRootMismatch() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Expected", logger: logger))
        let xml = Data("<Wrong><name>hi</name><value>7</value></Wrong>".utf8)

        XCTAssertThrowsError(try decoder.decode(SimpleModel.self, from: xml))
        XCTAssertTrue(
            handler.hasEntry(at: .error, containing: "root element mismatch"),
            "Expected root mismatch error log, got: \(handler.entries.map(\.message))"
        )
        let entry = handler.entries(at: .error).first { $0.message.contains("root element mismatch") }
        XCTAssertEqual(entry?.metadata["expected"], "Expected")
        XCTAssertEqual(entry?.metadata["found"], "Wrong")
    }

    // MARK: Decoder — per-property date hint

    func testDecoderEmitsTraceForPerPropertyDateHint() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let decoder = XMLDecoder(configuration: .init(logger: logger))
        let xml = Data("<DateModel><timestamp>2000-01-01</timestamp></DateModel>".utf8)

        _ = try decoder.decode(DateModel.self, from: xml)

        XCTAssertTrue(
            handler.hasEntry(at: .trace, containing: "Per-property date hint applied"),
            "Expected per-property hint trace log, got: \(handler.entries.map(\.message))"
        )
    }

    func testDecoderHintTraceContainsFieldMetadata() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let decoder = XMLDecoder(configuration: .init(logger: logger))
        let xml = Data("<DateModel><timestamp>2000-01-01</timestamp></DateModel>".utf8)

        _ = try decoder.decode(DateModel.self, from: xml)

        let entry = handler.entries(at: .trace).first { $0.message.contains("Per-property date hint applied") }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.metadata["field"], "timestamp")
    }

    // MARK: XMLTreeParser — lifecycle

    func testParserEmitsDebugOnParseStartAndCompletion() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let parser = XMLTreeParser(configuration: .init(logger: logger))
        let xml = Data("<root><child>text</child></root>".utf8)

        _ = try parser.parse(data: xml)

        XCTAssertTrue(handler.hasEntry(at: .debug, containing: "XML parse started"))
        XCTAssertTrue(handler.hasEntry(at: .debug, containing: "XML parse completed"))
    }

    func testParserCompletionCarriesNodeCount() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let parser = XMLTreeParser(configuration: .init(logger: logger))
        let xml = Data("<root><child>text</child></root>".utf8)

        _ = try parser.parse(data: xml)

        let entry = handler.entries(at: .debug).first { $0.message == "XML parse completed" }
        XCTAssertNotNil(entry)
        // 2 elements (root + child) + 1 text node = 3, depending on whitespace policy
        XCTAssertNotNil(entry?.metadata["nodeCount"])
    }

    // MARK: XMLTreeParser — limit warnings

    func testParserWarnsWhenInputBytesExceedLimit() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let limits = XMLTreeParser.Limits(maxInputBytes: 10)
        let parser = XMLTreeParser(configuration: .init(limits: limits, logger: logger))
        let xml = Data("<root><child>this is more than 10 bytes</child></root>".utf8)

        XCTAssertThrowsError(try parser.parse(data: xml))
        XCTAssertTrue(
            handler.hasEntry(at: .warning, containing: "limit exceeded"),
            "Expected limit exceeded warning, got: \(handler.entries.map(\.message))"
        )
        let entry = handler.entries(at: .warning).first { $0.message.contains("limit exceeded") }
        XCTAssertNotNil(entry?.metadata["code"])
        XCTAssertNotNil(entry?.metadata["actual"])
        XCTAssertNotNil(entry?.metadata["limit"])
    }

    func testParserWarnsOnceWhenApproachingNodeCountLimit() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        // maxNodeCount=5, 80% threshold = 4; our XML has exactly 5 nodes
        let limits = XMLTreeParser.Limits(maxNodeCount: 5)
        let parser = XMLTreeParser(configuration: .init(limits: limits, logger: logger))
        // 4 elements + 1 text = 5 nodes
        let xml = Data("<a><b><c><d>x</d></c></b></a>".utf8)

        _ = try parser.parse(data: xml)

        let warnings = handler.entries(at: .warning).filter { $0.message.contains("node count approaching") }
        // Must emit exactly once, not once per node
        XCTAssertEqual(warnings.count, 1, "Expected exactly 1 'approaching' warning, got \(warnings.count)")
    }

    func testParserWarnsOnceWhenApproachingDepthLimit() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        // maxDepth=5, 80% = 4; XML goes 5 levels deep
        let limits = XMLTreeParser.Limits(maxDepth: 5)
        let parser = XMLTreeParser(configuration: .init(limits: limits, logger: logger))
        let xml = Data("<a><b><c><d><e/></d></c></b></a>".utf8)

        _ = try parser.parse(data: xml)

        let warnings = handler.entries(at: .warning).filter { $0.message.contains("depth") }
        // Must emit exactly once
        XCTAssertEqual(warnings.count, 1, "Expected exactly 1 depth warning, got \(warnings.count)")
    }

    // MARK: XMLCapturingLogHandler helpers

    func testCapturingHandlerReset() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))

        _ = try encoder.encode(SimpleModel(name: "a", value: 1))
        XCTAssertFalse(handler.entries.isEmpty)

        handler.reset()
        XCTAssertTrue(handler.entries.isEmpty)
    }

    func testCapturingHandlerEntriesContaining() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))

        _ = try encoder.encode(SimpleModel(name: "a", value: 1))

        XCTAssertFalse(handler.entries(containing: "XML encode").isEmpty)
    }

    func testCapturingHandlerHasEntryWithMetadataKey() throws {
        let handler = XMLCapturingLogHandler(label: "test")
        let logger = Logger(label: "test") { _ in handler }
        let encoder = XMLEncoder(configuration: .init(logger: logger))
        let date = Date(timeIntervalSince1970: 0)

        _ = try encoder.encode(DateModel(timestamp: date))

        XCTAssertTrue(
            handler.hasEntry(at: .trace, withMetadataKey: "field"),
            "Expected trace entry with 'field' metadata key"
        )
    }
}
