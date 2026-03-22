import Foundation
import Logging
import SwiftXMLCoder
import XCTest

final class XMLDocumentCoverageTests: XCTestCase {
    private struct TestLogHandler: LogHandler {
        var logLevel: Logger.Level = .trace
        var metadata: Logger.Metadata = [:]

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        // swiftlint:disable:next function_parameter_count
        func log(
            level: Logger.Level,
            message: Logger.Message,
            metadata: Logger.Metadata?,
            source: String,
            file: String,
            function: String,
            line: UInt
        ) {}
    }

    private func makeLogger(level: Logger.Level) -> Logger {
        var logger = Logger(label: "test.logger") { _ in
            TestLogHandler()
        }
        logger.logLevel = level
        return logger
    }

    func test_initData_withURL_parsesSuccessfully() throws {
        let xml = "<root><item id=\"1\">value</item></root>"
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/schema.xml"))
        let document = try SwiftXMLCoder.XMLDocument(
            data: Data(xml.utf8),
            sourceURL: sourceURL
        )

        let item = try document.xpathFirstNode("/root/item")
        XCTAssertEqual(item?.attribute(named: "id"), "1")
    }

    func test_initURL_loadsDataAndParsesSuccessfully() throws {
        let xml = "<root><item id=\"2\">local</item></root>"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftsoapxml-test-\(UUID().uuidString).xml")
        try Data(xml.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let document = try SwiftXMLCoder.XMLDocument(url: fileURL)
        let item = try document.xpathFirstNode("/root/item")
        XCTAssertEqual(item?.attribute(named: "id"), "2")
    }

    func test_initData_withInvalidXML_throwsParseFailed() {
        let invalidXML = "<root><child></root>"

        let logger = makeLogger(level: .debug)

        XCTAssertThrowsError(try SwiftXMLCoder.XMLDocument(data: Data(invalidXML.utf8), logger: logger)) { error in
            guard case XMLParsingError.parseFailed = error else {
                return XCTFail("Expected parseFailed, got: \(error)")
            }
        }
    }

    func test_xpathFirstNode_invalidExpression_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(
            data: Data("<root/>".utf8),
            logger: makeLogger(level: .trace)
        )

        XCTAssertThrowsError(try document.xpathFirstNode("//*[", namespaces: [:])) { error in
            guard case XMLParsingError.xpathFailed = error else {
                return XCTFail("Expected xpathFailed, got: \(error)")
            }
        }
    }

    func test_xpathNodes_invalidExpression_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root/>".utf8))

        XCTAssertThrowsError(try document.xpathNodes("//*[", namespaces: [:])) { error in
            guard case XMLParsingError.xpathFailed = error else {
                return XCTFail("Expected xpathFailed, got: \(error)")
            }
        }
    }

    func test_xpath_noMatch_returnsNilAndEmptyArray() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root><item/></root>".utf8))

        let firstNode = try document.xpathFirstNode("/root/missing")
        let nodes = try document.xpathNodes("/root/missing")

        XCTAssertNil(firstNode)
        XCTAssertTrue(nodes.isEmpty)
    }

    func test_xpath_nonNodeSetExpression_returnsEmptyResults() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root><item/></root>".utf8))

        let firstNode = try document.xpathFirstNode("count(/root/item)")
        let nodes = try document.xpathNodes("string(/root/item/@missing)")

        XCTAssertNil(firstNode)
        XCTAssertTrue(nodes.isEmpty)
    }

    func test_xpath_withInvalidNamespacePrefix_throws() throws {
        let xml = "<soap:Envelope xmlns:soap=\"urn:soap\"/>"
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))

        XCTAssertThrowsError(try document.xpathFirstNode("/soap:Envelope", namespaces: ["": "urn:soap"])) { error in
            guard case XMLParsingError.xpathFailed = error else {
                return XCTFail("Expected xpathFailed, got: \(error)")
            }
        }
    }

    func test_serializedData_prettyPrinted_containsNewline() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root><child>v</child></root>".utf8))
        let serialized = try document.serializedData(prettyPrinted: true)
        let string = String(data: serialized, encoding: .utf8) ?? ""

        XCTAssertTrue(string.contains("\n"))
    }

    func test_serializedData_withInvalidEncoding_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root/>".utf8))

        XCTAssertThrowsError(try document.serializedData(encoding: "NOT-A-REAL-ENCODING")) { error in
            guard case XMLParsingError.other = error else {
                return XCTFail("Expected other error, got: \(error)")
            }
        }
    }

    func test_nodeChildrenAndFirstChild_coverHelpers() throws {
        let document = try SwiftXMLCoder.XMLDocument(data: Data("<root><a>1</a><b id=\"x\"/></root>".utf8))
        let root = try XCTUnwrap(document.rootElement())

        let children = root.children()
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.first?.name, "a")
        XCTAssertEqual(root.firstChild(named: "b")?.attribute(named: "id"), "x")
        XCTAssertNil(root.firstChild(named: "missing"))
        XCTAssertNil(root.attribute(named: "missing"))
        XCTAssertNil(root.namespacePrefix)
        XCTAssertNil(root.namespaceURI)
    }

    func test_addNamespace_successAndLookup() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Envelope")
        let root = try XCTUnwrap(document.rootElement())

        try root.addNamespace(SwiftXMLCoder.XMLNamespace(prefix: "soap", uri: "urn:soap"))

        XCTAssertEqual(root.namespacePrefix, "soap")
        XCTAssertEqual(root.namespaceURI, "urn:soap")
    }

    func test_addNamespace_invalidConfiguration_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Envelope")
        let root = try XCTUnwrap(document.rootElement())

        XCTAssertThrowsError(try root.addNamespace(SwiftXMLCoder.XMLNamespace(prefix: "soap", uri: " "))) { error in
            guard case XMLParsingError.invalidNamespaceConfiguration = error else {
                return XCTFail("Expected invalidNamespaceConfiguration, got: \(error)")
            }
        }
    }

    func test_addChild_fromDifferentDocuments_throws() throws {
        let first = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let second = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")

        let parent = try XCTUnwrap(first.rootElement())
        let child = try XCTUnwrap(second.rootElement())

        XCTAssertThrowsError(try first.appendChild(child, to: parent)) { error in
            guard case XMLParsingError.nodeOperationFailed = error else {
                return XCTFail("Expected nodeOperationFailed, got: \(error)")
            }
        }
    }

    func test_addChild_invalidOperation_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let root = try XCTUnwrap(document.rootElement())

        XCTAssertThrowsError(try root.addChild(root)) { error in
            guard case XMLParsingError.nodeOperationFailed = error else {
                return XCTFail("Expected nodeOperationFailed, got: \(error)")
            }
        }
    }

    func test_xmlNamespace_trimsEmptyPrefix() {
        let namespace = SwiftXMLCoder.XMLNamespace(prefix: "   ", uri: "urn:test")
        XCTAssertNil(namespace.prefix)
        XCTAssertEqual(namespace.uri, "urn:test")
    }

    func test_builder_withDefaultNamespace_setsNamespaceURIWithoutPrefix() throws {
        let document = try SwiftXMLCoder.XMLDocument(
            rootElementName: "Envelope",
            rootNamespace: SwiftXMLCoder.XMLNamespace(uri: "urn:default")
        )
        let root = try XCTUnwrap(document.rootElement())

        XCTAssertNil(root.namespacePrefix)
        XCTAssertEqual(root.namespaceURI, "urn:default")
    }

    func test_addNamespace_withDefaultNamespace_succeeds() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Envelope")
        let root = try XCTUnwrap(document.rootElement())

        try root.addNamespace(SwiftXMLCoder.XMLNamespace(uri: "urn:default"))

        XCTAssertNil(root.namespacePrefix)
        XCTAssertEqual(root.namespaceURI, "urn:default")
    }

    // MARK: - XMLNode additional coverage

    func test_addChild_ancestorCycle_throws() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let root = try XCTUnwrap(document.rootElement())
        let child = try document.createElement(named: "Child")
        try document.appendChild(child, to: root)

        // Appending root (an ancestor) to its own child must throw a cycle error
        XCTAssertThrowsError(try child.addChild(root)) { error in
            guard case XMLParsingError.nodeOperationFailed = error else {
                return XCTFail("Expected nodeOperationFailed, got: \(error)")
            }
        }
    }

    func test_setAndGetText_roundTrips() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let root = try XCTUnwrap(document.rootElement())
        root.setText("hello")
        XCTAssertEqual(root.text(), "hello")
    }

    func test_namespaceDeclarationsInScope_walksAncestors() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let root = try XCTUnwrap(document.rootElement())
        try root.addNamespace(SwiftXMLCoder.XMLNamespace(prefix: "outer", uri: "urn:outer"))

        let child = try document.createElement(named: "Child")
        try document.appendChild(child, to: root)
        try child.addNamespace(SwiftXMLCoder.XMLNamespace(prefix: "inner", uri: "urn:inner"))

        let scopedDecls = child.namespaceDeclarationsInScope()
        XCTAssertEqual(scopedDecls["outer"], "urn:outer", "Outer namespace must be visible from child scope")
        XCTAssertEqual(scopedDecls["inner"], "urn:inner", "Inner namespace must be in child scope")

        let rootDecls = root.namespaceDeclarationsInScope()
        XCTAssertNil(rootDecls["inner"], "Child namespace must not be visible in root scope")
    }

    func test_parent_returnsParentElement() throws {
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Root")
        let root = try XCTUnwrap(document.rootElement())
        let child = try document.createElement(named: "Child")
        try document.appendChild(child, to: root)

        let parentNode = child.parent()
        XCTAssertEqual(parentNode?.name, "Root")
        XCTAssertNil(root.parent(), "Root element has no element parent")
    }

    // MARK: - XMLParsingError Equatable

    func test_xmlParsingError_equatable_sameCase_equal() {
        XCTAssertEqual(XMLParsingError.invalidUTF8, .invalidUTF8)
        XCTAssertEqual(XMLParsingError.parseFailed(message: "msg"), .parseFailed(message: "msg"))
        XCTAssertEqual(XMLParsingError.parseFailed(message: nil), .parseFailed(message: nil))
        XCTAssertEqual(
            XMLParsingError.xpathFailed(expression: "//x", message: "oops"),
            .xpathFailed(expression: "//x", message: "oops")
        )
        XCTAssertEqual(XMLParsingError.documentCreationFailed(message: "d"), .documentCreationFailed(message: "d"))
        XCTAssertEqual(
            XMLParsingError.nodeCreationFailed(name: "el", message: "n"),
            .nodeCreationFailed(name: "el", message: "n")
        )
        XCTAssertEqual(
            XMLParsingError.invalidNamespaceConfiguration(prefix: "ns", uri: "urn:x"),
            .invalidNamespaceConfiguration(prefix: "ns", uri: "urn:x")
        )
        XCTAssertEqual(XMLParsingError.nodeOperationFailed(message: "op"), .nodeOperationFailed(message: "op"))
    }

    func test_xmlParsingError_equatable_differentCases_notEqual() {
        XCTAssertNotEqual(XMLParsingError.invalidUTF8, .parseFailed(message: nil))
        XCTAssertNotEqual(XMLParsingError.parseFailed(message: "a"), .parseFailed(message: "b"))
    }

    func test_xmlParsingError_other_neverEqual() {
        let lhs = XMLParsingError.other(underlyingError: nil, message: "x")
        let rhs = XMLParsingError.other(underlyingError: nil, message: "x")
        XCTAssertNotEqual(lhs, rhs)
    }

    // MARK: - XMLDateFormatHint encodingStrategy / decodingStrategy

    func test_xmlDateFormatHint_encodingStrategy_allCases() {
        let hints: [XMLDateFormatHint] = [
            .xsdDateTime, .xsdDate, .xsdDateWithTimezone(identifier: "Europe/Rome"),
            .xsdTime, .xsdTimeWithTimezone(identifier: "America/New_York"),
            .xsdGYear, .xsdGYearMonth, .xsdGMonth, .xsdGDay, .xsdGMonthDay,
            .secondsSince1970, .millisecondsSince1970
        ]
        for hint in hints {
            _ = hint.encodingStrategy
            _ = hint.decodingStrategy
        }
    }

    func test_xmlDateFormatHint_equatable_hashable() {
        XCTAssertEqual(XMLDateFormatHint.xsdDate, .xsdDate)
        XCTAssertNotEqual(XMLDateFormatHint.xsdDate, .xsdTime)
        var seen = Set<XMLDateFormatHint>()
        seen.insert(.xsdDate)
        seen.insert(.xsdDate)
        XCTAssertEqual(seen.count, 1)
    }
}
