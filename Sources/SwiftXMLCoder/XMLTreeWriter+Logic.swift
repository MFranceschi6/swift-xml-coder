// swiftlint:disable file_length
import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim

extension XMLTreeWriter {
    func writeDocumentImpl(_ treeDocument: XMLTreeDocument) throws -> XMLDocument {
        do {
            try XMLNamespaceValidator.validate(
                document: treeDocument,
                mode: configuration.namespaceValidationMode.validatorMode
            )
        } catch let resolutionError as XMLNamespaceResolutionError {
            throw XMLParsingError.parseFailed(
                message: "[XML6_3_NAMESPACE_VALIDATION] Namespace validation failed: \(resolutionError)."
            )
        }

        let root = treeDocument.root
        let rootNamespace = makeNamespace(from: root.name)

        let xmlDocument: XMLDocument
        if let rootNamespace = rootNamespace {
            xmlDocument = try XMLDocument(rootElementName: root.name.localName, rootNamespace: rootNamespace)
        } else {
            xmlDocument = try XMLDocument(rootElementName: root.name.localName)
        }

        guard let rootNode = xmlDocument.rootElement() else {
            throw XMLParsingError.documentCreationFailed(message: "Unable to create root element in XML document.")
        }

        try writePrologue(of: treeDocument, rootNode: rootNode)

        var writeState = WriteState()
        try writeElementContent(root, into: rootNode, in: xmlDocument, depth: 1, writeState: &writeState)
        try writeEpilogue(of: treeDocument, rootNode: rootNode)

        return xmlDocument
    }

    // swiftlint:disable:next function_body_length
    private func writeElementContent(
        _ element: XMLTreeElement,
        into node: XMLNode,
        in document: XMLDocument,
        depth: Int,
        writeState: inout WriteState
    ) throws {
        try ensureDepth(depth)
        try incrementNodeCount(writeState: &writeState, context: "element")

        try applyNamespaceDeclarations(
            orderedNamespaceDeclarations(element.namespaceDeclarations),
            to: node
        )
        try applyAttributes(
            orderedAttributes(element.attributes),
            to: node
        )

        // When expandEmptyElements is enabled, inject an empty text node into child-less elements
        // so that libxml2 emits <tag></tag> instead of <tag/>.
        if configuration.expandEmptyElements && element.children.isEmpty {
            try appendTextNode("", to: node)
        }

        for child in element.children {
            switch child {
            case .element(let childElement):
                let namespace = makeNamespace(from: childElement.name)
                let childNode = try document.createElement(
                    named: childElement.name.localName,
                    namespace: namespace
                )
                try document.appendChild(childNode, to: node)
                try writeElementContent(
                    childElement,
                    into: childNode,
                    in: document,
                    depth: depth + 1,
                    writeState: &writeState
                )
            case .text(let value):
                guard let normalizedValue = normalizedTextNodeValue(value) else {
                    continue
                }
                try ensureUTF8Length(
                    normalizedValue,
                    limit: configuration.limits.maxTextNodeBytes,
                    code: "XML6_2H_MAX_TEXT_NODE_BYTES",
                    context: "text node"
                )
                try incrementNodeCount(writeState: &writeState, context: "text node")
                try appendTextNode(normalizedValue, to: node)
            case .cdata(let value):
                try ensureUTF8Length(
                    value,
                    limit: configuration.limits.maxCDATABlockBytes,
                    code: "XML6_2H_MAX_CDATA_BYTES",
                    context: "CDATA node"
                )
                try incrementNodeCount(writeState: &writeState, context: "CDATA node")
                try appendCDATASection(value, to: node)
            case .comment(let value):
                try ensureUTF8Length(
                    value,
                    limit: configuration.limits.maxCommentBytes,
                    code: "XML6_2H_MAX_COMMENT_BYTES",
                    context: "comment node"
                )
                try incrementNodeCount(writeState: &writeState, context: "comment node")
                try appendComment(value, to: node)
            case .processingInstruction(let target, let data):
                try incrementNodeCount(writeState: &writeState, context: "processing instruction node")
                try appendProcessingInstruction(target: target, data: data, to: node)
            }
        }
    }

    private func orderedAttributes(_ attributes: [XMLTreeAttribute]) -> [XMLTreeAttribute] {
        switch resolvedAttributeOrderingPolicy() {
        case .preserve:
            return attributes
        case .lexicographical:
            return attributes.sorted { left, right in
                let leftKey = sortableQualifiedNameKey(for: left.name)
                let rightKey = sortableQualifiedNameKey(for: right.name)
                if leftKey != rightKey {
                    return leftKey < rightKey
                }
                return left.value < right.value
            }
        }
    }

    private func orderedNamespaceDeclarations(
        _ declarations: [XMLNamespaceDeclaration]
    ) -> [XMLNamespaceDeclaration] {
        switch resolvedNamespaceDeclarationOrderingPolicy() {
        case .preserve:
            return declarations
        case .lexicographical:
            return declarations.sorted { left, right in
                let leftPrefix = left.prefix ?? ""
                let rightPrefix = right.prefix ?? ""
                if leftPrefix != rightPrefix {
                    return leftPrefix < rightPrefix
                }
                return left.uri < right.uri
            }
        }
    }

    private func normalizedTextNodeValue(_ value: String) -> String? {
        switch configuration.whitespaceTextNodePolicy {
        case .preserve:
            return value
        case .omitWhitespaceOnly:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        case .trim:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .normalizeAndTrim:
            let collapsed = value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return collapsed
        }
    }

    private func resolvedAttributeOrderingPolicy() -> AttributeOrderingPolicy {
        switch configuration.deterministicSerializationMode {
        case .disabled:
            return configuration.attributeOrderingPolicy
        case .stable:
            return .lexicographical
        }
    }

    private func resolvedNamespaceDeclarationOrderingPolicy() -> NamespaceDeclarationOrderingPolicy {
        switch configuration.deterministicSerializationMode {
        case .disabled:
            return configuration.namespaceDeclarationOrderingPolicy
        case .stable:
            return .lexicographical
        }
    }

    private func sortableQualifiedNameKey(for qualifiedName: XMLQualifiedName) -> String {
        [
            qualifiedName.namespaceURI ?? "",
            qualifiedName.prefix ?? "",
            qualifiedName.localName
        ].joined(separator: "|")
    }

    private func makeNamespace(from qualifiedName: XMLQualifiedName) -> XMLNamespace? {
        guard let namespaceURI = qualifiedName.namespaceURI else {
            return nil
        }
        return XMLNamespace(prefix: qualifiedName.prefix, uri: namespaceURI)
    }

    private func applyNamespaceDeclarations(
        _ namespaceDeclarations: [XMLNamespaceDeclaration],
        to node: XMLNode
    ) throws {
        for declaration in namespaceDeclarations where shouldDeclareNamespace(declaration, on: node.nodePointer) {
            if declaration.prefix != nil && declaration.uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XMLParsingError.invalidNamespaceConfiguration(prefix: declaration.prefix, uri: declaration.uri)
            }

            let namespacePointer = LibXML2.withXMLCharPointer(declaration.uri) { uriPointer -> xmlNsPtr? in
                if let prefix = declaration.prefix {
                    return LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                        xmlNewNs(node.nodePointer, uriPointer, prefixPointer)
                    }
                }
                return xmlNewNs(node.nodePointer, uriPointer, nil)
            }

            guard namespacePointer != nil else {
                throw XMLParsingError.nodeOperationFailed(
                    message: "Unable to declare namespace '\(declaration.uri)' on '\(node.name ?? "<unknown>")'."
                )
            }
        }
    }

    private func applyAttributes(_ attributes: [XMLTreeAttribute], to node: XMLNode) throws {
        var generatedNamespaceIndex = 0

        for attribute in attributes {
            if let prefix = attribute.name.prefix, attribute.name.namespaceURI == nil {
                throw XMLParsingError.invalidNamespaceConfiguration(prefix: prefix, uri: nil)
            }

            let attributeNamespace = try resolveAttributeNamespace(
                for: attribute,
                on: node.nodePointer,
                generatedNamespaceIndex: &generatedNamespaceIndex
            )

            let setResult = LibXML2.withXMLCharPointer(attribute.name.localName) { attributeNamePointer in
                LibXML2.withXMLCharPointer(attribute.value) { valuePointer -> xmlAttrPtr? in
                    if let attributeNamespace = attributeNamespace {
                        return xmlSetNsProp(node.nodePointer, attributeNamespace, attributeNamePointer, valuePointer)
                    }
                    return xmlSetProp(node.nodePointer, attributeNamePointer, valuePointer)
                }
            }

            guard setResult != nil else {
                throw XMLParsingError.nodeOperationFailed(
                    message:
                        "Unable to set attribute '\(attribute.name.qualifiedName)' on '\(node.name ?? "<unknown>")'."
                )
            }
        }
    }

    private func resolveAttributeNamespace(
        for attribute: XMLTreeAttribute,
        on nodePointer: xmlNodePtr,
        generatedNamespaceIndex: inout Int
    ) throws -> xmlNsPtr? {
        guard let namespaceURI = attribute.name.namespaceURI else {
            return nil
        }

        if let prefix = attribute.name.prefix {
            if let existing = lookupNamespace(prefix: prefix, uri: namespaceURI, nodePointer: nodePointer) {
                return existing
            }
            return try declareNamespace(prefix: prefix, uri: namespaceURI, on: nodePointer)
        }

        if let existing = lookupNamespaceByURI(uri: namespaceURI, nodePointer: nodePointer) {
            return existing
        }

        let generatedPrefix = makeGeneratedNamespacePrefix(
            for: nodePointer,
            startingAt: &generatedNamespaceIndex
        )
        return try declareNamespace(prefix: generatedPrefix, uri: namespaceURI, on: nodePointer)
    }

    private func lookupNamespace(prefix: String, uri: String, nodePointer: xmlNodePtr) -> xmlNsPtr? {
        guard let documentPointer = nodePointer.pointee.doc else {
            return nil
        }

        let namespaceByPrefix = LibXML2.withXMLCharPointer(prefix) { prefixPointer in
            xmlSearchNs(documentPointer, nodePointer, prefixPointer)
        }
        guard let namespaceByPrefix = namespaceByPrefix else {
            return nil
        }

        let namespaceURI = string(fromXMLCharPointer: namespaceByPrefix.pointee.href)
        return namespaceURI == uri ? namespaceByPrefix : nil
    }

    private func lookupNamespaceByURI(uri: String, nodePointer: xmlNodePtr) -> xmlNsPtr? {
        guard let documentPointer = nodePointer.pointee.doc else {
            return nil
        }
        return LibXML2.withXMLCharPointer(uri) { uriPointer in
            xmlSearchNsByHref(documentPointer, nodePointer, uriPointer)
        }
    }

    private func declareNamespace(prefix: String, uri: String, on nodePointer: xmlNodePtr) throws -> xmlNsPtr {
        let namespacePointer = LibXML2.withXMLCharPointer(uri) { uriPointer in
            LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                xmlNewNs(nodePointer, uriPointer, prefixPointer)
            }
        }

        guard let namespacePointer = namespacePointer else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to declare namespace '\(prefix):\(uri)'."
            )
        }
        return namespacePointer
    }

    private func makeGeneratedNamespacePrefix(
        for nodePointer: xmlNodePtr,
        startingAt index: inout Int
    ) -> String {
        while true {
            let candidate = "ns\(index)"
            index += 1

            let existing = LibXML2.withXMLCharPointer(candidate) { prefixPointer in
                xmlSearchNs(nodePointer.pointee.doc, nodePointer, prefixPointer)
            }
            if existing == nil {
                return candidate
            }
        }
    }

    private func shouldDeclareNamespace(_ declaration: XMLNamespaceDeclaration, on nodePointer: xmlNodePtr) -> Bool {
        var namespacePointer = nodePointer.pointee.nsDef
        while let currentNamespacePointer = namespacePointer {
            let existingPrefix = string(fromXMLCharPointer: currentNamespacePointer.pointee.prefix)
            let existingURI = string(fromXMLCharPointer: currentNamespacePointer.pointee.href)
            if existingPrefix == declaration.prefix && existingURI == declaration.uri {
                return false
            }
            namespacePointer = currentNamespacePointer.pointee.next
        }
        return true
    }

    private func appendTextNode(_ value: String, to node: XMLNode) throws {
        let textNodePointer = LibXML2.withXMLCharPointer(value) { valuePointer in
            xmlNewText(valuePointer)
        }
        guard let textNodePointer = textNodePointer else {
            throw XMLParsingError.nodeCreationFailed(name: "#text", message: "Unable to create text node.")
        }

        guard xmlAddChild(node.nodePointer, textNodePointer) != nil else {
            xmlFreeNode(textNodePointer)
            throw XMLParsingError.nodeOperationFailed(message: "Unable to append text node.")
        }
    }

    private func appendCDATASection(_ value: String, to node: XMLNode) throws {
        guard let documentPointer = node.nodePointer.pointee.doc else {
            throw XMLParsingError.nodeOperationFailed(message: "Unable to resolve XML document for CDATA section.")
        }

        let utf8Bytes = Array(value.utf8)
        let cdataLength = try XMLInteropBounds.checkedNonNegativeInt32Length(
            utf8Bytes.count,
            code: "XML6_2H_INT32_CDATA_LENGTH",
            context: "xmlNewCDataBlock input"
        )

        let cdataNodePointer = utf8Bytes.withUnsafeBufferPointer { buffer -> xmlNodePtr? in
            guard let baseAddress = buffer.baseAddress else {
                return xmlNewCDataBlock(documentPointer, nil, 0)
            }
            return xmlNewCDataBlock(
                documentPointer,
                UnsafePointer<xmlChar>(baseAddress),
                cdataLength
            )
        }

        guard let cdataNodePointer = cdataNodePointer else {
            throw XMLParsingError.nodeCreationFailed(
                name: "#cdata-section",
                message: "Unable to create CDATA section."
            )
        }

        guard xmlAddChild(node.nodePointer, cdataNodePointer) != nil else {
            xmlFreeNode(cdataNodePointer)
            throw XMLParsingError.nodeOperationFailed(message: "Unable to append CDATA section.")
        }
    }

    private func appendComment(_ value: String, to node: XMLNode) throws {
        let commentNodePointer = LibXML2.withXMLCharPointer(value) { valuePointer in
            xmlNewComment(valuePointer)
        }
        guard let commentNodePointer = commentNodePointer else {
            throw XMLParsingError.nodeCreationFailed(name: "#comment", message: "Unable to create XML comment.")
        }

        guard xmlAddChild(node.nodePointer, commentNodePointer) != nil else {
            xmlFreeNode(commentNodePointer)
            throw XMLParsingError.nodeOperationFailed(message: "Unable to append XML comment.")
        }
    }

    private func appendProcessingInstruction(target: String, data: String?, to node: XMLNode) throws {
        let piPointer: xmlNodePtr?
        if let data = data {
            piPointer = LibXML2.withXMLCharPointer(target) { targetPointer in
                LibXML2.withXMLCharPointer(data) { dataPointer in
                    xmlNewPI(targetPointer, dataPointer)
                }
            }
        } else {
            piPointer = LibXML2.withXMLCharPointer(target) { targetPointer in
                xmlNewPI(targetPointer, nil)
            }
        }
        guard let piPointer = piPointer else {
            throw XMLParsingError.nodeCreationFailed(
                name: target,
                message: "Unable to create processing instruction '<?\\(target)?>'."
            )
        }
        guard xmlAddChild(node.nodePointer, piPointer) != nil else {
            xmlFreeNode(piPointer)
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to append processing instruction '<?\\(target)?>'."
            )
        }
    }

    @discardableResult
    private func writeDocumentLevelNode(
        _ node: XMLDocumentNode,
        asPrevSiblingOf referenceNode: XMLNode
    ) throws -> xmlNodePtr {
        let newPointer = try makeDocumentLevelNodePointer(node)
        guard xmlAddPrevSibling(referenceNode.nodePointer, newPointer) != nil else {
            xmlFreeNode(newPointer)
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to insert document-level node before root element."
            )
        }
        return newPointer
    }

    @discardableResult
    private func writeDocumentLevelNode(
        _ node: XMLDocumentNode,
        asNextSiblingOf referencePointer: xmlNodePtr
    ) throws -> xmlNodePtr {
        let newPointer = try makeDocumentLevelNodePointer(node)
        guard xmlAddNextSibling(referencePointer, newPointer) != nil else {
            xmlFreeNode(newPointer)
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to insert document-level node after root element."
            )
        }
        return newPointer
    }

    private func writePrologue(of document: XMLTreeDocument, rootNode: XMLNode) throws {
        if let doctype = document.metadata.doctype {
            try writeDoctype(doctype, toDocumentOf: rootNode)
        }
        for node in document.prologueNodes {
            try writeDocumentLevelNode(node, asPrevSiblingOf: rootNode)
        }
    }

    private func writeEpilogue(of document: XMLTreeDocument, rootNode: XMLNode) throws {
        var lastPointer = rootNode.nodePointer
        for node in document.epilogueNodes {
            lastPointer = try writeDocumentLevelNode(node, asNextSiblingOf: lastPointer)
        }
    }

    private func makeDocumentLevelNodePointer(_ node: XMLDocumentNode) throws -> xmlNodePtr {
        switch node {
        case .comment(let value):
            guard let pointer = LibXML2.withXMLCharPointer(value, { xmlNewComment($0) }) else {
                throw XMLParsingError.nodeCreationFailed(
                    name: "#comment",
                    message: "Unable to create document-level XML comment."
                )
            }
            return pointer
        case .processingInstruction(let target, let data):
            let pointer: xmlNodePtr?
            if let data = data {
                pointer = LibXML2.withXMLCharPointer(target) { targetPointer in
                    LibXML2.withXMLCharPointer(data) { dataPointer in
                        xmlNewPI(targetPointer, dataPointer)
                    }
                }
            } else {
                pointer = LibXML2.withXMLCharPointer(target) { xmlNewPI($0, nil) }
            }
            guard let pointer = pointer else {
                throw XMLParsingError.nodeCreationFailed(
                    name: target,
                    message: "Unable to create document-level processing instruction '<?\\(target)?>'."
                )
            }
            return pointer
        }
    }

    private func writeDoctype(_ doctype: XMLDoctype, toDocumentOf node: XMLNode) throws {
        guard let docPointer = node.nodePointer.pointee.doc else {
            throw XMLParsingError.nodeOperationFailed(
                message: "Unable to resolve XML document pointer for DOCTYPE creation."
            )
        }
        let result: xmlDtdPtr?
        if let publicID = doctype.publicID {
            result = LibXML2.withXMLCharPointer(doctype.name) { namePointer in
                LibXML2.withXMLCharPointer(publicID) { publicPointer in
                    if let systemID = doctype.systemID {
                        return LibXML2.withXMLCharPointer(systemID) { systemPointer in
                            xmlCreateIntSubset(docPointer, namePointer, publicPointer, systemPointer)
                        }
                    }
                    return xmlCreateIntSubset(docPointer, namePointer, publicPointer, nil)
                }
            }
        } else if let systemID = doctype.systemID {
            result = LibXML2.withXMLCharPointer(doctype.name) { namePointer in
                LibXML2.withXMLCharPointer(systemID) { systemPointer in
                    xmlCreateIntSubset(docPointer, namePointer, nil, systemPointer)
                }
            }
        } else {
            result = LibXML2.withXMLCharPointer(doctype.name) { namePointer in
                xmlCreateIntSubset(docPointer, namePointer, nil, nil)
            }
        }
        guard result != nil else {
            throw XMLParsingError.nodeCreationFailed(
                name: doctype.name,
                message: "Unable to create DOCTYPE declaration for '\\(doctype.name)'."
            )
        }
    }

    private func string(fromXMLCharPointer pointer: UnsafePointer<xmlChar>?) -> String? {
        guard let pointer = pointer else {
            return nil
        }
        return String(cString: UnsafePointer<CChar>(OpaquePointer(pointer)))
    }

    private func ensureDepth(_ depth: Int) throws {
        guard depth <= configuration.limits.maxDepth else {
            throw XMLParsingError.parseFailed(
                message:
                    "[XML6_2H_MAX_DEPTH] XML depth exceeded max depth (\(configuration.limits.maxDepth)): \(depth)."
            )
        }
    }

    private func incrementNodeCount(writeState: inout WriteState, context: String) throws {
        writeState.nodeCount += 1
        try ensureLimit(
            actual: writeState.nodeCount,
            limit: configuration.limits.maxNodeCount,
            code: "XML6_2H_MAX_NODE_COUNT",
            context: "total written nodes after \(context)"
        )
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
            throw XMLParsingError.parseFailed(
                message: "[\(code)] \(context) exceeded max (\(limit)): \(actual)."
            )
        }
    }
}
