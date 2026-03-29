import Foundation
import SwiftXMLCoder
import SwiftXMLCoderTestSupport
import XCTest

final class XMLTestingToolkitIntegrationTests: XCTestCase {
    private struct Payload: Codable, Equatable {
        let value: String
    }

    func test_encoderDecoderSpies_recordCalls_forRoundtrip() throws {
        let payload = Payload(value: "ok")
        let encoderSpy = XMLTestEncoderSpy(
            encoder: XMLEncoder(configuration: .init(rootElementName: "Payload"))
        )

        let encodedData = try encoderSpy.encode(payload)
        XCTAssertEqual(encoderSpy.calls.count, 1)
        XCTAssertEqual(encoderSpy.calls.first?.method, .encodeData)
        XCTAssertEqual(encoderSpy.calls.first?.valueTypeName, String(reflecting: Payload.self))

        let decoderSpy = XMLTestDecoderSpy(
            decoder: XMLDecoder(configuration: .init(rootElementName: "Payload"))
        )
        let decoded = try decoderSpy.decode(Payload.self, from: encodedData)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoderSpy.calls.count, 1)
        XCTAssertEqual(decoderSpy.calls.first?.method, .decodeData)
        XCTAssertEqual(decoderSpy.calls.first?.valueTypeName, String(reflecting: Payload.self))
        XCTAssertTrue((decoderSpy.calls.first?.payloadSize ?? 0) > 0)
    }

    func test_encoderSpy_forcedError_isDeterministic() {
        let encoderSpy = XMLTestEncoderSpy()
        encoderSpy.forcedError = XMLTestCodecError.forcedFailure(message: "forced-encode-failure")

        XCTAssertThrowsError(try encoderSpy.encode(Payload(value: "boom"))) { error in
            XCTAssertEqual(
                error as? XMLTestCodecError,
                .forcedFailure(message: "forced-encode-failure")
            )
        }
    }

    func test_canonicalizerHarness_assertsTransformOrderAndFailureEnvelope() throws {
        try XMLCanonicalizerContractHarness.assertTransformOrder(tokens: ["A", "B", "C"])
        try XMLCanonicalizerContractHarness.assertTransformFailureEnvelope()
    }

    // MARK: - EncoderSpy.encodeTree and stub/forced-error paths

    func test_encoderSpy_encodeTree_recordsCall() throws {
        let encoderSpy = XMLTestEncoderSpy(
            encoder: XMLEncoder(configuration: .init(rootElementName: "Payload"))
        )
        let tree = try encoderSpy.encodeTree(Payload(value: "tree"))
        XCTAssertEqual(tree.root.name.localName, "Payload")
        XCTAssertEqual(encoderSpy.calls.count, 1)
        XCTAssertEqual(encoderSpy.calls.first?.method, .encodeTree)
    }

    func test_encoderSpy_encodeTree_forcedError_throws() {
        let encoderSpy = XMLTestEncoderSpy()
        encoderSpy.forcedError = XMLTestCodecError.forcedFailure(message: "tree-error")
        XCTAssertThrowsError(try encoderSpy.encodeTree(Payload(value: "x"))) { error in
            XCTAssertEqual(error as? XMLTestCodecError, .forcedFailure(message: "tree-error"))
        }
    }

    func test_encoderSpy_encode_stubbedData_returnsStub() throws {
        let stub = Data("stubbed".utf8)
        let encoderSpy = XMLTestEncoderSpy()
        encoderSpy.stubbedData = stub
        let result = try encoderSpy.encode(Payload(value: "ignored"))
        XCTAssertEqual(result, stub)
    }

    func test_encoderSpy_encodeTree_stubbedDocument_returnsStub() throws {
        let xml = Data("<Payload><value>stub</value></Payload>".utf8)
        let parser = XMLTreeParser()
        let stubDoc = try parser.parse(data: xml)
        let encoderSpy = XMLTestEncoderSpy()
        encoderSpy.stubbedTreeDocument = stubDoc
        let result = try encoderSpy.encodeTree(Payload(value: "ignored"))
        XCTAssertEqual(result.root.name.localName, "Payload")
    }

    // MARK: - DecoderSpy.decode forced-error path

    func test_decoderSpy_decode_forcedError_throws() {
        let decoderSpy = XMLTestDecoderSpy()
        decoderSpy.forcedError = XMLTestCodecError.forcedFailure(message: "decode-error")
        let xml = Data("<Payload><value>x</value></Payload>".utf8)
        XCTAssertThrowsError(try decoderSpy.decode(Payload.self, from: xml)) { error in
            XCTAssertEqual(error as? XMLTestCodecError, .forcedFailure(message: "decode-error"))
        }
    }
}
