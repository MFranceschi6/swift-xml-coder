import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamWriterTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip(
        xml: String,
        parserConfig: XMLTreeParser.Configuration = .init(whitespaceTextNodePolicy: .preserve),
        writerConfig: XMLStreamWriter.Configuration = .init()
    ) throws -> [XMLStreamEvent] {
        let data = Data(xml.utf8)
        var events: [XMLStreamEvent] = []
        try XMLStreamParser(configuration: parserConfig).parse(data: data) { events.append($0) }
        let output = try XMLStreamWriter(configuration: writerConfig).write(events)
        var reparsed: [XMLStreamEvent] = []
        try XMLStreamParser(configuration: parserConfig).parse(data: output) { reparsed.append($0) }
        return reparsed
    }

    // MARK: - Simple round-trip

    func test_write_simpleRoundTrip() throws {
        let xml = "<Root><child>hello</child></Root>"
        let reparsed = try roundTrip(xml: xml)
        let texts = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .text(let s) = e { return s }; return nil
        }
        XCTAssertTrue(texts.contains("hello"))
    }

    // MARK: - Attributes

    func test_write_attributes() throws {
        let xml = #"<Root id="42" name="test"/>"#
        let reparsed = try roundTrip(xml: xml)
        let attrs = reparsed.compactMap { event -> [XMLTreeAttribute]? in
            if case .startElement(_, let a, _) = event, !a.isEmpty { return a } else { return nil }
        }.first ?? []
        let attrMap = Dictionary(attrs.map { ($0.name.localName, $0.value) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(attrMap["id"], "42")
        XCTAssertEqual(attrMap["name"], "test")
    }

    // MARK: - Namespaces

    func test_write_namespaces() throws {
        let xml = #"<ex:Root xmlns:ex="http://example.com/ns"/>"#
        let reparsed = try roundTrip(xml: xml)
        let names = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.namespaceURI }; return nil
        }
        XCTAssertTrue(names.contains("http://example.com/ns"))
    }

    // MARK: - CDATA

    func test_write_cdata() throws {
        let xml = "<Root><![CDATA[hello & world]]></Root>"
        let reparsed = try roundTrip(xml: xml)
        let cdata = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .cdata(let s) = e { return s }; return nil
        }
        XCTAssertTrue(cdata.contains("hello & world"), "Expected CDATA content to be preserved, got: \(cdata)")
    }

    // MARK: - Comment

    func test_write_comment() throws {
        let xml = "<Root><!-- a comment --></Root>"
        let reparsed = try roundTrip(xml: xml)
        let comments = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .comment(let s) = e { return s }; return nil
        }
        XCTAssertTrue(comments.contains(" a comment "))
    }

    // MARK: - Processing instruction

    func test_write_processingInstruction() throws {
        let xml = #"<?xml-stylesheet type="text/xsl"?><Root/>"#
        let reparsed = try roundTrip(xml: xml)
        let pis = reparsed.compactMap { (e: XMLStreamEvent) -> String? in
            if case .processingInstruction(let t, _) = e { return t }; return nil
        }
        XCTAssertTrue(pis.contains("xml-stylesheet"))
    }

    // MARK: - Empty events produce empty Data

    func test_write_emptyEventList_producesEmptyData() throws {
        let data = try XMLStreamWriter().write([] as [XMLStreamEvent])
        XCTAssertTrue(data.isEmpty)
    }

    // MARK: - Output is valid UTF-8

    func test_write_outputIsValidUTF8() throws {
        let xml = "<Root><child>hello ⬡</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }
        let output = try XMLStreamWriter().write(events)
        XCTAssertNotNil(String(data: output, encoding: .utf8), "Output should be valid UTF-8")
    }

    // MARK: - Security limits

    func test_write_depthLimit_throws() {
        // Events that nest beyond maxDepth
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "A"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "B"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "C"), attributes: [], namespaceDeclarations: []),
            .endElement(name: XMLQualifiedName(localName: "C")),
            .endElement(name: XMLQualifiedName(localName: "B")),
            .endElement(name: XMLQualifiedName(localName: "A")),
            .endDocument
        ]
        let limits = XMLStreamWriter.WriterLimits(maxDepth: 2)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    func test_write_outputBytesLimit_throws() throws {
        // Build events that produce > 50 bytes of output
        let xml = "<Root><child>a longer text content here</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }

        let limits = XMLStreamWriter.WriterLimits(maxOutputBytes: 20)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    func test_write_textNodeLimit_throws() {
        let bigText = String(repeating: "x", count: 200)
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .text(bigText),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let limits = XMLStreamWriter.WriterLimits(maxTextNodeBytes: 100)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    // MARK: - expandEmptyElements

    func test_write_expandEmptyElements_producesLongForm() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let config = XMLStreamWriter.Configuration(expandEmptyElements: true)
        let data = try XMLStreamWriter(configuration: config).write(events)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("</Root>"), "Expected long form </Root> but got: \(str)")
        XCTAssertFalse(str.contains("<Root/>"), "Unexpected self-closing form in: \(str)")
    }

    // MARK: - Async API

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_write_async_roundTrip() async throws {
        let xml = "<Root><child>async test</child></Root>"
        let data = Data(xml.utf8)
        let output = try await XMLStreamWriter().write(XMLStreamParser().events(for: data))
        XCTAssertFalse(output.isEmpty)
        // Re-parse to verify content
        var texts: [String] = []
        try XMLStreamParser().parse(data: output) { event in
            if case .text(let s) = event { texts.append(s) }
        }
        XCTAssertTrue(texts.contains("async test"))
    }

    // MARK: - Security limits — CDATA, comment, node count

    func test_write_cdataBlockLimit_throws() {
        let bigCDATA = String(repeating: "x", count: 200)
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .cdata(bigCDATA),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let limits = XMLStreamWriter.WriterLimits(maxCDATABlockBytes: 50)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
        }
    }

    func test_write_commentLimit_throws() {
        let bigComment = String(repeating: "c", count: 200)
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .comment(bigComment),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let limits = XMLStreamWriter.WriterLimits(maxCommentBytes: 50)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
        }
    }

    func test_write_nodeCountLimit_throws() {
        // 3 elements with maxNodeCount=2 should throw
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "A"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "B"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "C"), attributes: [], namespaceDeclarations: []),
            .endElement(name: XMLQualifiedName(localName: "C")),
            .endElement(name: XMLQualifiedName(localName: "B")),
            .endElement(name: XMLQualifiedName(localName: "A")),
            .endDocument
        ]
        let limits = XMLStreamWriter.WriterLimits(maxNodeCount: 2)
        let config = XMLStreamWriter.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamWriter(configuration: config).write(events)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
        }
    }

    func test_write_standaloneDeclaration_yes() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: true),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]
        let data = try XMLStreamWriter().write(events)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("standalone=\"yes\""), "Expected standalone='yes' in: \(str)")
    }

    // MARK: - prettyPrinted produces indented output

    func test_write_prettyPrinted_producesIndentation() throws {
        let xml = "<Root><child>hello</child></Root>"
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: Data(xml.utf8)) { events.append($0) }
        let config = XMLStreamWriter.Configuration(prettyPrinted: true)
        let data = try XMLStreamWriter(configuration: config).write(events)
        let str = String(data: data, encoding: .utf8) ?? ""
        // Pretty-printed output should contain newlines and indentation
        XCTAssertTrue(str.contains("\n"), "Expected newlines in pretty-printed output: \(str)")
    }
}
