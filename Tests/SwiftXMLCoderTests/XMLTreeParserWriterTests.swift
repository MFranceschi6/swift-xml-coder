import Foundation
import SwiftXMLCoder
import XCTest

final class XMLTreeParserWriterTests: XCTestCase {
    func test_parser_parsesMixedNodesAttributesAndNamespaces() throws {
        let xml = """
        <soap:Envelope xmlns:soap="urn:soap" xmlns:m="urn:messages" id="env">
          <!--metadata-->
          <soap:Body m:flag="true"><![CDATA[<payload/>]]><m:Echo>hello</m:Echo></soap:Body>
        </soap:Envelope>
        """

        let parser = XMLTreeParser()
        let document = try parser.parse(data: Data(xml.utf8))

        XCTAssertEqual(document.root.name.localName, "Envelope")
        XCTAssertEqual(document.root.name.namespaceURI, "urn:soap")
        XCTAssertEqual(document.root.name.prefix, "soap")
        XCTAssertEqual(document.root.attributes.count, 1)
        XCTAssertEqual(document.root.attributes[0].name.localName, "id")
        XCTAssertEqual(document.root.attributes[0].value, "env")
        XCTAssertEqual(document.root.namespaceDeclarations.count, 2)

        XCTAssertEqual(document.root.children.count, 2)
        guard case .comment("metadata") = document.root.children[0] else {
            return XCTFail("Expected first root child to be XML comment.")
        }

        guard case .element(let bodyElement) = document.root.children[1] else {
            return XCTFail("Expected second root child to be body element.")
        }

        XCTAssertEqual(bodyElement.name.localName, "Body")
        XCTAssertEqual(bodyElement.name.namespaceURI, "urn:soap")
        XCTAssertEqual(bodyElement.attributes.count, 1)
        XCTAssertEqual(bodyElement.attributes[0].name.localName, "flag")
        XCTAssertEqual(bodyElement.attributes[0].name.namespaceURI, "urn:messages")
        XCTAssertEqual(bodyElement.attributes[0].name.prefix, "m")
        XCTAssertEqual(bodyElement.attributes[0].value, "true")

        XCTAssertEqual(bodyElement.children.count, 2)
        guard case .cdata("<payload/>") = bodyElement.children[0] else {
            return XCTFail("Expected first body child to be CDATA.")
        }

        guard case .element(let echoElement) = bodyElement.children[1] else {
            return XCTFail("Expected second body child to be echo element.")
        }

        XCTAssertEqual(echoElement.name.localName, "Echo")
        XCTAssertEqual(echoElement.name.namespaceURI, "urn:messages")
        XCTAssertEqual(echoElement.name.prefix, "m")
        XCTAssertEqual(echoElement.children.count, 1)
        XCTAssertEqual(echoElement.children[0], .text("hello"))
    }

    func test_writer_generatesXMLDocumentWithElementTextCDATAAndComment() throws {
        let echoElement = XMLTreeElement(
            name: XMLQualifiedName(localName: "Echo", namespaceURI: "urn:messages", prefix: "m"),
            children: [
                .text("hello")
            ]
        )
        let bodyElement = XMLTreeElement(
            name: XMLQualifiedName(localName: "Body", namespaceURI: "urn:soap", prefix: "soap"),
            attributes: [
                XMLTreeAttribute(
                    name: XMLQualifiedName(localName: "flag", namespaceURI: "urn:messages", prefix: "m"),
                    value: "true"
                )
            ],
            children: [
                .cdata("<payload/>"),
                .element(echoElement)
            ]
        )
        let root = XMLTreeElement(
            name: XMLQualifiedName(localName: "Envelope", namespaceURI: "urn:soap", prefix: "soap"),
            attributes: [
                XMLTreeAttribute(name: XMLQualifiedName(localName: "id"), value: "env")
            ],
            namespaceDeclarations: [
                XMLNamespaceDeclaration(prefix: "soap", uri: "urn:soap"),
                XMLNamespaceDeclaration(prefix: "m", uri: "urn:messages")
            ],
            children: [
                .comment("metadata"),
                .element(bodyElement)
            ]
        )
        let treeDocument = XMLTreeDocument(root: root)

        let writer = XMLTreeWriter(configuration: .init(prettyPrinted: false))
        let parser = XMLTreeParser()

        let xmlData = try writer.writeData(treeDocument)
        let roundtripTree = try parser.parse(data: xmlData)

        XCTAssertEqual(roundtripTree.root.name.localName, "Envelope")
        XCTAssertEqual(roundtripTree.root.name.namespaceURI, "urn:soap")
        XCTAssertEqual(roundtripTree.root.attributes.count, 1)
        XCTAssertEqual(roundtripTree.root.attributes[0].name.localName, "id")
        XCTAssertEqual(roundtripTree.root.attributes[0].value, "env")
        XCTAssertEqual(roundtripTree.root.children.count, 2)

        guard case .comment("metadata") = roundtripTree.root.children[0] else {
            return XCTFail("Expected first root child to be XML comment.")
        }

        guard case .element(let parsedBody) = roundtripTree.root.children[1] else {
            return XCTFail("Expected second root child to be body element.")
        }
        XCTAssertEqual(parsedBody.attributes.count, 1)
        XCTAssertEqual(parsedBody.attributes[0].name.localName, "flag")
        XCTAssertEqual(parsedBody.attributes[0].name.namespaceURI, "urn:messages")
        XCTAssertEqual(parsedBody.attributes[0].value, "true")
        XCTAssertEqual(parsedBody.children.count, 2)
        XCTAssertEqual(parsedBody.children[0], .cdata("<payload/>"))
    }

    func test_writer_and_parser_workThroughXMLDocumentBoundary() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("value")]
            )
        )
        let writer = XMLTreeWriter()
        let parser = XMLTreeParser()

        let xmlDocument = try writer.writeDocument(treeDocument)
        let parsedTree = try parser.parse(document: xmlDocument)

        XCTAssertEqual(parsedTree.root.name.localName, "Root")
        XCTAssertEqual(parsedTree.root.children, [.text("value")])
    }

    func test_writer_prettyPrinted_outputsReadableFormatting() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [
                    .element(XMLTreeElement(name: XMLQualifiedName(localName: "Child"), children: [.text("value")]))
                ]
            )
        )

        let prettyWriter = XMLTreeWriter(configuration: .init(prettyPrinted: true))
        let compactWriter = XMLTreeWriter(configuration: .init(prettyPrinted: false))

        let prettyXML = try prettyWriter.writeData(treeDocument)
        let compactXML = try compactWriter.writeData(treeDocument)

        let prettyXMLString = String(bytes: prettyXML, encoding: .utf8)
        XCTAssertTrue(prettyXMLString?.contains("\n") == true)
        XCTAssertTrue(prettyXML.count >= compactXML.count)
    }

    func test_writer_deterministicSerialization_stableSortsAttributesAndNamespaces() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(name: XMLQualifiedName(localName: "z"), value: "1"),
                    XMLTreeAttribute(name: XMLQualifiedName(localName: "a"), value: "2"),
                    XMLTreeAttribute(name: XMLQualifiedName(localName: "m"), value: "3")
                ],
                namespaceDeclarations: [
                    XMLNamespaceDeclaration(prefix: "z", uri: "urn:z"),
                    XMLNamespaceDeclaration(prefix: nil, uri: "urn:default"),
                    XMLNamespaceDeclaration(prefix: "a", uri: "urn:a")
                ]
            )
        )

        let writer = XMLTreeWriter(
            configuration: .init(
                deterministicSerializationMode: .stable
            )
        )
        let parser = XMLTreeParser()

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)

        XCTAssertEqual(parsed.root.attributes.map(\.name.localName), ["a", "m", "z"])
        XCTAssertEqual(parsed.root.namespaceDeclarations.map { $0.prefix ?? "" }, ["", "a", "z"])
    }

    func test_writer_whitespaceTextPolicy_normalizeAndTrim_normalizesTextNodes() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("  hello \n  world   ")]
            )
        )

        let writer = XMLTreeWriter(
            configuration: .init(
                whitespaceTextNodePolicy: .normalizeAndTrim
            )
        )
        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .preserve))

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)
        XCTAssertEqual(parsed.root.children, [.text("hello world")])
    }

    func test_parser_whitespacePolicy_trim_trimsAndDropsEmptyTextNodes() throws {
        let xml = """
        <Root>
            <Value>   keep me   </Value>
            <Blank>   </Blank>
        </Root>
        """

        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .trim))
        let document = try parser.parse(data: Data(xml.utf8))

        guard case .element(let valueElement) = document.root.children[0] else {
            return XCTFail("Expected first child element.")
        }
        XCTAssertEqual(valueElement.children, [.text("keep me")])

        guard case .element(let blankElement) = document.root.children[1] else {
            return XCTFail("Expected second child element.")
        }
        XCTAssertTrue(blankElement.children.isEmpty)
    }

    // MARK: - Coverage: writer whitespace policies

    func test_writer_omitWhitespaceOnly_skipsWhitespaceOnlyTextNodes() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [
                    .text("   \n   "),          // whitespace-only → must be omitted
                    .element(XMLTreeElement(
                        name: XMLQualifiedName(localName: "Item"),
                        children: [.text("hello")]
                    )),
                    .text("  ")                  // whitespace-only → must be omitted
                ]
            )
        )

        let writer = XMLTreeWriter(configuration: .init(whitespaceTextNodePolicy: .omitWhitespaceOnly))
        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .preserve))

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)

        XCTAssertEqual(parsed.root.children.count, 1)
        if case .element(let item) = parsed.root.children[0] {
            XCTAssertEqual(item.name.localName, "Item")
        } else {
            XCTFail("Expected element child.")
        }
    }

    func test_writer_omitWhitespaceOnly_nonWhitespaceTextIsPreserved() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("  actual content  ")]
            )
        )

        let writer = XMLTreeWriter(configuration: .init(whitespaceTextNodePolicy: .omitWhitespaceOnly))
        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .preserve))

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)
        XCTAssertEqual(parsed.root.children, [.text("  actual content  ")])
    }

    func test_writer_trim_trimsBothSidesOfTextNodes() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("  trimmed value  ")]
            )
        )

        let writer = XMLTreeWriter(configuration: .init(whitespaceTextNodePolicy: .trim))
        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .preserve))

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)
        XCTAssertEqual(parsed.root.children, [.text("trimmed value")])
    }

    // MARK: - Coverage: writer namespaced attributes

    func test_writer_namespacedAttribute_withPrefixAndDeclaredNamespace_writesCorrectly() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(
                        name: XMLQualifiedName(localName: "id", namespaceURI: "urn:attrs", prefix: "a"),
                        value: "123"
                    )
                ],
                namespaceDeclarations: [XMLNamespaceDeclaration(prefix: "a", uri: "urn:attrs")]
            )
        )

        let writer = XMLTreeWriter(configuration: .init(namespaceValidationMode: .synthesizeMissingDeclarations))
        let parser = XMLTreeParser()

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)

        XCTAssertEqual(parsed.root.attributes.first?.value, "123")
        XCTAssertEqual(parsed.root.attributes.first?.name.localName, "id")
    }

    func test_writer_namespacedAttribute_withoutPrefix_synthesizesNamespace() throws {
        let treeDocument = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(
                        name: XMLQualifiedName(localName: "id", namespaceURI: "urn:attrs"),
                        value: "456"
                    )
                ]
            )
        )

        let writer = XMLTreeWriter(configuration: .init(namespaceValidationMode: .synthesizeMissingDeclarations))
        let parser = XMLTreeParser()

        let data = try writer.writeData(treeDocument)
        let parsed = try parser.parse(data: data)

        XCTAssertEqual(parsed.root.attributes.first?.value, "456")
        XCTAssertEqual(parsed.root.attributes.first?.name.localName, "id")
    }
}
