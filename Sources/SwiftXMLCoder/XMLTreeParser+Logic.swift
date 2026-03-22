import Foundation
import Logging
import XMLCoderCompatibility
import SwiftXMLCoderCShim

// MARK: - Architecture: libxml2 → XMLTreeDocument conversion
//
// `XMLTreeParser+Logic` contains the internal traversal that converts a libxml2
// `XMLDocument` (a C-level DOM) into the Swift-native immutable `XMLTreeDocument`.
//
// ## Parse pipeline
//
//   XMLTreeParser.parse(data:)          (in XMLTreeParser.swift)
//     → libxml2 parses raw bytes into XMLDocument (C DOM)
//     → parseDocument(_ document:)     (this file)
//          → walks document.rootElement() recursively via parseElement
//          → text / CDATA / comment nodes → XMLTreeNode cases
//          → element nodes → XMLTreeElement (name, attributes, ns declarations)
//          → whitespace-only text nodes dropped if whitespaceTextNodePolicy == .dropWhitespaceOnly
//     → returns XMLTreeDocument { root: XMLTreeElement }
//
// ## Namespace handling
//
// Namespace prefix bindings declared on an element (xmlns:prefix="uri") are
// captured in `XMLNamespaceDeclaration` values on `XMLTreeElement.namespaceDeclarations`.
// The qualified name (prefix + localName + namespaceURI) is stored in `XMLQualifiedName`.
// The parser does NOT resolve inherited namespaces — consumers must do their own
// lookup via `XMLNamespaceResolver` if needed.

extension XMLTreeParser {
    func parseDocument(_ document: XMLDocument) throws -> XMLTreeDocument {
        guard let rootNode = document.rootElement() else {
            throw XMLParsingError.parseFailed(message: "XML document does not contain a root element.")
        }

        var logger = configuration.logger
        logger[metadataKey: "component"] = "XMLTreeParser"
        logger.debug("XML parse started")

        var parseState = ParseState()
        let rootElement = try parseElement(
            nodePointer: rootNode.nodePointer,
            sourceOrder: 0,
            depth: 1,
            parseState: &parseState
        )
        let docPointer = rootNode.nodePointer.pointee.doc
        let metadata = parseDocumentMetadata(from: docPointer)
        let (prologueNodes, epilogueNodes) = parseDocumentLevelNodes(from: docPointer)
        logger.debug("XML parse completed", metadata: ["nodeCount": "\(parseState.nodeCount)"])
        return XMLTreeDocument(
            root: rootElement,
            metadata: metadata,
            prologueNodes: prologueNodes,
            epilogueNodes: epilogueNodes
        )
    }

    func effectiveParsingConfiguration() -> XMLDocument.ParsingConfiguration {
        guard configuration.whitespaceTextNodePolicy == .preserve,
              configuration.parsingConfiguration.trimBlankTextNodes
        else {
            return configuration.parsingConfiguration
        }

        return XMLDocument.ParsingConfiguration(
            trimBlankTextNodes: false,
            externalResourceLoadingPolicy: configuration.parsingConfiguration.externalResourceLoadingPolicy,
            dtdLoadingPolicy: configuration.parsingConfiguration.dtdLoadingPolicy,
            entityDecodingPolicy: configuration.parsingConfiguration.entityDecodingPolicy
        )
    }

    func ensureLimit(
        actual: Int,
        limit: Int?,
        code: String,
        context: String
    ) throws {
        guard let limit = limit else {
            return
        }

        guard actual <= limit else {
            configuration.logger.warning(
                "XML parse limit exceeded",
                metadata: ["code": "\(code)", "context": "\(context)", "actual": "\(actual)", "limit": "\(limit)"]
            )
            throw XMLParsingError.parseFailed(
                message: "[\(code)] \(context) exceeded max (\(limit)): \(actual)."
            )
        }
    }

    private func parseElement(
        nodePointer: xmlNodePtr,
        sourceOrder: Int?,
        depth: Int,
        parseState: inout ParseState
    ) throws -> XMLTreeElement {
        try ensureDepth(depth, parseState: &parseState)
        try incrementNodeCount(parseState: &parseState, context: "element")

        let nodeName = string(fromXMLCharPointer: nodePointer.pointee.name)
        guard let nodeName = nodeName, nodeName.isEmpty == false else {
            throw XMLParsingError.nodeCreationFailed(name: "<unknown>", message: "XML element name is missing.")
        }

        let namespaceURI = string(fromXMLCharPointer: nodePointer.pointee.ns?.pointee.href)
        let prefix = string(fromXMLCharPointer: nodePointer.pointee.ns?.pointee.prefix)
        let qualifiedName = XMLQualifiedName(localName: nodeName, namespaceURI: namespaceURI, prefix: prefix)

        let attributes = parseAttributes(nodePointer: nodePointer)
        try ensureLimit(
            actual: attributes.count,
            limit: configuration.limits.maxAttributesPerElement,
            code: "XML6_2H_MAX_ATTRIBUTES_PER_ELEMENT",
            context: "attributes per element"
        )

        let namespaceDeclarations = parseNamespaceDeclarations(nodePointer: nodePointer)
        let children = try parseChildren(
            nodePointer: nodePointer,
            depth: depth,
            parseState: &parseState
        )
        let lineNo = Int(xmlGetLineNo(nodePointer))
        let metadata = XMLNodeStructuralMetadata(
            sourceOrder: sourceOrder,
            originalPrefix: prefix,
            wasSelfClosing: nil,
            sourceLine: lineNo > 0 ? lineNo : nil
        )

        return XMLTreeElement(
            name: qualifiedName,
            attributes: attributes,
            namespaceDeclarations: namespaceDeclarations,
            children: children,
            metadata: metadata
        )
    }

    private func parseAttributes(nodePointer: xmlNodePtr) -> [XMLTreeAttribute] {
        var attributes: [XMLTreeAttribute] = []
        var attributePointer = nodePointer.pointee.properties

        while let currentAttributePointer = attributePointer {
            let localName = string(fromXMLCharPointer: currentAttributePointer.pointee.name) ?? ""
            let namespaceURI = string(fromXMLCharPointer: currentAttributePointer.pointee.ns?.pointee.href)
            let prefix = string(fromXMLCharPointer: currentAttributePointer.pointee.ns?.pointee.prefix)
            let name = XMLQualifiedName(localName: localName, namespaceURI: namespaceURI, prefix: prefix)
            let value = parseAttributeValue(attributePointer: currentAttributePointer, nodePointer: nodePointer)

            attributes.append(XMLTreeAttribute(name: name, value: value))
            attributePointer = currentAttributePointer.pointee.next
        }

        return attributes
    }

    private func parseAttributeValue(attributePointer: xmlAttrPtr, nodePointer: xmlNodePtr) -> String {
        guard let documentPointer = nodePointer.pointee.doc else {
            return ""
        }

        guard let valuePointer = xmlNodeListGetString(documentPointer, attributePointer.pointee.children, 1) else {
            return ""
        }

        return LibXML2.withOwnedXMLCharPointer(valuePointer) { ownedValuePointer in
            String(cString: UnsafePointer<CChar>(OpaquePointer(ownedValuePointer)))
        } ?? ""
    }

    private func parseNamespaceDeclarations(nodePointer: xmlNodePtr) -> [XMLNamespaceDeclaration] {
        var declarations: [XMLNamespaceDeclaration] = []
        var namespacePointer = nodePointer.pointee.nsDef

        while let currentNamespacePointer = namespacePointer {
            let prefix = string(fromXMLCharPointer: currentNamespacePointer.pointee.prefix)
            let uri = string(fromXMLCharPointer: currentNamespacePointer.pointee.href) ?? ""
            declarations.append(XMLNamespaceDeclaration(prefix: prefix, uri: uri))
            namespacePointer = currentNamespacePointer.pointee.next
        }

        return declarations
    }

    private func parseChildren(
        nodePointer: xmlNodePtr,
        depth: Int,
        parseState: inout ParseState
    ) throws -> [XMLTreeNode] {
        var children: [XMLTreeNode] = []
        var childPointer = nodePointer.pointee.children
        var sourceOrder = 0

        while let currentChildPointer = childPointer {
            defer {
                childPointer = currentChildPointer.pointee.next
                sourceOrder += 1
            }

            switch currentChildPointer.pointee.type {
            case XML_ELEMENT_NODE:
                let element = try parseElement(
                    nodePointer: currentChildPointer,
                    sourceOrder: sourceOrder,
                    depth: depth + 1,
                    parseState: &parseState
                )
                children.append(.element(element))
            case XML_TEXT_NODE:
                let value = string(fromNodeContent: currentChildPointer)
                if let normalizedValue = normalizedTextNodeValue(value) {
                    try ensureUTF8Length(
                        normalizedValue,
                        limit: configuration.limits.maxTextNodeBytes,
                        code: "XML6_2H_MAX_TEXT_NODE_BYTES",
                        context: "text node"
                    )
                    try incrementNodeCount(parseState: &parseState, context: "text node")
                    children.append(.text(normalizedValue))
                }
            case XML_CDATA_SECTION_NODE:
                let value = string(fromNodeContent: currentChildPointer)
                try ensureUTF8Length(
                    value,
                    limit: configuration.limits.maxCDATABlockBytes,
                    code: "XML6_2H_MAX_CDATA_BYTES",
                    context: "CDATA node"
                )
                try incrementNodeCount(parseState: &parseState, context: "CDATA node")
                children.append(.cdata(value))
            case XML_COMMENT_NODE:
                let value = string(fromNodeContent: currentChildPointer)
                try incrementNodeCount(parseState: &parseState, context: "comment node")
                children.append(.comment(value))
            case XML_PI_NODE:
                let target = string(fromXMLCharPointer: currentChildPointer.pointee.name) ?? ""
                let data = currentChildPointer.pointee.content.map {
                    String(cString: UnsafePointer<CChar>(OpaquePointer($0)))
                }
                try incrementNodeCount(parseState: &parseState, context: "processing instruction node")
                children.append(.processingInstruction(target: target, data: data))
            default:
                break
            }
        }

        return children
    }

    private func parseDocumentMetadata(from documentPointer: xmlDocPtr?) -> XMLDocumentStructuralMetadata {
        let xmlVersion = string(fromXMLCharPointer: documentPointer?.pointee.version)
        let encoding = string(fromXMLCharPointer: documentPointer?.pointee.encoding)
        let standaloneValue = Int32(documentPointer?.pointee.standalone ?? -1)

        var doctype: XMLDoctype?
        if let dtd = documentPointer?.pointee.intSubset, let dtdName = string(fromXMLCharPointer: dtd.pointee.name) {
            let systemID = string(fromXMLCharPointer: dtd.pointee.SystemID)
            let publicID = string(fromXMLCharPointer: dtd.pointee.ExternalID)
            doctype = XMLDoctype(name: dtdName, systemID: systemID, publicID: publicID)
        }

        return XMLDocumentStructuralMetadata(
            xmlVersion: xmlVersion,
            encoding: encoding,
            standalone: standaloneValue < 0 ? nil : standaloneValue == 1,
            canonicalization: XMLCanonicalizationMetadata(),
            doctype: doctype
        )
    }

    private func parseDocumentLevelNodes(
        from documentPointer: xmlDocPtr?
    ) -> (prologue: [XMLDocumentNode], epilogue: [XMLDocumentNode]) {
        var prologueNodes: [XMLDocumentNode] = []
        var epilogueNodes: [XMLDocumentNode] = []
        var passedRoot = false

        var nodePointer = documentPointer?.pointee.children
        while let currentPointer = nodePointer {
            defer { nodePointer = currentPointer.pointee.next }

            switch currentPointer.pointee.type {
            case XML_ELEMENT_NODE:
                passedRoot = true
            case XML_PI_NODE:
                let target = string(fromXMLCharPointer: currentPointer.pointee.name) ?? ""
                let data = currentPointer.pointee.content.map {
                    String(cString: UnsafePointer<CChar>(OpaquePointer($0)))
                }
                let node = XMLDocumentNode.processingInstruction(target: target, data: data)
                if passedRoot { epilogueNodes.append(node) } else { prologueNodes.append(node) }
            case XML_COMMENT_NODE:
                let value = string(fromNodeContent: currentPointer)
                let node = XMLDocumentNode.comment(value)
                if passedRoot { epilogueNodes.append(node) } else { prologueNodes.append(node) }
            default:
                break
            }
        }

        return (prologueNodes, epilogueNodes)
    }

    private func string(fromNodeContent nodePointer: xmlNodePtr) -> String {
        guard let contentPointer = nodePointer.pointee.content else {
            return ""
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(contentPointer)))
    }

    private func normalizedTextNodeValue(_ value: String) -> String? {
        switch configuration.whitespaceTextNodePolicy {
        case .preserve:
            return value
        case .dropWhitespaceOnly:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        case .trim:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .normalizeAndTrim:
            let normalized = value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return normalized.isEmpty ? nil : normalized
        }
    }

    private func string(fromXMLCharPointer pointer: UnsafePointer<xmlChar>?) -> String? {
        guard let pointer = pointer else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(pointer)))
    }

    private func ensureDepth(_ depth: Int, parseState: inout ParseState) throws {
        let maxDepth = configuration.limits.maxDepth
        guard depth <= maxDepth else {
            configuration.logger.warning(
                "XML parse depth limit exceeded",
                metadata: ["code": "XML6_2H_MAX_DEPTH", "depth": "\(depth)", "limit": "\(maxDepth)"]
            )
            throw XMLParsingError.parseFailed(
                message:
                    "[XML6_2H_MAX_DEPTH] XML depth exceeded max depth (\(maxDepth)): \(depth)."
            )
        }

        // Warn once when depth first reaches 80% of the limit.
        if !parseState.warnedDepthApproaching {
            let threshold = (maxDepth * 4) / 5
            if depth >= threshold {
                parseState.warnedDepthApproaching = true
                configuration.logger.warning(
                    "XML parse depth approaching limit",
                    metadata: ["code": "XML6_2H_MAX_DEPTH", "depth": "\(depth)", "limit": "\(maxDepth)"]
                )
            }
        }
    }

    private func incrementNodeCount(parseState: inout ParseState, context: String) throws {
        parseState.nodeCount += 1
        if let maxNodeCount = configuration.limits.maxNodeCount {
            guard parseState.nodeCount <= maxNodeCount else {
                configuration.logger.warning(
                    "XML parse limit exceeded",
                    metadata: [
                        "code": "XML6_2H_MAX_NODE_COUNT",
                        "context": "total parsed nodes after \(context)",
                        "actual": "\(parseState.nodeCount)",
                        "limit": "\(maxNodeCount)"
                    ]
                )
                throw XMLParsingError.parseFailed(
                    message: "[XML6_2H_MAX_NODE_COUNT] total parsed nodes after \(context) exceeded max (\(maxNodeCount)): \(parseState.nodeCount)."
                )
            }
            // Warn once when node count first reaches 80% of the limit.
            if !parseState.warnedNodeCountApproaching {
                let threshold = (maxNodeCount * 4) / 5
                if parseState.nodeCount >= threshold {
                    parseState.warnedNodeCountApproaching = true
                    configuration.logger.warning(
                        "XML parse node count approaching limit",
                        metadata: [
                            "code": "XML6_2H_MAX_NODE_COUNT",
                            "nodeCount": "\(parseState.nodeCount)",
                            "limit": "\(maxNodeCount)"
                        ]
                    )
                }
            }
        }
    }

    private func ensureUTF8Length(
        _ value: String,
        limit: Int?,
        code: String,
        context: String
    ) throws {
        try ensureLimit(
            actual: value.utf8.count,
            limit: limit,
            code: code,
            context: context
        )
    }
}
