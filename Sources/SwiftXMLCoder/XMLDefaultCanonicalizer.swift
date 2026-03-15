import Foundation

/// The default ``XMLCanonicalizer`` implementation.
///
/// Produces deterministic canonical XML by sorting attributes alphabetically,
/// normalising namespace declarations, applying any ``XMLTransform`` pipeline steps,
/// and serialising with configurable whitespace and encoding policies.
///
/// ```swift
/// let canonicalizer = XMLDefaultCanonicalizer()
/// let view = try canonicalizer.canonicalView(for: tree)
/// let deterministicBytes = view.canonicalXMLData
/// ```
public struct XMLDefaultCanonicalizer: XMLCanonicalizer {
    /// Creates a default canonicalizer.
    public init() {}

    #if swift(>=6.0)
    public func canonicalView(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions = XMLNormalizationOptions(),
        transforms: XMLTransformPipeline = []
    ) throws(XMLCanonicalizationError) -> XMLCanonicalView {
        do {
            return try canonicalViewImpl(for: document, options: options, transforms: transforms)
        } catch let error as XMLCanonicalizationError {
            throw error
        } catch {
            throw XMLCanonicalizationContract.unexpectedFailure(underlyingError: error)
        }
    }
    #else
    public func canonicalView(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions = XMLNormalizationOptions(),
        transforms: XMLTransformPipeline = []
    ) throws -> XMLCanonicalView {
        try canonicalViewImpl(for: document, options: options, transforms: transforms)
    }
    #endif
}
