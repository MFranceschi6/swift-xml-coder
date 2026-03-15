import Foundation

/// Transformation hook applied before canonical normalization.
///
/// Transforms are executed in-order by `XMLCanonicalizationContract.applyTransforms(...)`.
/// A transform must be deterministic for identical input/options pairs.
public protocol XMLTransform: Sendable {
    func apply(
        to document: XMLTreeDocument,
        options: XMLNormalizationOptions
    ) throws -> XMLTreeDocument
}

#if swift(>=6.0)
public typealias XMLTransformPipeline = [any XMLTransform]
#else
public typealias XMLTransformPipeline = [XMLTransform]
#endif
