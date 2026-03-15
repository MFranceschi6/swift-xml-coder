import Foundation

/// Public canonicalization boundary used by SOAP/runtime layers and external XML signature engines.
///
/// `SwiftXMLCoder` provides deterministic normalization and extensibility hooks, but intentionally
/// does not implement XMLDSig canonicalization/signature algorithms directly.
///
/// External libraries can implement `XMLCanonicalizer` and optionally reuse
/// `XMLCanonicalizationContract` helpers to keep transform ordering and error propagation
/// semantics consistent with the default runtime behavior.
public protocol XMLCanonicalizer: Sendable {
    func canonicalView(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> XMLCanonicalView
}
