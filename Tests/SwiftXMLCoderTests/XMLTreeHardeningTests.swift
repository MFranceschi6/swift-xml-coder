import Foundation
import SwiftXMLCoder
import XCTest

final class XMLTreeHardeningTests: XCTestCase {
    func test_parser_defaultConfiguration_isUnlimitedWhereSafe_andBlocksNetworkExternalLoading() {
        let configuration = XMLTreeParser.Configuration()

        XCTAssertNil(configuration.limits.maxInputBytes)
        XCTAssertNil(configuration.limits.maxNodeCount)
        XCTAssertNil(configuration.limits.maxAttributesPerElement)
        XCTAssertNil(configuration.limits.maxTextNodeBytes)
        XCTAssertNil(configuration.limits.maxCDATABlockBytes)
        XCTAssertEqual(configuration.limits.maxDepth, 4096)
        XCTAssertEqual(configuration.parsingConfiguration.externalResourceLoadingPolicy, .forbidNetwork)
        XCTAssertEqual(configuration.parsingConfiguration.dtdLoadingPolicy, .forbid)
        XCTAssertEqual(configuration.parsingConfiguration.entityDecodingPolicy, .preserveReferences)
    }

    func test_writer_defaultConfiguration_isUnlimitedWhereSafe_withMandatoryDepthCap() {
        let configuration = XMLTreeWriter.Configuration()

        XCTAssertNil(configuration.limits.maxNodeCount)
        XCTAssertNil(configuration.limits.maxOutputBytes)
        XCTAssertNil(configuration.limits.maxTextNodeBytes)
        XCTAssertNil(configuration.limits.maxCDATABlockBytes)
        XCTAssertNil(configuration.limits.maxCommentBytes)
        XCTAssertEqual(configuration.limits.maxDepth, 4096)
    }

    func test_parser_withMaxInputBytesLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxInputBytes: 8)
            )
        )
        let xml = "<root>payload</root>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_INPUT_BYTES")
        }
    }

    func test_parser_withMaxDepthLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxDepth: 2)
            )
        )
        let xml = "<root><level1><level2/></level1></root>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_DEPTH")
        }
    }

    func test_parser_withMaxNodeCountLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxNodeCount: 2)
            )
        )
        let xml = "<root><a/><b/></root>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_NODE_COUNT")
        }
    }

    func test_parser_withMaxAttributesPerElementLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxAttributesPerElement: 1)
            )
        )
        let xml = "<root a=\"1\" b=\"2\"/>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_ATTRIBUTES_PER_ELEMENT")
        }
    }

    func test_parser_withMaxTextNodeBytesLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxTextNodeBytes: 2)
            )
        )
        let xml = "<root>abcd</root>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_TEXT_NODE_BYTES")
        }
    }

    func test_parser_withMaxCDATABlockBytesLimit_throwsDeterministicError() {
        let parser = XMLTreeParser(
            configuration: .init(
                limits: .init(maxCDATABlockBytes: 2)
            )
        )
        let xml = "<root><![CDATA[abcd]]></root>"

        XCTAssertThrowsError(try parser.parse(data: Data(xml.utf8))) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_CDATA_BYTES")
        }
    }

    func test_writer_withMaxOutputBytesLimit_throwsDeterministicError() {
        let writer = XMLTreeWriter(
            configuration: .init(
                limits: .init(maxOutputBytes: 8)
            )
        )
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("payload")]
            )
        )

        XCTAssertThrowsError(try writer.writeData(tree)) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_OUTPUT_BYTES")
        }
    }

    func test_writer_withMaxDepthLimit_throwsDeterministicError() {
        let writer = XMLTreeWriter(
            configuration: .init(
                limits: .init(maxDepth: 2)
            )
        )
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [
                    .element(
                        XMLTreeElement(
                            name: XMLQualifiedName(localName: "Level1"),
                            children: [
                                .element(XMLTreeElement(name: XMLQualifiedName(localName: "Level2")))
                            ]
                        )
                    )
                ]
            )
        )

        XCTAssertThrowsError(try writer.writeDocument(tree)) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_DEPTH")
        }
    }

    func test_writer_withMaxNodeCountLimit_throwsDeterministicError() {
        let writer = XMLTreeWriter(
            configuration: .init(
                limits: .init(maxNodeCount: 2)
            )
        )
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [
                    .element(XMLTreeElement(name: XMLQualifiedName(localName: "A"))),
                    .element(XMLTreeElement(name: XMLQualifiedName(localName: "B")))
                ]
            )
        )

        XCTAssertThrowsError(try writer.writeDocument(tree)) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_NODE_COUNT")
        }
    }

    func test_writer_withMaxCDATABlockBytesLimit_throwsDeterministicError() {
        let writer = XMLTreeWriter(
            configuration: .init(
                limits: .init(maxCDATABlockBytes: 2)
            )
        )
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [
                    .cdata("abcd")
                ]
            )
        )

        XCTAssertThrowsError(try writer.writeDocument(tree)) { error in
            self.assertParseFailedCode(error, code: "XML6_2H_MAX_CDATA_BYTES")
        }
    }

    private func assertParseFailedCode(
        _ error: Error,
        code: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case XMLParsingError.parseFailed(let message) = error else {
            return XCTFail("Expected XMLParsingError.parseFailed, got: \(error)", file: file, line: line)
        }

        guard let message = message else {
            return XCTFail("Expected error message containing code \(code), got nil.", file: file, line: line)
        }

        XCTAssertTrue(
            message.contains("[\(code)]"),
            "Expected message to contain [\(code)], got: \(message)",
            file: file,
            line: line
        )
    }
}
