import Foundation

/// A node in an immutable XML tree.
///
/// Child nodes of an ``XMLTreeElement`` are represented as an array of `XMLTreeNode`.
public enum XMLTreeNode: Sendable, Equatable, Codable {
    /// A child element node.
    case element(XMLTreeElement)
    /// A text content node.
    case text(String)
    /// A CDATA section node.
    case cdata(String)
    /// An XML comment node.
    case comment(String)
}
