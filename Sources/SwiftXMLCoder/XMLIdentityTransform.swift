import Foundation

/// A no-op ``XMLTransform`` that returns the document unchanged.
///
/// Useful as a placeholder in transform pipelines or for testing purposes.
public struct XMLIdentityTransform: XMLTransform {
    /// Creates an identity transform.
    public init() {}

    public func apply(
        to document: XMLTreeDocument,
        options: XMLNormalizationOptions
    ) throws -> XMLTreeDocument {
        document
    }
}
