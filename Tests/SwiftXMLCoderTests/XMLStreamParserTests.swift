import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamParserTests: XCTestCase {

    // MARK: - Helpers

    private func events(
        from xml: String,
        configuration: XMLTreeParser.Configuration = .init()
    ) throws -> [XMLStreamEvent] {
        var result: [XMLStreamEvent] = []
        let data = Data(xml.utf8)
        try XMLStreamParser(configuration: configuration).parse(data: data) { result.append($0) }
        return result
    }

    // MARK: - startDocument / endDocument

    func test_parse_startEndDocument_emitted() throws {
        let evts = try events(from: "<Root/>")
        XCTAssertEqual(evts.first, .startDocument(version: nil, encoding: nil, standalone: nil))
        XCTAssertEqual(evts.last, .endDocument)
    }

    // MARK: - Simple element

    func test_parse_simpleElement_emitsCorrectEvents() throws {
        let evts = try events(from: "<Root><child>hello</child></Root>")
        let startEvts = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        let endEvts = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .endElement(let n) = e { return n.localName }; return nil
        }
        let textEvts = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .text(let s) = e { return s }; return nil
        }

        XCTAssertEqual(startEvts, ["Root", "child"])
        XCTAssertEqual(endEvts, ["child", "Root"])
        XCTAssertEqual(textEvts, ["hello"])
    }

    // MARK: - Attributes

    func test_parse_attributes_emittedOnStartElement() throws {
        let evts = try events(from: #"<Root id="42" name="test"/>"#)
        guard case .startElement(_, let attrs, _) = evts.first(where: {
            if case .startElement = $0 { return true } else { return false }
        }) else { return XCTFail("No startElement event") }

        let attrMap = Dictionary(attrs.map { ($0.name.localName, $0.value) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(attrMap["id"], "42")
        XCTAssertEqual(attrMap["name"], "test")
    }

    // MARK: - Namespaces

    func test_parse_namespaces_emittedOnStartElement() throws {
        let xml = #"<ex:Root xmlns:ex="http://example.com/ns"><ex:child/></ex:Root>"#
        let evts = try events(from: xml)

        guard case .startElement(let name, _, let nsDecls) = evts.first(where: {
            if case .startElement = $0 { return true } else { return false }
        }) else { return XCTFail("No startElement") }

        XCTAssertEqual(name.localName, "Root")
        XCTAssertEqual(name.prefix, "ex")
        XCTAssertEqual(name.namespaceURI, "http://example.com/ns")
        XCTAssertTrue(nsDecls.contains { $0.prefix == "ex" && $0.uri == "http://example.com/ns" })
    }

    // MARK: - CDATA

    func test_parse_cdata_emittedAsCDATAEvent() throws {
        let xml = "<Root><![CDATA[hello & world]]></Root>"
        let evts = try events(from: xml)
        let cdata = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .cdata(let s) = e { return s }; return nil
        }
        XCTAssertEqual(cdata, ["hello & world"])
    }

    // MARK: - Comment

    func test_parse_comment_emittedAsCommentEvent() throws {
        let xml = "<Root><!-- a comment --></Root>"
        let evts = try events(from: xml)
        let comments = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .comment(let s) = e { return s }; return nil
        }
        XCTAssertEqual(comments, [" a comment "])
    }

    // MARK: - Processing instruction

    func test_parse_processingInstruction_emitted() throws {
        let xml = #"<?xml-stylesheet type="text/xsl" href="style.xsl"?><Root/>"#
        let evts = try events(from: xml)
        let pis = evts.compactMap { (e: XMLStreamEvent) -> (String, String?)? in
            if case .processingInstruction(let target, let data) = e { return (target, data) }; return nil
        }
        XCTAssertTrue(pis.contains { $0.0 == "xml-stylesheet" })
    }

    // MARK: - Whitespace policy

    func test_parse_whitespacePolicy_dropWhitespaceOnly() throws {
        let xml = "<Root>\n  <child>text</child>\n</Root>"
        let config = XMLTreeParser.Configuration(whitespaceTextNodePolicy: .dropWhitespaceOnly)
        let evts = try events(from: xml, configuration: config)
        let texts = evts.compactMap { (e: XMLStreamEvent) -> String? in
            if case .text(let s) = e { return s }; return nil
        }
        XCTAssertFalse(texts.contains { $0.allSatisfy { $0.isWhitespace } })
    }

    // MARK: - Security limits

    func test_parse_depthLimit_throws() {
        // Generate XML that exceeds depth 3
        let xml = "<A><B><C><D/></C></B></A>"
        let limits = XMLTreeParser.Limits(maxDepth: 3)
        let config = XMLTreeParser.Configuration(limits: limits)
        let xmlData = Data(xml.utf8)
        XCTAssertThrowsError(try XMLStreamParser(configuration: config).parse(data: xmlData) { _ in }) { error in
            guard case XMLParsingError.parseFailed(let msg) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
            XCTAssertTrue(msg?.contains("XML6_2H_MAX_DEPTH") == true || msg != nil)
        }
    }

    func test_parse_textSizeLimit_throws() {
        let bigText = String(repeating: "x", count: 200)
        let xml = "<Root>\(bigText)</Root>"
        let limits = XMLTreeParser.Limits(maxTextNodeBytes: 100)
        let config = XMLTreeParser.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamParser(configuration: config).parse(data: Data(xml.utf8)) { _ in }) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    func test_parse_inputSizeLimit_throws() {
        let xml = "<Root><child>hello</child></Root>"
        let limits = XMLTreeParser.Limits(maxInputBytes: 10)
        let config = XMLTreeParser.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamParser(configuration: config).parse(data: Data(xml.utf8)) { _ in }) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    func test_parse_commentSizeLimit_throws() {
        let bigComment = String(repeating: "x", count: 300)
        let xml = "<Root><!--\(bigComment)--></Root>"
        let limits = XMLTreeParser.Limits(maxCommentBytes: 100)
        let config = XMLTreeParser.Configuration(limits: limits)
        XCTAssertThrowsError(try XMLStreamParser(configuration: config).parse(data: Data(xml.utf8)) { _ in }) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Invalid XML

    func test_parse_invalidXML_throws() {
        let xml = "<Root><unclosed>"
        XCTAssertThrowsError(try XMLStreamParser().parse(data: Data(xml.utf8)) { _ in }) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Event ordering

    func test_parse_eventOrdering_startBeforeEnd() throws {
        let evts = try events(from: "<A><B/></A>")
        var depth = 0
        for event in evts {
            switch event {
            case .startElement:
                depth += 1
            case .endElement:
                depth -= 1
                XCTAssertGreaterThanOrEqual(depth, 0, "endElement before startElement")
            default:
                break
            }
        }
        XCTAssertEqual(depth, 0, "Unbalanced start/end elements")
    }

    // MARK: - Round-trip against XMLTreeParser

    func test_parse_roundTrip_matchesXMLTreeParser() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Catalog xmlns:dc="http://purl.org/dc/elements/1.1/">
          <item id="1">
            <dc:title>Widget</dc:title>
            <price currency="USD">9.99</price>
          </item>
        </Catalog>
        """
        let data = Data(xml.utf8)
        let config = XMLTreeParser.Configuration(whitespaceTextNodePolicy: .dropWhitespaceOnly)

        // Tree parser: collect element names in DFS order
        let treeDoc = try XMLTreeParser(configuration: config).parse(data: data)
        var treeNames: [String] = []
        func walk(_ el: XMLTreeElement) {
            treeNames.append(el.name.localName)
            for child in el.children {
                if case .element(let sub) = child { walk(sub) }
            }
        }
        walk(treeDoc.root)

        // Stream parser: collect startElement names
        var streamNames: [String] = []
        try XMLStreamParser(configuration: config).parse(data: data) { event in
            if case .startElement(let n, _, _) = event { streamNames.append(n.localName) }
        }

        XCTAssertEqual(treeNames, streamNames)
    }

    // MARK: - Async API

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_parse_async_emitsCorrectEvents() async throws {
        let xml = "<Root><child>hello</child></Root>"
        let data = Data(xml.utf8)
        var collected: [XMLStreamEvent] = []
        for try await event in XMLStreamParser().events(for: data) {
            collected.append(event)
        }
        let startEvts = collected.compactMap { (e: XMLStreamEvent) -> String? in
            if case .startElement(let n, _, _) = e { return n.localName }; return nil
        }
        XCTAssertEqual(startEvts, ["Root", "child"])
    }
}
