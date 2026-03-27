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
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let result = try XMLCanonicalizerContractProbe.probeTransformFailure(
            canonicalize: canonicalizeClosure(for: canonicalizer)
        )
        XCTAssertTrue(result.message?.contains("XML6_9_CANONICAL_TRANSFORM_FAILED") == true, file: file, line: line)
        XCTAssertEqual(result.recordedTokens, ["failing-step"], file: file, line: line)
    }

    private static func canonicalizeClosure(
        for canonicalizer: XMLTestCanonicalizer
    ) -> XMLCanonicalizerContractProbe.CanonicalizeClosure {
        { document, options, transforms in
            try canonicalizer.canonicalize(document, options: options, transforms: transforms)
        }
    }
}
