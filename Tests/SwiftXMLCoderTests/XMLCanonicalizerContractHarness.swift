import Foundation
import SwiftXMLCoder
import SwiftXMLCoderTestSupport
import XCTest

#if swift(>=6.0)
typealias XMLTestCanonicalizer = any XMLCanonicalizer
#else
typealias XMLTestCanonicalizer = XMLCanonicalizer
#endif

enum XMLCanonicalizerContractHarness {
    static func assertTransformOrder(
        canonicalizer: XMLTestCanonicalizer = XMLDefaultCanonicalizer(),
        tokens: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let result = try XMLCanonicalizerContractProbe.probeTransformOrder(
            tokens: tokens,
            canonicalize: canonicalizeClosure(for: canonicalizer)
        )

        XCTAssertEqual(result.recordedTokens, tokens, file: file, line: line)
        XCTAssertEqual(result.traceValue, tokens.joined(), file: file, line: line)
    }

    static func assertTransformFailureEnvelope(
        canonicalizer: XMLTestCanonicalizer = XMLDefaultCanonicalizer(),
        expectedCode: XMLCanonicalizationErrorCode = .transformFailed,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let result = try XMLCanonicalizerContractProbe.probeTransformFailure(
            canonicalize: canonicalizeClosure(for: canonicalizer)
        )
        XCTAssertEqual(result.stage, .transform, file: file, line: line)
        XCTAssertEqual(result.code, expectedCode, file: file, line: line)
        XCTAssertEqual(result.recordedTokens, ["failing-step"], file: file, line: line)
    }

    private static func canonicalizeClosure(
        for canonicalizer: XMLTestCanonicalizer
    ) -> XMLCanonicalizerContractProbe.CanonicalizeClosure {
        { document, options, transforms in
            try canonicalizer.canonicalView(for: document, options: options, transforms: transforms)
        }
    }
}
