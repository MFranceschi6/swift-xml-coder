import Foundation
import SwiftXMLCoder
import XCTest

final class XMLCanonicalizerTests: XCTestCase {
    func test_canonicalize_semanticallyEquivalentInputs_produceSameCanonicalData() throws {
        let xmlA = """
        <Root xmlns:b="urn:b" xmlns:a="urn:a" z="1" a="2"><a:Child><![CDATA[payload]]></a:Child></Root>
        """
        let xmlB = """
        <Root a="2" z="1" xmlns:a="urn:a" xmlns:b="urn:b"><a:Child>payload</a:Child></Root>
        """

        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .trim))
        let canonicalizer = XMLDefaultCanonicalizer()
        let options = XMLCanonicalizationOptions(
            attributeOrderingPolicy: .lexicographical,
            namespaceDeclarationOrderingPolicy: .lexicographical,
            whitespaceTextNodePolicy: .normalizeAndTrim,
            deterministicSerializationMode: .stable,
            includeComments: false,
            convertCDATAIntoText: true
        )

        let documentA = try parser.parse(data: Data(xmlA.utf8))
        let documentB = try parser.parse(data: Data(xmlB.utf8))
        let canonicalA = try canonicalizer.canonicalize(documentA, options: options)
        let canonicalB = try canonicalizer.canonicalize(documentB, options: options)

        XCTAssertEqual(canonicalA, canonicalB)
    }

    func test_canonicalize_includeComments_false_removesComments() throws {
        let xml = "<Root><!--note--><Value>42</Value></Root>"
        let parser = XMLTreeParser()
        let canonicalizer = XMLDefaultCanonicalizer()
        let options = XMLCanonicalizationOptions(includeComments: false)

        let document = try parser.parse(data: Data(xml.utf8))
        let canonicalData = try canonicalizer.canonicalize(document, options: options)
        let canonicalTree = try parser.parse(data: canonicalData)

        let comments = canonicalTree.root.children.filter {
            if case .comment = $0 {
                return true
            }
            return false
        }
        XCTAssertTrue(comments.isEmpty)
    }

    func test_canonicalize_appliesCustomTransformPipeline() throws {
        struct AddAuditAttributeTransform: XMLTransform {
            func apply(
                to document: XMLTreeDocument,
                options _: XMLCanonicalizationOptions
            ) throws -> XMLTreeDocument {
                let attribute = XMLTreeAttribute(
                    name: XMLQualifiedName(localName: "audit"),
                    value: "1"
                )
                let root = XMLTreeElement(
                    name: document.root.name,
                    attributes: document.root.attributes + [attribute],
                    namespaceDeclarations: document.root.namespaceDeclarations,
                    children: document.root.children,
                    metadata: document.root.metadata
                )
                return XMLTreeDocument(root: root, metadata: document.metadata)
            }
        }

        let xml = "<Root><Value>42</Value></Root>"
        let parser = XMLTreeParser()
        let canonicalizer = XMLDefaultCanonicalizer()
        let document = try parser.parse(data: Data(xml.utf8))
        let canonicalData = try canonicalizer.canonicalize(
            document,
            options: XMLCanonicalizationOptions(),
            transforms: [AddAuditAttributeTransform()]
        )

        let canonicalString = String(bytes: canonicalData, encoding: .utf8)
        XCTAssertTrue(canonicalString?.contains("audit=\"1\"") == true)
    }

    func test_canonicalize_transformFailure_wrapsAsXMLParsingError() throws {
        enum ExpectedFailure: Error {
            case boom
        }

        struct FailingTransform: XMLTransform {
            func apply(
                to _: XMLTreeDocument,
                options _: XMLCanonicalizationOptions
            ) throws -> XMLTreeDocument {
                throw ExpectedFailure.boom
            }
        }

        let document = XMLTreeDocument(root: XMLTreeElement(name: XMLQualifiedName(localName: "Root")))
        let canonicalizer = XMLDefaultCanonicalizer()

        XCTAssertThrowsError(
            try canonicalizer.canonicalize(
                document,
                options: XMLCanonicalizationOptions(),
                transforms: [FailingTransform()]
            )
        ) { error in
            guard case .other(_, let message)? = error as? XMLParsingError else {
                XCTFail("Expected XMLParsingError.other, got \(type(of: error))")
                return
            }
            XCTAssertTrue(message?.contains("XML6_9_CANONICAL_TRANSFORM_FAILED") == true)
        }
    }

    func test_canonicalize_data_streamPath_matchesTreePath() throws {
        let xml = "<Root z=\"1\" a=\"2\"><Value>  42 </Value></Root>"
        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .preserve))
        let document = try parser.parse(data: Data(xml.utf8))
        let options = XMLCanonicalizationOptions()
        let canonicalizer = XMLDefaultCanonicalizer()

        let treeData = try canonicalizer.canonicalize(document, options: options)
        let streamData = try canonicalizer.canonicalize(data: Data(xml.utf8), options: options)

        XCTAssertEqual(treeData, streamData)
    }

    func test_canonicalize_events_appliesEventTransformPipeline() throws {
        struct UppercaseTextTransform: XMLEventTransform {
            mutating func process(_ event: XMLStreamEvent) throws -> [XMLStreamEvent] {
                if case .text(let text) = event {
                    return [.text(text.uppercased())]
                }
                return [event]
            }

            mutating func finalize() throws -> [XMLStreamEvent] {
                []
            }
        }

        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "Root"), attributes: [], namespaceDeclarations: []),
            .startElement(name: XMLQualifiedName(localName: "Value"), attributes: [], namespaceDeclarations: []),
            .text("abc"),
            .endElement(name: XMLQualifiedName(localName: "Value")),
            .endElement(name: XMLQualifiedName(localName: "Root")),
            .endDocument
        ]

        let canonicalizer = XMLDefaultCanonicalizer()
        let output = try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(),
            eventTransforms: [UppercaseTextTransform()]
        )
        let xml = String(decoding: output, as: UTF8.self)
        XCTAssertTrue(xml.contains("<Value>ABC</Value>"))
    }

    func test_externalCanonicalizerPrototype_keepsTransformOrder() throws {
        let parser = XMLTreeParser()
        let input = try parser.parse(data: Data("<Root/>".utf8))
        let canonicalizer = TestExternalPrototypeCanonicalizer()
        let canonical = try canonicalizer.canonicalize(
            input,
            options: XMLCanonicalizationOptions(),
            transforms: [
                TestAppendTraceTransform(token: "A"),
                TestAppendTraceTransform(token: "B")
            ]
        )

        let parsed = try parser.parse(data: canonical)
        let traceAttribute = parsed.root.attributes.first {
            $0.name.localName == "trace"
        }
        XCTAssertEqual(traceAttribute?.value, "AB")
    }
}

private struct TestAppendTraceTransform: XMLTransform {
    let token: String

    func apply(
        to document: XMLTreeDocument,
        options _: XMLCanonicalizationOptions
    ) throws -> XMLTreeDocument {
        let traceName = XMLQualifiedName(localName: "trace")
        var attributes = document.root.attributes

        if let traceIndex = attributes.firstIndex(where: { $0.name == traceName }) {
            let previousValue = attributes[traceIndex].value
            attributes[traceIndex] = XMLTreeAttribute(name: traceName, value: previousValue + token)
        } else {
            attributes.append(XMLTreeAttribute(name: traceName, value: token))
        }

        let root = XMLTreeElement(
            name: document.root.name,
            attributes: attributes,
            namespaceDeclarations: document.root.namespaceDeclarations,
            children: document.root.children,
            metadata: document.root.metadata
        )
        return XMLTreeDocument(root: root, metadata: document.metadata)
    }
}

private struct TestExternalPrototypeCanonicalizer: XMLCanonicalizer {
    func canonicalize(
        _ document: XMLTreeDocument,
        options: XMLCanonicalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> Data {
        try XMLDefaultCanonicalizer().canonicalize(document, options: options, transforms: transforms)
    }

    func canonicalize(
        data: Data,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws {
        try XMLDefaultCanonicalizer().canonicalize(
            data: data,
            options: options,
            eventTransforms: eventTransforms,
            output: output
        )
    }

    func canonicalize<S: Sequence>(
        events: S,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws where S.Element == XMLStreamEvent {
        try XMLDefaultCanonicalizer().canonicalize(
            events: events,
            options: options,
            eventTransforms: eventTransforms,
            output: output
        )
    }
}

// MARK: - Streaming canonicalizer incremental output

extension XMLCanonicalizerTests {

    func test_streamCanonicalize_producesIncrementalOutput() throws {
        // Build a document with enough content to trigger incremental flushing.
        var xml = "<Root>"
        for i in 0..<100 {
            xml += "<item>value\(i)</item>"
        }
        xml += "</Root>"
        let data = Data(xml.utf8)

        var chunkCount = 0
        var totalData = Data()
        try XMLDefaultCanonicalizer().canonicalize(
            data: data,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        ) { chunk in
            chunkCount += 1
            totalData.append(chunk)
        }

        // The output callback should have been called at least once.
        XCTAssertGreaterThan(chunkCount, 0)
        // The concatenated output should be valid XML.
        let outputString = String(data: totalData, encoding: .utf8) ?? ""
        XCTAssertTrue(outputString.contains("<Root>"), "Output should contain root: \(outputString.prefix(200))")
        XCTAssertTrue(outputString.contains("value99"), "Output should contain last item")
    }
}
