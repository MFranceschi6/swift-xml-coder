import SwiftXMLCoder
import XCTest

final class XMLTreeModelTests: XCTestCase {
    func test_xmlQualifiedName_preservesLocalNameNamespaceAndPrefix() {
        let qName = XMLQualifiedName(
            localName: "Envelope",
            namespaceURI: "urn:soap",
            prefix: "soap"
        )

        XCTAssertEqual(qName.localName, "Envelope")
        XCTAssertEqual(qName.namespaceURI, "urn:soap")
        XCTAssertEqual(qName.prefix, "soap")
        XCTAssertEqual(qName.qualifiedName, "soap:Envelope")
    }

    func test_xmlTreeElement_preservesChildrenOrderAndNodeKinds() {
        let childElement = XMLTreeElement(name: XMLQualifiedName(localName: "Child"))
        let root = XMLTreeElement(
            name: XMLQualifiedName(localName: "Root"),
            children: [
                .text("alpha"),
                .element(childElement),
                .comment("note"),
                .cdata("payload")
            ]
        )

        XCTAssertEqual(root.children.count, 4)
        XCTAssertEqual(root.children[0], .text("alpha"))
        XCTAssertEqual(root.children[1], .element(childElement))
        XCTAssertEqual(root.children[2], .comment("note"))
        XCTAssertEqual(root.children[3], .cdata("payload"))
    }

    func test_xmlTreeElement_preservesAttributesAndNamespaceDeclarations() {
        let attribute = XMLTreeAttribute(
            name: XMLQualifiedName(localName: "id"),
            value: "123"
        )
        let defaultNamespace = XMLNamespaceDeclaration(uri: "urn:default")
        let explicitNamespace = XMLNamespaceDeclaration(prefix: "m", uri: "urn:messages")

        let element = XMLTreeElement(
            name: XMLQualifiedName(localName: "Item"),
            attributes: [attribute],
            namespaceDeclarations: [defaultNamespace, explicitNamespace]
        )

        XCTAssertEqual(element.attributes, [attribute])
        XCTAssertEqual(element.namespaceDeclarations, [defaultNamespace, explicitNamespace])
    }

    func test_xmlTreeDocument_codableRoundtrip_preservesModelAndMetadata() throws {
        let root = XMLTreeElement(
            name: XMLQualifiedName(localName: "Envelope", namespaceURI: "urn:soap", prefix: "soap"),
            attributes: [
                XMLTreeAttribute(name: XMLQualifiedName(localName: "id"), value: "abc")
            ],
            namespaceDeclarations: [
                XMLNamespaceDeclaration(uri: "urn:soap"),
                XMLNamespaceDeclaration(prefix: "m", uri: "urn:messages")
            ],
            children: [
                .text("hello"),
                .comment("stable comment"),
                .cdata("<raw/>")
            ],
            metadata: XMLNodeStructuralMetadata(sourceOrder: 1, originalPrefix: "soap", wasSelfClosing: false)
        )

        let metadata = XMLDocumentStructuralMetadata(
            xmlVersion: "1.0",
            encoding: "UTF-8",
            standalone: nil,
            canonicalization: XMLCanonicalizationMetadata(
                attributeOrderIsSignificant: true,
                namespaceOrderIsSignificant: true,
                whitespaceIsSignificant: false
            )
        )

        let document = XMLTreeDocument(root: root, metadata: metadata)

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(XMLTreeDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
    }
}
