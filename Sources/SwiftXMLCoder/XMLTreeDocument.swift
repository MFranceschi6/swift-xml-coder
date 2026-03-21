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
    /// Document-level structural metadata (XML version, encoding, standalone flag, doctype).
    public let metadata: XMLDocumentStructuralMetadata
    /// Processing instructions and comments that appear before the root element (prolog).
    ///
    /// Populated from the parsed XML prolog. Empty when no document-level nodes precede the root.
    public let prologueNodes: [XMLDocumentNode]
    /// Processing instructions and comments that appear after the root element (epilog).
    ///
    /// Populated from the parsed XML epilog. Empty in the vast majority of real-world documents.
    public let epilogueNodes: [XMLDocumentNode]

    /// Creates an XML tree document.
    ///
    /// - Parameters:
    ///   - root: The root element.
    ///   - metadata: Document-level metadata. Defaults to `XMLDocumentStructuralMetadata()`.
    ///   - prologueNodes: Document-level nodes before the root. Defaults to `[]`.
    ///   - epilogueNodes: Document-level nodes after the root. Defaults to `[]`.
    public init(
        root: XMLTreeElement,
        metadata: XMLDocumentStructuralMetadata = XMLDocumentStructuralMetadata(),
        prologueNodes: [XMLDocumentNode] = [],
        epilogueNodes: [XMLDocumentNode] = []
    ) {
        self.root = root
        self.metadata = metadata
        self.prologueNodes = prologueNodes
        self.epilogueNodes = epilogueNodes
    }
}
