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
}
