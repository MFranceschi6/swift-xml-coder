import Foundation
import SwiftXMLCoder

public enum XMLCanonicalizerContractProbe {
    public typealias CanonicalizeClosure = (
        _ document: XMLTreeDocument,
        _ options: XMLNormalizationOptions,
        _ transforms: XMLTransformPipeline
    ) throws -> XMLCanonicalView

    public static func makeDefaultCanonicalizeClosure() -> CanonicalizeClosure {
        let canonicalizer = XMLDefaultCanonicalizer()
        return { document, options, transforms in
            try canonicalizer.canonicalView(for: document, options: options, transforms: transforms)
        }
    }

    public static func probeTransformOrder(
        tokens: [String],
        canonicalize: CanonicalizeClosure
    ) throws -> XMLCanonicalizerOrderProbeResult {
        let recorder = XMLTestCallRecorder()
        let transforms = tokens.map { XMLTestRecordingTransform(token: $0, recorder: recorder) }
        let canonical = try canonicalize(
            minimalDocument(),
            XMLNormalizationOptions(),
            transforms
        )
        let traceAttribute = canonical.normalizedDocument.root.attributes.first {
            $0.name.localName == "trace"
        }

        return XMLCanonicalizerOrderProbeResult(
            recordedTokens: recorder.snapshot(),
            traceValue: traceAttribute?.value
        )
    }

    public static func probeTransformFailure(
        canonicalize: CanonicalizeClosure
    ) throws -> XMLCanonicalizerFailureProbeResult {
        let recorder = XMLTestCallRecorder()
        let transforms: XMLTransformPipeline = [
            XMLTestFailingTransform(
                token: "failing-step",
                recorder: recorder,
                error: XMLTestCodecError.forcedFailure(message: "forced-transform-failure")
            )
        ]

        do {
            _ = try canonicalize(minimalDocument(), XMLNormalizationOptions(), transforms)
            throw XMLTestCodecError.forcedFailure(
                message: "Expected canonicalize closure to fail for failing transform."
            )
        } catch let canonicalError as XMLCanonicalizationError {
            return XMLCanonicalizerFailureProbeResult(
                stage: canonicalError.stage,
                code: canonicalError.code,
                recordedTokens: recorder.snapshot()
            )
        }
    }

    private static func minimalDocument() -> XMLTreeDocument {
        XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                children: [.text("payload")]
            )
        )
    }
}
