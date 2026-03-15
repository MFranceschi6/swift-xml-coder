import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim

public struct XMLNode {
    let nodePointer: xmlNodePtr

    init(nodePointer: xmlNodePtr) {
        self.nodePointer = nodePointer
    }

    public var name: String? {
        guard let namePointer = nodePointer.pointee.name else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(namePointer)))
    }

    public var namespacePrefix: String? {
        guard let namespacePointer = nodePointer.pointee.ns else {
            return nil
        }
        guard let prefixPointer = namespacePointer.pointee.prefix else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(prefixPointer)))
    }

    public var namespaceURI: String? {
        guard let namespacePointer = nodePointer.pointee.ns else {
            return nil
        }
        guard let hrefPointer = namespacePointer.pointee.href else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(hrefPointer)))
    }

    public func parent() -> XMLNode? {
        guard let parentPointer = nodePointer.pointee.parent else {
            return nil
        }
        guard parentPointer.pointee.type == XML_ELEMENT_NODE else {
            return nil
        }
        return XMLNode(nodePointer: parentPointer)
    }

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

    public func text() -> String? {
        return LibXML2.withOwnedXMLCharPointer(xmlNodeGetContent(nodePointer)) { contentPointer in
            String(cString: UnsafePointer<CChar>(OpaquePointer(contentPointer)))
        }
    }

    public func attribute(named attributeName: String) -> String? {
        LibXML2.ensureInitialized()

        return LibXML2.withXMLCharPointer(attributeName) { attributeNamePointer in
            LibXML2.withOwnedXMLCharPointer(xmlGetProp(nodePointer, attributeNamePointer)) { valuePointer in
                String(cString: UnsafePointer<CChar>(OpaquePointer(valuePointer)))
            }
        }
    }

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

    public func firstChild(named childName: String) -> XMLNode? {
        children().first(where: { $0.name == childName })
    }

    public func setText(_ value: String) {
        LibXML2.withXMLCharPointer(value) { valuePointer in
            xmlNodeSetContent(nodePointer, valuePointer)
        }
    }

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
