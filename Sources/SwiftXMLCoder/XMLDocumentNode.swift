import Foundation

/// A node that can appear at the document level in an XML document, outside the root element.
///
/// XML allows processing instructions and comments to appear in the document prolog
/// (before the root element) and epilog (after the root element). `XMLDocumentNode`
/// represents one such node, as captured by ``XMLTreeParser`` and preserved in
/// ``XMLTreeDocument/prologueNodes`` and ``XMLTreeDocument/epilogueNodes``.
///
/// - SeeAlso: ``XMLTreeDocument``, ``XMLTreeNode``
public enum XMLDocumentNode: Sendable, Equatable, Codable {
    /// An XML comment at the document level (`<!-- ... -->`).
    case comment(String)

    /// A processing instruction at the document level (`<?target data?>`).
    ///
    /// - Parameters:
    ///   - target: The PI target name (e.g. `"xml-stylesheet"`).
    ///   - data: The PI data string, or `nil` if absent.
    case processingInstruction(target: String, data: String?)
}
