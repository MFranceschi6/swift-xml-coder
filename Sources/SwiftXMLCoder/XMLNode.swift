import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim

/// A view over a single libxml2 element node within an ``XMLDocument``.
///
/// `XMLNode` is a lightweight, copyable view. It does **not** own the underlying C pointer —
/// the owning ``XMLDocument`` must remain alive for any `XMLNode` derived from it.
///
/// Use ``XMLDocument`` methods to obtain nodes, and methods on `XMLNode` to navigate, read,
/// and mutate the document tree.
public struct XMLNode {
    let nodePointer: xmlNodePtr

    init(nodePointer: xmlNodePtr) {
        self.nodePointer = nodePointer
    }

    /// The local name of the element, or `nil` if the node has no name.
    public var name: String? {
        guard let namePointer = nodePointer.pointee.name else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(namePointer)))
    }

    /// The namespace prefix bound to this element's namespace, or `nil` if unprefixed.
    public var namespacePrefix: String? {
        guard let namespacePointer = nodePointer.pointee.ns else {
            return nil
        }
        guard let prefixPointer = namespacePointer.pointee.prefix else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(prefixPointer)))
    }

    /// The namespace URI of this element, or `nil` if the element has no associated namespace.
    public var namespaceURI: String? {
        guard let namespacePointer = nodePointer.pointee.ns else {
            return nil
        }
        guard let hrefPointer = namespacePointer.pointee.href else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(hrefPointer)))
    }

    /// Returns the parent element node, or `nil` if this node is the root or has no element parent.
    public func parent() -> XMLNode? {
        guard let parentPointer = nodePointer.pointee.parent else {
            return nil
        }
        guard parentPointer.pointee.type == XML_ELEMENT_NODE else {
            return nil
        }
        return XMLNode(nodePointer: parentPointer)
    }

    /// Returns the namespace declarations defined directly on this node, keyed by prefix.
    ///
    /// The empty string key (`""`) represents the default namespace.
    public func namespaceDeclarations() -> [String: String] {
        var declarations: [String: String] = [:]
        var namespacePointer = nodePointer.pointee.nsDef

        while let currentNamespacePointer = namespacePointer {
            let prefix: String
            if let prefixPointer = currentNamespacePointer.pointee.prefix {
                prefix = String(cString: UnsafePointer<CChar>(OpaquePointer(prefixPointer)))
            } else {
                prefix = ""
            }

            if let hrefPointer = currentNamespacePointer.pointee.href {
                declarations[prefix] = String(cString: UnsafePointer<CChar>(OpaquePointer(hrefPointer)))
            }

            namespacePointer = currentNamespacePointer.pointee.next
        }

        return declarations
    }

    /// Returns all namespace declarations in scope for this node, walking up to ancestor elements.
    ///
    /// Inner declarations shadow outer ones with the same prefix.
    /// The empty string key (`""`) represents the default namespace.
    public func namespaceDeclarationsInScope() -> [String: String] {
        var scopeDeclarations: [String: String] = [:]
        var currentNode: XMLNode? = self

        while let node = currentNode {
            for (prefix, uri) in node.namespaceDeclarations() where scopeDeclarations[prefix] == nil {
                scopeDeclarations[prefix] = uri
            }
            currentNode = node.parent()
        }

        return scopeDeclarations
    }

    /// Returns the concatenated text content of this node and all its descendants, or `nil` if empty.
    public func text() -> String? {
        return LibXML2.withOwnedXMLCharPointer(xmlNodeGetContent(nodePointer)) { contentPointer in
            String(cString: UnsafePointer<CChar>(OpaquePointer(contentPointer)))
        }
    }

    /// Returns the value of an attribute on this node, or `nil` if the attribute is absent.
    ///
    /// - Parameter attributeName: The unqualified attribute name.
    public func attribute(named attributeName: String) -> String? {
        LibXML2.ensureInitialized()

        return LibXML2.withXMLCharPointer(attributeName) { attributeNamePointer in
            LibXML2.withOwnedXMLCharPointer(xmlGetProp(nodePointer, attributeNamePointer)) { valuePointer in
                String(cString: UnsafePointer<CChar>(OpaquePointer(valuePointer)))
            }
        }
    }

    /// Returns all direct element children of this node.
    public func children() -> [XMLNode] {
        var nodes: [XMLNode] = []
        var childPointer = nodePointer.pointee.children
        while let currentPointer = childPointer {
            if currentPointer.pointee.type == XML_ELEMENT_NODE {
                nodes.append(XMLNode(nodePointer: currentPointer))
            }
            childPointer = currentPointer.pointee.next
        }
        return nodes
    }

    /// Returns the first direct element child with the given local name, or `nil` if none is found.
    ///
    /// - Parameter childName: The local name to match.
    public func firstChild(named childName: String) -> XMLNode? {
        children().first(where: { $0.name == childName })
    }

    /// Sets the text content of this node, replacing any existing content.
    ///
    /// - Parameter value: The new text content.
    public func setText(_ value: String) {
        LibXML2.withXMLCharPointer(value) { valuePointer in
            xmlNodeSetContent(nodePointer, valuePointer)
        }
    }

    /// Sets an attribute on this node.
    ///
    /// - Parameters:
    ///   - attributeName: The unqualified attribute name.
    ///   - value: The attribute value.
    /// - Throws: ``XMLParsingError`` if the attribute cannot be set.
    #if swift(>=6.0)
    public func setAttribute(named attributeName: String, value: String) throws(XMLParsingError) {
        let result = LibXML2.withXMLCharPointer(attributeName) { attributeNamePointer in
            LibXML2.withXMLCharPointer(value) { valuePointer in
                xmlSetProp(nodePointer, attributeNamePointer, valuePointer)
            }
        }

        guard result != nil else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to set attribute '\(attributeName)' on node '\(name ?? "<unknown>")'."
            )
        }
    }
    #else
    public func setAttribute(named attributeName: String, value: String) throws {
        let result = LibXML2.withXMLCharPointer(attributeName) { attributeNamePointer in
            LibXML2.withXMLCharPointer(value) { valuePointer in
                xmlSetProp(nodePointer, attributeNamePointer, valuePointer)
            }
        }

        guard result != nil else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to set attribute '\(attributeName)' on node '\(name ?? "<unknown>")'."
            )
        }
    }
    #endif

    /// Adds a namespace declaration to this node and sets it as the node's active namespace.
    ///
    /// - Parameter namespace: The ``XMLNamespace`` to declare and activate.
    /// - Throws: ``XMLParsingError`` if the namespace URI is empty (for a prefixed declaration)
    ///   or if the libxml2 call fails.
    #if swift(>=6.0)
    public func addNamespace(_ namespace: XMLNamespace) throws(XMLParsingError) {
        if namespace.prefix != nil && namespace.uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw XMLParsingError.invalidNamespaceConfiguration(prefix: namespace.prefix, uri: namespace.uri)
        }

        let namespacePointer = LibXML2.withXMLCharPointer(namespace.uri) { uriPointer -> xmlNsPtr? in
            if let prefix = namespace.prefix {
                return LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                    xmlNewNs(nodePointer, uriPointer, prefixPointer)
                }
            } else {
                return xmlNewNs(nodePointer, uriPointer, nil)
            }
        }

        guard let namespacePointer = namespacePointer else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to add namespace '\(namespace.uri)' to node '\(name ?? "<unknown>")'."
            )
        }

        xmlSetNs(nodePointer, namespacePointer)
    }
    #else
    public func addNamespace(_ namespace: XMLNamespace) throws {
        if namespace.prefix != nil && namespace.uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw XMLParsingError.invalidNamespaceConfiguration(prefix: namespace.prefix, uri: namespace.uri)
        }

        let namespacePointer = LibXML2.withXMLCharPointer(namespace.uri) { uriPointer -> xmlNsPtr? in
            if let prefix = namespace.prefix {
                return LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                    xmlNewNs(nodePointer, uriPointer, prefixPointer)
                }
            } else {
                return xmlNewNs(nodePointer, uriPointer, nil)
            }
        }

        guard let namespacePointer = namespacePointer else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to add namespace '\(namespace.uri)' to node '\(name ?? "<unknown>")'."
            )
        }

        xmlSetNs(nodePointer, namespacePointer)
    }
    #endif

    /// Appends `child` as the last child of this node.
    ///
    /// - Parameter child: The node to append. Must belong to the same document.
    /// - Throws: ``XMLParsingError`` if appending would create a cycle, the node is appended
    ///   to itself, the node belongs to a different document, or the libxml2 call fails.
    #if swift(>=6.0)
    public func addChild(_ child: XMLNode) throws(XMLParsingError) {
        if child.nodePointer == nodePointer {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append a node as a child of itself."
            )
        }

        var ancestorPointer = nodePointer.pointee.parent
        while let currentAncestor = ancestorPointer {
            if currentAncestor == child.nodePointer {
                throw XMLParsingError.nodeOperationFailed(
                    message: "Unable to append an ancestor node as child, would create a cycle."
                )
            }
            ancestorPointer = currentAncestor.pointee.parent
        }

        let parentDocument = nodePointer.pointee.doc
        let childDocument = child.nodePointer.pointee.doc
        if let parentDocument = parentDocument, let childDocument = childDocument, parentDocument != childDocument {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append child from a different XML document."
            )
        }

        guard xmlAddChild(nodePointer, child.nodePointer) != nil else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append child '\(child.name ?? "<unknown>")' to node '\(name ?? "<unknown>")'."
            )
        }
    }
    #else
    public func addChild(_ child: XMLNode) throws {
        if child.nodePointer == nodePointer {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append a node as a child of itself."
            )
        }

        var ancestorPointer = nodePointer.pointee.parent
        while let currentAncestor = ancestorPointer {
            if currentAncestor == child.nodePointer {
                throw XMLParsingError.nodeOperationFailed(
                    message: "Unable to append an ancestor node as child, would create a cycle."
                )
            }
            ancestorPointer = currentAncestor.pointee.parent
        }

        let parentDocument = nodePointer.pointee.doc
        let childDocument = child.nodePointer.pointee.doc
        if let parentDocument = parentDocument, let childDocument = childDocument, parentDocument != childDocument {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append child from a different XML document."
            )
        }

        guard xmlAddChild(nodePointer, child.nodePointer) != nil else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append child '\(child.name ?? "<unknown>")' to node '\(name ?? "<unknown>")'."
            )
        }
    }
    #endif
}
