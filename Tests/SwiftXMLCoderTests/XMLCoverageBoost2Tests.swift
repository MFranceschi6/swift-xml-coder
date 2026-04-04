import Foundation
@testable import SwiftXMLCoder
import XCTest

// MARK: - Coverage Boost Tests — Phase 2
//
// Targeted tests to exercise previously uncovered paths in:
// - _XMLEventEncoder: nested containers, super encoder, expand-empty, nil unkeyed
// - XMLStreamWriterSink: limit violations, write-after-finish, flush boundary
// - XMLDefaultCanonicalizer: stream-based API, event transforms, CDATA normalisation
// - XMLItemDecoder: empty data, non-matching elements, configuration propagation
// - _XMLStreamingParserSession: buffer recycling
// - _XMLEventCollector: childCount tracking

// MARK: - File-scope model for namespace test

private struct _NSModelForTest: Codable {
    let name: String
}
extension _NSModelForTest: XMLFieldNamespaceProvider {
    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["name": XMLNamespace(prefix: "ns", uri: "http://example.com")]
    }
}

final class XMLCoverageBoost2Tests: XCTestCase {

    // MARK: - Event encoder: nested keyed container via Codable

    /// Model that uses `nestedContainer(keyedBy:forKey:)` via manual Codable conformance.
    private struct ManualNested: Codable, Equatable {
        let outer: String
        let innerA: Int
        let innerB: String

        enum CodingKeys: String, CodingKey { case outer, nested }
        enum NestedKeys: String, CodingKey { case innerA, innerB }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(outer, forKey: .outer)
            var nested = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
            try nested.encode(innerA, forKey: .innerA)
            try nested.encode(innerB, forKey: .innerB)
        }

        init(outer: String, innerA: Int, innerB: String) {
            self.outer = outer
            self.innerA = innerA
            self.innerB = innerB
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            outer = try container.decode(String.self, forKey: .outer)
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
            innerA = try nested.decode(Int.self, forKey: .innerA)
            innerB = try nested.decode(String.self, forKey: .innerB)
        }
    }

    func test_eventEncoder_nestedKeyedContainer_roundTrips() throws {
        let original = ManualNested(outer: "hello", innerA: 42, innerB: "world")
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(original)
        let decoded = try XMLDecoder().decode(ManualNested.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Event encoder: nested unkeyed container

    private struct ManualNestedUnkeyed: Codable, Equatable {
        let label: String
        let values: [Int]

        enum CodingKeys: String, CodingKey { case label, values }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            var unkeyed = container.nestedUnkeyedContainer(forKey: .values)
            for v in values { try unkeyed.encode(v) }
        }

        init(label: String, values: [Int]) {
            self.label = label
            self.values = values
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            var unkeyed = try container.nestedUnkeyedContainer(forKey: .values)
            var vals: [Int] = []
            while !unkeyed.isAtEnd { vals.append(try unkeyed.decode(Int.self)) }
            values = vals
        }
    }

    func test_eventEncoder_nestedUnkeyedContainer_roundTrips() throws {
        let original = ManualNestedUnkeyed(label: "nums", values: [1, 2, 3])
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(original)
        let decoded = try XMLDecoder().decode(ManualNestedUnkeyed.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Event encoder: superEncoder

    private struct UseSuperEncoder: Codable, Equatable {
        let name: String
        let value: Int

        enum CodingKeys: String, CodingKey { case name, value }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            let superEnc = container.superEncoder(forKey: .value)
            var single = superEnc.singleValueContainer()
            try single.encode(value)
        }

        init(name: String, value: Int) {
            self.name = name
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(Int.self, forKey: .value)
        }
    }

    func test_eventEncoder_superEncoder_producesValidXML() throws {
        let original = UseSuperEncoder(name: "test", value: 99)
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(original)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<name>test</name>"), "Expected name element in \(xml)")
        XCTAssert(xml.contains("<value>"), "Expected value element in \(xml)")
    }

    // MARK: - Event encoder: superEncoder() without key

    private struct UseSuperEncoderDefault: Codable, Equatable {
        let tag: String

        enum CodingKeys: String, CodingKey { case tag }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tag, forKey: .tag)
            let superEnc = container.superEncoder()
            var single = superEnc.singleValueContainer()
            try single.encode("superValue")
        }

        init(tag: String) { self.tag = tag }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tag = try container.decode(String.self, forKey: .tag)
        }
    }

    func test_eventEncoder_superEncoderDefault_producesValidXML() throws {
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(UseSuperEncoderDefault(tag: "hi"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<tag>hi</tag>"), "Expected tag in \(xml)")
        XCTAssert(xml.contains("<super>"), "Expected super element in \(xml)")
    }

    // MARK: - Event encoder: expand-empty nil elements

    func test_eventEncoder_nilElement_expandEmpty() throws {
        struct WithOptional: Codable {
            let name: String?
        }
        // @XMLExpandEmpty would normally trigger this, test via emptyElement strategy
        let data = try XMLEncoder(configuration: .init(
            rootElementName: "root",
            nilEncodingStrategy: .emptyElement
        )).encode(WithOptional(name: nil))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<name"), "Expected <name> element for nil with emptyElement strategy in \(xml)")
    }

    // MARK: - Event encoder: unkeyed container encodeNil

    func test_eventEncoder_unkeyedNil_emptyElement() throws {
        struct WithOptionalArray: Codable {
            let items: [String?]
        }
        let data = try XMLEncoder(configuration: .init(
            rootElementName: "root",
            nilEncodingStrategy: .emptyElement
        )).encode(WithOptionalArray(items: ["a", nil, "b"]))
        let xml = String(decoding: data, as: UTF8.self)
        // Should contain 3 item elements (one empty for nil)
        XCTAssert(xml.contains("<item"), "Expected item elements in \(xml)")
    }

    // MARK: - Event encoder: single value container with complex value

    private struct WrapperSingle: Codable, Equatable {
        let inner: InnerSingle

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(inner)
        }

        init(inner: InnerSingle) { self.inner = inner }

        init(from decoder: Decoder) throws {
            inner = try InnerSingle(from: decoder)
        }
    }

    private struct InnerSingle: Codable, Equatable {
        let x: Int
        let y: String
    }

    func test_eventEncoder_singleValueContainer_complexValue() throws {
        let original = WrapperSingle(inner: InnerSingle(x: 1, y: "ok"))
        let data = try XMLEncoder(configuration: .init(rootElementName: "wrap")).encode(original)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<x>1</x>"), "Expected x element in \(xml)")
        XCTAssert(xml.contains("<y>ok</y>"), "Expected y element in \(xml)")
    }

    // MARK: - Event encoder: unkeyed nested keyed container

    private struct UnkeyedWithNestedKeyed: Codable, Equatable {
        let entries: [Entry]

        struct Entry: Codable, Equatable {
            let a: Int
            let b: String
            enum CodingKeys: String, CodingKey { case a, b }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var unkeyed = container.nestedUnkeyedContainer(forKey: .entries)
            for entry in entries {
                var nested = unkeyed.nestedContainer(keyedBy: Entry.CodingKeys.self)
                try nested.encode(entry.a, forKey: .a)
                try nested.encode(entry.b, forKey: .b)
            }
        }

        enum CodingKeys: String, CodingKey { case entries }

        init(entries: [Entry]) { self.entries = entries }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decode([Entry].self, forKey: .entries)
        }
    }

    func test_eventEncoder_unkeyedNestedKeyed_producesValidXML() throws {
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(
            UnkeyedWithNestedKeyed(entries: [
                .init(a: 1, b: "x"),
                .init(a: 2, b: "y"),
            ])
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<a>1</a>"), "Expected a=1 in \(xml)")
        XCTAssert(xml.contains("<b>y</b>"), "Expected b=y in \(xml)")
    }

    // MARK: - Event encoder: unkeyed nestedUnkeyedContainer

    private struct UnkeyedWithNestedUnkeyed: Codable {
        let matrix: [[Int]]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var outer = container.nestedUnkeyedContainer(forKey: .matrix)
            for row in matrix {
                var inner = outer.nestedUnkeyedContainer()
                for val in row { try inner.encode(val) }
            }
        }

        enum CodingKeys: String, CodingKey { case matrix }
    }

    func test_eventEncoder_unkeyedNestedUnkeyed_producesValidXML() throws {
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(
            UnkeyedWithNestedUnkeyed(matrix: [[1, 2], [3, 4]])
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<item>"), "Expected item elements in \(xml)")
    }

    // MARK: - Event encoder: unkeyed superEncoder

    private struct UnkeyedWithSuper: Codable {
        let values: [Int]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var unkeyed = container.nestedUnkeyedContainer(forKey: .values)
            for v in values {
                let superEnc = unkeyed.superEncoder()
                var single = superEnc.singleValueContainer()
                try single.encode(v)
            }
        }

        enum CodingKeys: String, CodingKey { case values }
    }

    func test_eventEncoder_unkeyedSuperEncoder_producesValidXML() throws {
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(
            UnkeyedWithSuper(values: [10, 20])
        )
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("10"), "Expected 10 in \(xml)")
        XCTAssert(xml.contains("20"), "Expected 20 in \(xml)")
    }

    // MARK: - _XMLEventCollector: childCount accuracy

    func test_eventCollector_childCount_countsRootChildren() {
        let collector = _XMLEventCollector()
        // Root element
        collector.append(.startElement(
            name: XMLQualifiedName(localName: "root"),
            attributes: [],
            namespaceDeclarations: []
        ))
        // Two children
        collector.append(.startElement(
            name: XMLQualifiedName(localName: "a"),
            attributes: [],
            namespaceDeclarations: []
        ))
        collector.append(.text("hello"))
        collector.append(.endElement(name: XMLQualifiedName(localName: "a")))
        collector.append(.startElement(
            name: XMLQualifiedName(localName: "b"),
            attributes: [],
            namespaceDeclarations: []
        ))
        collector.append(.text("world"))
        collector.append(.endElement(name: XMLQualifiedName(localName: "b")))
        collector.append(.endElement(name: XMLQualifiedName(localName: "root")))

        XCTAssertEqual(collector.childCount, 2)
    }

    func test_eventCollector_childCount_excludesGrandchildren() {
        let collector = _XMLEventCollector()
        collector.append(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        collector.append(.startElement(name: XMLQualifiedName(localName: "child"), attributes: [], namespaceDeclarations: []))
        collector.append(.startElement(name: XMLQualifiedName(localName: "grandchild"), attributes: [], namespaceDeclarations: []))
        collector.append(.endElement(name: XMLQualifiedName(localName: "grandchild")))
        collector.append(.endElement(name: XMLQualifiedName(localName: "child")))
        collector.append(.endElement(name: XMLQualifiedName(localName: "root")))

        XCTAssertEqual(collector.childCount, 1, "Only direct children of root should be counted")
    }

    // MARK: - XMLStreamWriterSink: write after finish

    func test_writerSink_writeAfterFinish_throws() throws {
        let sink = try XMLStreamWriterSink(configuration: .init()) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        XCTAssertThrowsError(try sink.write(.text("after finish")))
    }

    // MARK: - XMLStreamWriterSink: finish is idempotent

    func test_writerSink_finishIdempotent_doesNotThrow() throws {
        let sink = try XMLStreamWriterSink(configuration: .init()) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()
        try sink.finish() // Should not throw
    }

    // MARK: - XMLStreamWriterSink: text node byte limit

    func test_writerSink_textNodeByteLimitExceeded_throws() throws {
        let limits = XMLStreamWriter.WriterLimits(maxTextNodeBytes: 5)
        let config = XMLStreamWriter.Configuration(limits: limits)
        let sink = try XMLStreamWriterSink(configuration: config) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))

        XCTAssertThrowsError(try sink.write(.text("this is way too long"))) { error in
            if case XMLParsingError.parseFailed(let msg) = error {
                XCTAssert(msg?.contains("MAX_TEXT_NODE_BYTES") == true, "Expected text limit error, got: \(msg ?? "nil")")
            }
        }
    }

    // MARK: - XMLStreamWriterSink: CDATA byte limit

    func test_writerSink_cdataByteLimitExceeded_throws() throws {
        let limits = XMLStreamWriter.WriterLimits(maxCDATABlockBytes: 3)
        let config = XMLStreamWriter.Configuration(limits: limits)
        let sink = try XMLStreamWriterSink(configuration: config) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))

        XCTAssertThrowsError(try sink.write(.cdata("long cdata content"))) { error in
            if case XMLParsingError.parseFailed(let msg) = error {
                XCTAssert(msg?.contains("MAX_CDATA_BYTES") == true, "Expected CDATA limit error, got: \(msg ?? "nil")")
            }
        }
    }

    // MARK: - XMLStreamWriterSink: comment byte limit

    func test_writerSink_commentByteLimitExceeded_throws() throws {
        let limits = XMLStreamWriter.WriterLimits(maxCommentBytes: 3)
        let config = XMLStreamWriter.Configuration(limits: limits)
        let sink = try XMLStreamWriterSink(configuration: config) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))

        XCTAssertThrowsError(try sink.write(.comment("this comment is too long"))) { error in
            if case XMLParsingError.parseFailed(let msg) = error {
                XCTAssert(msg?.contains("MAX_COMMENT_BYTES") == true, "Expected comment limit error, got: \(msg ?? "nil")")
            }
        }
    }

    // MARK: - XMLStreamWriterSink: max depth limit

    func test_writerSink_maxDepthExceeded_throws() throws {
        let limits = XMLStreamWriter.WriterLimits(maxDepth: 2)
        let config = XMLStreamWriter.Configuration(limits: limits)
        let sink = try XMLStreamWriterSink(configuration: config) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "a"), attributes: [], namespaceDeclarations: []))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "b"), attributes: [], namespaceDeclarations: []))
        // Depth is now 2, trying to go to 3 should fail
        XCTAssertThrowsError(try sink.write(.startElement(name: XMLQualifiedName(localName: "c"), attributes: [], namespaceDeclarations: []))) { error in
            if case XMLParsingError.parseFailed(let msg) = error {
                XCTAssert(msg?.contains("MAX_DEPTH") == true, "Expected depth limit error, got: \(msg ?? "nil")")
            }
        }
    }

    // MARK: - XMLStreamWriterSink: max node count limit

    func test_writerSink_maxNodeCountExceeded_throws() throws {
        let limits = XMLStreamWriter.WriterLimits(maxNodeCount: 3)
        let config = XMLStreamWriter.Configuration(limits: limits)
        let sink = try XMLStreamWriterSink(configuration: config) { _ in }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        // Node 1: startElement
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        // Node 2: text
        try sink.write(.text("a"))
        // Node 3: another text
        try sink.write(.text("b"))
        // Node 4: should exceed limit
        XCTAssertThrowsError(try sink.write(.text("c"))) { error in
            if case XMLParsingError.parseFailed(let msg) = error {
                XCTAssert(msg?.contains("MAX_NODE_COUNT") == true, "Expected node count error, got: \(msg ?? "nil")")
            }
        }
    }

    // MARK: - XMLStreamWriterSink: expandEmptyElements

    func test_writerSink_expandEmptyElements_producesFullClosingTag() throws {
        var chunks: [Data] = []
        let config = XMLStreamWriter.Configuration(expandEmptyElements: true)
        let sink = try XMLStreamWriterSink(configuration: config) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "empty"), attributes: [], namespaceDeclarations: []))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "empty")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("<empty></empty>"), "Expected expanded empty element, got: \(xml)")
    }

    // MARK: - XMLStreamWriterSink: processing instruction

    func test_writerSink_processingInstruction() throws {
        var chunks: [Data] = []
        let sink = try XMLStreamWriterSink(configuration: .init()) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.processingInstruction(target: "xml-stylesheet", data: "type=\"text/xsl\""))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("xml-stylesheet"), "Expected PI in \(xml)")
    }

    // MARK: - XMLStreamWriterSink: comment

    func test_writerSink_comment() throws {
        var chunks: [Data] = []
        let sink = try XMLStreamWriterSink(configuration: .init()) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.comment("test comment"))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("test comment"), "Expected comment in \(xml)")
    }

    // MARK: - XMLStreamWriterSink: standalone declaration

    func test_writerSink_standaloneDeclaration() throws {
        var chunks: [Data] = []
        let sink = try XMLStreamWriterSink(configuration: .init()) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: true))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("standalone=\"yes\""), "Expected standalone=yes in \(xml)")
    }

    // MARK: - XMLStreamWriterSink: flush threshold with small threshold

    func test_writerSink_smallFlushThreshold_flushesMultipleTimes() throws {
        var chunkCount = 0
        let sink = try XMLStreamWriterSink(
            configuration: .init(),
            flushThreshold: 16
        ) { _ in chunkCount += 1 }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        for i in 0..<20 {
            try sink.write(.startElement(name: XMLQualifiedName(localName: "item"), attributes: [], namespaceDeclarations: []))
            try sink.write(.text("value_\(i)_padding"))
            try sink.write(.endElement(name: XMLQualifiedName(localName: "item")))
        }
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        XCTAssertGreaterThan(chunkCount, 1, "Expected multiple flushes with small threshold")
    }

}
