import SwiftXMLCoder
import XCTest

final class XMLNodeLineNumberTests: XCTestCase {
    // MARK: - lineNumber

    func test_lineNumber_returnsCorrectLineForRootElement() throws {
        let xml = "<root/>"
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))
        let root = try XCTUnwrap(document.rootElement())
        XCTAssertEqual(root.lineNumber, 1)
    }

    func test_lineNumber_returnsCorrectLineForNestedElement() throws {
        let xml = "<root>\n  <child/>\n</root>"
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))
        let child = try XCTUnwrap(document.rootElement()?.firstChild(named: "child"))
        XCTAssertEqual(child.lineNumber, 2)
    }

    func test_lineNumber_returnsCorrectLinesForSiblings() throws {
        let xml = "<root>\n<a/>\n<b/>\n<c/>\n</root>"
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))
        let root = try XCTUnwrap(document.rootElement())
        let children = root.children()

        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(children[0].lineNumber, 2)
        XCTAssertEqual(children[1].lineNumber, 3)
        XCTAssertEqual(children[2].lineNumber, 4)
    }
}
