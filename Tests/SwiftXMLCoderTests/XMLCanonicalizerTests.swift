import Foundation
import SwiftXMLCoder
import XCTest

final class XMLCanonicalizerTests: XCTestCase {
    func test_canonicalView_semanticallyEquivalentInputs_produceSameCanonicalData() throws {
        let xmlA = """
        <Root xmlns:b="urn:b" xmlns:a="urn:a" z="1" a="2"><a:Child><![CDATA[payload]]></a:Child></Root>
        """
        let xmlB = """
        <Root a="2" z="1" xmlns:a="urn:a" xmlns:b="urn:b"><a:Child>payload</a:Child></Root>
        """

        let parser = XMLTreeParser(configuration: .init(whitespaceTextNodePolicy: .trim))
        let canonicalizer = XMLDefaultCanonicalizer()
        let options = XMLNormalizationOptions(
            attributeOrderingPolicy: .lexicographical,
            namespaceDeclarationOrderingPolicy: .lexicographical,
            whitespaceTextNodePolicy: .normalizeAndTrim,
            deterministicSerializationMode: .stable,
            includeComments: false,
            convertCDATAIntoText: true
        )

        let documentA = try parser.parse(data: Data(xmlA.utf8))
        let documentB = try parser.parse(data: Data(xmlB.utf8))
        let canonicalA = try canonicalizer.canonicalView(for: documentA, options: options, transforms: [])
        let canonicalB = try canonicalizer.canonicalView(for: documentB, options: options, transforms: [])

        XCTAssertEqual(canonicalA.canonicalXMLData, canonicalB.canonicalXMLData)
        XCTAssertEqual(canonicalA.normalizedDocument, canonicalB.normalizedDocument)
    }

    func test_canonicalView_includeComments_false_removesComments() throws {
        let xml = "<Root><!--note--><Value>42</Value></Root>"
        let parser = XMLTreeParser()
        let canonicalizer = XMLDefaultCanonicalizer()
        let options = XMLNormalizationOptions(includeComments: false)

        let document = try parser.parse(data: Data(xml.utf8))
        let canonical = try canonicalizer.canonicalView(for: document, options: options, transforms: [])

        let comments = canonical.normalizedDocument.root.children.filter {
            if case .comment = $0 {
                return true
            }
            return false
        }
        XCTAssertTrue(comments.isEmpty)
    }

    func test_canonicalView_appliesCustomTransformPipeline() throws {
        struct AddAuditAttributeTransform: XMLTransform {
            func apply(
                to document: XMLTreeDocument,
                options _: XMLNormalizationOptions
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
        let canonical = try canonicalizer.canonicalView(
            for: document,
            options: XMLNormalizationOptions(),
            transforms: [AddAuditAttributeTransform()]
        )

        XCTAssertEqual(canonical.normalizedDocument.root.attributes.map(\.name.localName), ["audit"])
        let canonicalString = String(bytes: canonical.canonicalXMLData, encoding: .utf8)
        XCTAssertTrue(canonicalString?.contains("audit=\"1\"") == true)
    }

    func test_canonicalView_transformFailure_wrapsErrorWithStableCodeAndStage() throws {
        enum ExpectedFailure: Error {
            case boom
        }

        struct FailingTransform: XMLTransform {
            func apply(
                to _: XMLTreeDocument,
                options _: XMLNormalizationOptions
            ) throws -> XMLTreeDocument {
                throw ExpectedFailure.boom
            }
        }

        let document = XMLTreeDocument(root: XMLTreeElement(name: XMLQualifiedName(localName: "Root")))
        let canonicalizer = XMLDefaultCanonicalizer()

        XCTAssertThrowsError(
            try canonicalizer.canonicalView(
                for: document,
                options: XMLNormalizationOptions(),
                transforms: [FailingTransform()]
            )
        ) { error in
            guard let canonicalError = error as? XMLCanonicalizationError else {
                XCTFail("Expected XMLCanonicalizationError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(canonicalError.stage, .transform)
            XCTAssertEqual(canonicalError.code, .transformFailed)

            guard case .transformFailed(
                _,
                let index,
                let transformType,
                let underlyingError,
                let message
            ) = canonicalError else {
                XCTFail("Expected transformFailed case.")
                return
            }

            XCTAssertEqual(index, 0)
            XCTAssertTrue(transformType.contains("FailingTransform"))
            XCTAssertTrue((underlyingError as? ExpectedFailure) == .boom)
            XCTAssertTrue((message ?? "").contains("XML6_9_CANONICAL_TRANSFORM_FAILED"))
        }
    }

    func test_canonicalView_writerFailure_wrapsErrorWithSerializationStage() throws {
        let root = XMLTreeElement(
            name: XMLQualifiedName(localName: "Root", namespaceURI: nil, prefix: "p")
        )
        let document = XMLTreeDocument(root: root)
        let canonicalizer = XMLDefaultCanonicalizer()

        XCTAssertThrowsError(
            try canonicalizer.canonicalView(
                for: document,
                options: XMLNormalizationOptions(),
                transforms: []
            )
        ) { error in
            guard let canonicalError = error as? XMLCanonicalizationError else {
                XCTFail("Expected XMLCanonicalizationError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(canonicalError.stage, .serialization)
            XCTAssertEqual(canonicalError.code, .serializationFailed)

            guard case .serializationFailed(_, let underlyingError, let message) = canonicalError else {
                XCTFail("Expected serializationFailed case.")
                return
            }

            let parsingError = underlyingError as? XMLParsingError
            XCTAssertNotNil(parsingError)
            if case .parseFailed(let parseMessage)? = parsingError {
                XCTAssertTrue((parseMessage ?? "").contains("XML6_3_NAMESPACE_VALIDATION"))
            } else {
                XCTFail("Expected XMLParsingError.parseFailed.")
            }
            XCTAssertTrue((message ?? "").contains("XML6_9_CANONICAL_SERIALIZATION_FAILED"))
        }
    }

    func test_canonicalView_transformThrowingCanonicalizationError_isPropagatedUnchanged() throws {
        struct PassThroughTransform: XMLTransform {
            func apply(
                to _: XMLTreeDocument,
                options _: XMLNormalizationOptions
            ) throws -> XMLTreeDocument {
                throw XMLCanonicalizationError.other(
                    code: .init(rawValue: "XML6_9_CUSTOM"),
                    underlyingError: nil,
                    message: "[XML6_9_CUSTOM] custom failure"
                )
            }
        }

        let document = XMLTreeDocument(root: XMLTreeElement(name: XMLQualifiedName(localName: "Root")))
        let canonicalizer = XMLDefaultCanonicalizer()

        XCTAssertThrowsError(
            try canonicalizer.canonicalView(
                for: document,
                options: XMLNormalizationOptions(),
                transforms: [PassThroughTransform()]
            )
        ) { error in
            guard let canonicalError = error as? XMLCanonicalizationError else {
                XCTFail("Expected XMLCanonicalizationError, got \(type(of: error))")
                return
            }

            XCTAssertEqual(canonicalError.stage, .other)
            XCTAssertEqual(canonicalError.code, XMLCanonicalizationErrorCode(rawValue: "XML6_9_CUSTOM"))
            if case .other(_, _, let message) = canonicalError {
                XCTAssertEqual(message, "[XML6_9_CUSTOM] custom failure")
            } else {
                XCTFail("Expected other case.")
            }
        }
    }

    func test_externalCanonicalizerPrototype_usesPublicContractAndKeepsTransformOrder() throws {
        let parser = XMLTreeParser()
        let input = try parser.parse(data: Data("<Root/>".utf8))
        let canonicalizer = TestExternalPrototypeCanonicalizer()
        let canonical = try canonicalizer.canonicalView(
            for: input,
            options: XMLNormalizationOptions(),
            transforms: [
                TestAppendTraceTransform(token: "A"),
                TestAppendTraceTransform(token: "B")
            ]
        )

        let traceAttribute = canonical.normalizedDocument.root.attributes.first {
            $0.name.localName == "trace"
        }
        XCTAssertEqual(traceAttribute?.value, "AB")
    }
}

private struct TestAppendTraceTransform: XMLTransform {
    let token: String

    func apply(
        to document: XMLTreeDocument,
        options _: XMLNormalizationOptions
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
    #if swift(>=6.0)
    func canonicalView(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws(XMLCanonicalizationError) -> XMLCanonicalView {
        let transformedDocument = try XMLCanonicalizationContract.applyTransforms(
            to: document,
            options: options,
            transforms: transforms
        )
        return try XMLDefaultCanonicalizer().canonicalView(
            for: transformedDocument,
            options: options,
            transforms: []
        )
    }
    #else
    func canonicalView(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> XMLCanonicalView {
        let transformedDocument = try XMLCanonicalizationContract.applyTransforms(
            to: document,
            options: options,
            transforms: transforms
        )
        return try XMLDefaultCanonicalizer().canonicalView(
            for: transformedDocument,
            options: options,
            transforms: []
        )
    }
    #endif
}
