import Foundation

public struct XMLDefaultCanonicalizer: XMLCanonicalizer {
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
