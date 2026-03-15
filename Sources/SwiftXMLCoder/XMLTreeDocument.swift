import Foundation

/// An immutable in-memory representation of an XML document as a typed tree.
///
/// `XMLTreeDocument` is the intermediate form produced by ``XMLTreeParser`` from raw XML
/// bytes and consumed by ``XMLTreeWriter`` to produce raw XML bytes. The ``XMLDecoder``
/// and ``XMLEncoder`` operate on `XMLTreeDocument` values internally.
///
/// The tree is purely functional — all nodes are immutable value types that copy on
/// mutation (via standard Swift value semantics).
///
/// - SeeAlso: ``XMLTreeElement``, ``XMLTreeParser``, ``XMLTreeWriter``
public struct XMLTreeDocument: Sendable, Equatable, Codable {
    /// The root element of the document.
    public let root: XMLTreeElement
    /// Document-level structural metadata (XML version, encoding, standalone flag).
    public let metadata: XMLDocumentStructuralMetadata

    /// Creates an XML tree document.
    ///
    /// - Parameters:
    ///   - root: The root element.
    ///   - metadata: Document-level metadata. Defaults to `XMLDocumentStructuralMetadata()`.
    public init(
        root: XMLTreeElement,
        metadata: XMLDocumentStructuralMetadata = XMLDocumentStructuralMetadata()
    ) {
        self.root = root
        self.metadata = metadata
    }
}
