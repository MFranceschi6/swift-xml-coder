import Foundation
@testable import SwiftXMLCoder
import XCTest

final class XMLSAXDecoderTests: XCTestCase {

    private func makeBuffer(_ events: [XMLStreamEvent], _ lines: [Int?]? = nil) -> _XMLEventBuffer {
        let lineValues = lines ?? Array(repeating: nil, count: events.count)
        return _XMLEventBuffer(
            events: ContiguousArray(events),
            lineNumbers: ContiguousArray(lineValues)
        )
    }

    func test_eventBuffer_findRootElement_returnsRootSpan() throws {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .comment("before"),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .endElement(name: childName),
            .endElement(name: rootName),
            .endDocument
        ]
        let buffer = makeBuffer(events)
        let root = try buffer.findRootElement()
        XCTAssertEqual(root.start, 2)
        XCTAssertEqual(root.end, 5)
    }

    func test_eventBuffer_childElementSpans_returnsDirectChildrenOnly() {
        let rootName = XMLQualifiedName(localName: "Root")
        let aName = XMLQualifiedName(localName: "A")
        let bName = XMLQualifiedName(localName: "B")
        let nestedName = XMLQualifiedName(localName: "Nested")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []), // 1
            .startElement(name: aName, attributes: [], namespaceDeclarations: []),    // 2
            .startElement(name: nestedName, attributes: [], namespaceDeclarations: []), // 3
            .endElement(name: nestedName),                                             // 4
            .endElement(name: aName),                                                  // 5
            .startElement(name: bName, attributes: [], namespaceDeclarations: []),     // 6
            .endElement(name: bName),                                                  // 7
            .endElement(name: rootName),                                               // 8
            .endDocument
        ]
        let buffer = makeBuffer(events)
        let spans = buffer.childElementSpans(from: 1, to: 8)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].name.localName, "A")
        XCTAssertEqual(spans[0].start, 2)
        XCTAssertEqual(spans[0].end, 5)
        XCTAssertEqual(spans[1].name.localName, "B")
        XCTAssertEqual(spans[1].start, 6)
        XCTAssertEqual(spans[1].end, 7)
    }

    func test_eventBuffer_lexicalText_concatenatesDirectTextAndCDATA() {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []), // 1
            .text(" hello "),
            .cdata("world"),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .text("ignored"),
            .endElement(name: childName),
            .text(" !"),
            .endElement(name: rootName), // 8
            .endDocument
        ]
        let buffer = makeBuffer(events)
        XCTAssertEqual(buffer.lexicalText(from: 1, to: 8), " hello world !")
    }

    func test_eventBuffer_isNilSpan_trueOnlyWhenNoChildrenAndNoLexicalContent() {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")

        let emptyEvents: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .text("   \n"),
            .endElement(name: rootName),
            .endDocument
        ]
        XCTAssertTrue(makeBuffer(emptyEvents).isNilSpan(from: 1, to: 3))

        let withChildEvents: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .endElement(name: childName),
            .endElement(name: rootName),
            .endDocument
        ]
        XCTAssertFalse(makeBuffer(withChildEvents).isNilSpan(from: 1, to: 4))
    }

    func test_eventBuffer_lineNumberAt_returnsStoredLine() {
        let rootName = XMLQualifiedName(localName: "Root")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .endElement(name: rootName),
            .endDocument
        ]
        let lines: [Int?] = [nil, 12, 12, nil]
        let buffer = makeBuffer(events, lines)
        XCTAssertEqual(buffer.lineNumberAt(1), 12)
        XCTAssertEqual(buffer.lineNumberAt(2), 12)
        XCTAssertNil(buffer.lineNumberAt(0))
        XCTAssertNil(buffer.lineNumberAt(99))
    }

    func test_eventBuffer_makeTreeDocument_preservesSourceLineMetadata() throws {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .text("value"),
            .endElement(name: childName),
            .endElement(name: rootName),
            .endDocument
        ]
        let lines: [Int?] = [nil, 2, 3, 3, 3, 2, nil]
        let doc = try makeBuffer(events, lines).makeTreeDocument()

        XCTAssertEqual(doc.root.name.localName, "Root")
        XCTAssertEqual(doc.root.metadata.sourceLine, 2)
        guard case .element(let child) = try XCTUnwrap(doc.root.children.first) else {
            return XCTFail("Expected first child element")
        }
        XCTAssertEqual(child.name.localName, "Child")
        XCTAssertEqual(child.metadata.sourceLine, 3)
    }
}
