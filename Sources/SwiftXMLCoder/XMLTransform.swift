import Foundation

/// Transformation hook applied before canonical normalization in the tree-based canonicalization path.
public protocol XMLTransform: Sendable {
    func apply(
        to document: XMLTreeDocument,
        options: XMLCanonicalizationOptions
    ) throws -> XMLTreeDocument
}

#if swift(>=6.0)
public typealias XMLTransformPipeline = [any XMLTransform]
#else
public typealias XMLTransformPipeline = [XMLTransform]
#endif
