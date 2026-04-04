import Foundation

/// Public canonicalization boundary used by runtime layers and external signature engines.
public protocol XMLCanonicalizer: Sendable {
    /// Tree-based canonicalization entry point.
    func canonicalize(
        _ document: XMLTreeDocument,
        options: XMLCanonicalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> Data

    /// Streaming canonicalization entry point from raw XML data.
    func canonicalize(
        data: Data,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws

    /// Streaming canonicalization entry point from pre-existing XML events.
    func canonicalize<S: Sequence>(
        events: S,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws where S.Element == XMLStreamEvent
}
