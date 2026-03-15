import Foundation
import SwiftXMLCoder
import XCTest

final class XMLDocumentXPathTests: XCTestCase {
    func test_xpathFirstNode_withNamespaces_returnsExpectedNode() throws {
        let xml = """
        <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/">
          <wsdl:service name="ExampleService"/>
        </wsdl:definitions>
        """
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))

        let node = try document.xpathFirstNode("/wsdl:definitions/wsdl:service", namespaces: [
            "wsdl": "http://schemas.xmlsoap.org/wsdl/"
        ])

        XCTAssertEqual(node?.name, "service")
        XCTAssertEqual(node?.attribute(named: "name"), "ExampleService")
    }

    func test_serializedData_roundTrips() throws {
        let xml = """
        <root><child>Hello</child></root>
        """
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))
        let serialized = try document.serializedData(prettyPrinted: false)
        let roundTripped = try SwiftXMLCoder.XMLDocument(data: serialized)

        XCTAssertEqual(roundTripped.rootElement()?.name, "root")
        let child = try roundTripped.xpathFirstNode("/root/child")
        XCTAssertEqual(child?.text(), "Hello")
    }

    func test_xpathNodes_withNamespaces_returnsAllMatchingNodes() throws {
        let xml = """
        <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/">
          <wsdl:service name="One"/>
          <wsdl:service name="Two"/>
        </wsdl:definitions>
        """
        let document = try SwiftXMLCoder.XMLDocument(data: Data(xml.utf8))

        let nodes = try document.xpathNodes("/wsdl:definitions/wsdl:service", namespaces: [
            "wsdl": "http://schemas.xmlsoap.org/wsdl/"
        ])

        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].attribute(named: "name"), "One")
        XCTAssertEqual(nodes[1].attribute(named: "name"), "Two")
    }

    func test_builder_createsEnvelopeWithNamespacesAndBodyText() throws {
        let soapNamespace = XMLNamespace(prefix: "soap", uri: "http://schemas.xmlsoap.org/soap/envelope/")
        let document = try SwiftXMLCoder.XMLDocument(rootElementName: "Envelope", rootNamespace: soapNamespace)

        guard let root = document.rootElement() else {
            return XCTFail("Expected a root node.")
        }

        XCTAssertEqual(root.name, "Envelope")
        XCTAssertEqual(root.namespacePrefix, "soap")
        XCTAssertEqual(root.namespaceURI, "http://schemas.xmlsoap.org/soap/envelope/")

        let body = try document.createElement(named: "Body", namespace: soapNamespace)
        try document.appendChild(body, to: root)

        let message = try document.createElement(named: "GetWeather")
        try message.setAttribute(named: "city", value: "Rome")
        message.setText("payload")
        try document.appendChild(message, to: body)

        let serializedData = try document.serializedData(prettyPrinted: false)
        let parsedDocument = try SwiftXMLCoder.XMLDocument(data: serializedData)

        let parsedMessage = try parsedDocument.xpathFirstNode(
            "/soap:Envelope/soap:Body/GetWeather",
            namespaces: ["soap": "http://schemas.xmlsoap.org/soap/envelope/"]
        )
        XCTAssertEqual(parsedMessage?.attribute(named: "city"), "Rome")
        XCTAssertEqual(parsedMessage?.text(), "payload")
    }

    func test_builder_withNamespacePrefixWithoutURI_throwsError() throws {
        XCTAssertThrowsError(
            try SwiftXMLCoder.XMLDocument(
                rootElementName: "Envelope",
                rootNamespace: XMLNamespace(prefix: "soap", uri: " ")
            )
        ) { error in
            guard case XMLParsingError.invalidNamespaceConfiguration = error else {
                return XCTFail("Expected invalidNamespaceConfiguration, got: \(error)")
            }
        }
    }
}
