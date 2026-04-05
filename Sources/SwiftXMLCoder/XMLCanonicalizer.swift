import Foundation

/// A type that produces a deterministic, normalized XML byte sequence from a document or event stream.
///
/// Canonicalization is the process of reducing an XML document to a canonical form — a byte sequence
/// that is identical for all semantically equivalent documents. It is required by digest and digital
/// signature workflows such as XML-DSig and WS-Security.
///
/// The protocol exposes two entry points:
///
/// - **Tree-based** (`canonicalize(_:options:transforms:)`) — accepts an ``XMLTreeDocument`` and an
///   optional ``XMLTransformPipeline``. Use this path when you already hold a parsed document, or when
///   your transforms need random access to the tree structure.
/// - **Streaming** (`canonicalize(data:options:eventTransforms:output:)` and the events overload) —
///   processes raw `Data` or a pre-parsed ``XMLStreamEvent`` sequence through an
///   ``XMLEventTransformPipeline``. Use this path for large documents where loading the full tree
///   would be too costly.
///
/// In most cases you do not need to implement this protocol — use ``XMLDefaultCanonicalizer`` directly.
/// Implement it when you need to replace the normalization or serialization logic entirely.
///
/// - SeeAlso: ``XMLDefaultCanonicalizer``, ``XMLTransform``, ``XMLEventTransform``,
///   ``XMLCanonicalizationOptions``
public protocol XMLCanonicalizer: Sendable {
    /// Produces canonical XML from a parsed document tree.
    ///
    /// - Parameters:
    ///   - document: The document to canonicalize.
    ///   - options: Normalization and serialization options.
    ///   - transforms: An ordered pipeline of tree-level transforms applied before normalization.
    /// - Returns: The canonical XML bytes.
    func canonicalize(
        _ document: XMLTreeDocument,
        options: XMLCanonicalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> Data

    /// Produces canonical XML by streaming raw input bytes through an event-transform pipeline.
    ///
    /// - Parameters:
    ///   - data: The raw XML input.
    ///   - options: Normalization and serialization options.
    ///   - eventTransforms: An ordered pipeline of event-level transforms applied during streaming.
    ///   - output: A closure called one or more times with successive canonical output chunks.
    func canonicalize(
        data: Data,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws

    /// Produces canonical XML from a pre-parsed event sequence through an event-transform pipeline.
    ///
    /// - Parameters:
    ///   - events: A sequence of ``XMLStreamEvent`` values representing the document.
    ///   - options: Normalization and serialization options.
    ///   - eventTransforms: An ordered pipeline of event-level transforms applied during streaming.
    ///   - output: A closure called one or more times with successive canonical output chunks.
    func canonicalize<S: Sequence>(
        events: S,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws where S.Element == XMLStreamEvent
}
