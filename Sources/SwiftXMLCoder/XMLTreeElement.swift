import Foundation

/// An immutable node representing an XML element in the typed tree.
///
/// `XMLTreeElement` models a single `<element>` node, including its qualified name,
/// attributes, child namespace declarations, and child nodes (text or nested elements).
/// All properties are immutable; create a modified copy by constructing a new instance.
///
/// Produced by ``XMLTreeParser`` and consumed by ``XMLTreeWriter``. The Codable
/// containers inside ``XMLEncoder`` and ``XMLDecoder`` build and read these nodes directly.
///
/// - SeeAlso: ``XMLTreeDocument``, ``XMLTreeNode``, ``XMLQualifiedName``
public struct XMLTreeElement: Sendable, Equatable, Codable {
    /// The qualified name of this element (local name + optional namespace prefix/URI).
    public let name: XMLQualifiedName
    /// The XML attributes on this element.
    public let attributes: [XMLTreeAttribute]
    /// The namespace declarations (`xmlns:prefix="uri"`) declared on this element.
    public let namespaceDeclarations: [XMLNamespaceDeclaration]
    /// The child nodes of this element (text content or nested elements).
    public let children: [XMLTreeNode]
    /// Structural metadata (source line/column, user-defined annotations).
    public let metadata: XMLNodeStructuralMetadata

    /// Creates an XML tree element.
    ///
    /// - Parameters:
    ///   - name: The qualified element name.
    ///   - attributes: The element's XML attributes. Defaults to empty.
    ///   - namespaceDeclarations: Namespace declarations on this element. Defaults to empty.
    ///   - children: Child nodes. Defaults to empty.
    ///   - metadata: Structural metadata. Defaults to `XMLNodeStructuralMetadata()`.
    public init(
        name: XMLQualifiedName,
        attributes: [XMLTreeAttribute] = [],
        namespaceDeclarations: [XMLNamespaceDeclaration] = [],
        children: [XMLTreeNode] = [],
        metadata: XMLNodeStructuralMetadata = XMLNodeStructuralMetadata()
    ) {
        self.name = name
        self.attributes = attributes
        self.namespaceDeclarations = namespaceDeclarations
        self.children = children
        self.metadata = metadata
    }
}
