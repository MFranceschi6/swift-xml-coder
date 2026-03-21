import Foundation

extension XMLDefaultCanonicalizer {
    func canonicalViewImpl(
        for document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> XMLCanonicalView {
        let transformedDocument = try XMLCanonicalizationContract.applyTransforms(
            to: document,
            options: options,
            transforms: transforms
        )

        let normalizedDocument = normalize(document: transformedDocument, options: options)
        let writer = XMLTreeWriter(configuration: writerConfiguration(for: options))
        let data: Data
        do {
            data = try writer.writeData(normalizedDocument)
        } catch {
            throw XMLCanonicalizationContract.serializationFailure(underlyingError: error)
        }

        return XMLCanonicalView(normalizedDocument: normalizedDocument, canonicalXMLData: data)
    }

    private func writerConfiguration(for options: XMLNormalizationOptions) -> XMLTreeWriter.Configuration {
        XMLTreeWriter.Configuration(
            encoding: options.outputEncoding,
            prettyPrinted: options.prettyPrintedOutput,
            attributeOrderingPolicy: options.attributeOrderingPolicy,
            namespaceDeclarationOrderingPolicy: options.namespaceDeclarationOrderingPolicy,
            whitespaceTextNodePolicy: options.whitespaceTextNodePolicy,
            deterministicSerializationMode: options.deterministicSerializationMode,
            namespaceValidationMode: .strict,
            limits: XMLTreeWriter.Limits()
        )
    }

    private func normalize(
        document: XMLTreeDocument,
        options: XMLNormalizationOptions
    ) -> XMLTreeDocument {
        let normalizedRoot = normalize(element: document.root, options: options)
        let canonicalizationMetadata = XMLCanonicalizationMetadata(
            attributeOrderIsSignificant: false,
            namespaceOrderIsSignificant: false,
            whitespaceIsSignificant: options.whitespaceTextNodePolicy == .preserve
        )
        let normalizedMetadata = XMLDocumentStructuralMetadata(
            xmlVersion: document.metadata.xmlVersion,
            encoding: document.metadata.encoding,
            standalone: document.metadata.standalone,
            canonicalization: canonicalizationMetadata
        )
        let normalizedPrologueNodes = normalizeDocumentLevelNodes(document.prologueNodes, options: options)
        let normalizedEpilogueNodes = normalizeDocumentLevelNodes(document.epilogueNodes, options: options)
        return XMLTreeDocument(
            root: normalizedRoot,
            metadata: normalizedMetadata,
            prologueNodes: normalizedPrologueNodes,
            epilogueNodes: normalizedEpilogueNodes
        )
    }

    private func normalize(
        element: XMLTreeElement,
        options: XMLNormalizationOptions
    ) -> XMLTreeElement {
        let normalizedAttributes = orderedAttributes(element.attributes, policy: options.attributeOrderingPolicy)
        let normalizedNamespaceDeclarations = orderedNamespaceDeclarations(
            element.namespaceDeclarations,
            policy: options.namespaceDeclarationOrderingPolicy
        )
        let normalizedChildren = normalize(children: element.children, options: options)

        return XMLTreeElement(
            name: element.name,
            attributes: normalizedAttributes,
            namespaceDeclarations: normalizedNamespaceDeclarations,
            children: normalizedChildren,
            metadata: element.metadata
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func normalize(
        children: [XMLTreeNode],
        options: XMLNormalizationOptions
    ) -> [XMLTreeNode] {
        var normalizedChildren: [XMLTreeNode] = []
        normalizedChildren.reserveCapacity(children.count)

        for child in children {
            switch child {
            case .element(let element):
                normalizedChildren.append(.element(normalize(element: element, options: options)))
            case .text(let value):
                if let normalizedText = normalizeText(value, policy: options.whitespaceTextNodePolicy) {
                    normalizedChildren.append(.text(normalizedText))
                }
            case .cdata(let value):
                if options.convertCDATAIntoText {
                    if let normalizedText = normalizeText(value, policy: options.whitespaceTextNodePolicy) {
                        normalizedChildren.append(.text(normalizedText))
                    }
                } else {
                    normalizedChildren.append(.cdata(value))
                }
            case .comment(let value):
                if options.includeComments {
                    normalizedChildren.append(.comment(value))
                }
            case .processingInstruction(let target, let data):
                if options.includeProcessingInstructions {
                    normalizedChildren.append(.processingInstruction(target: target, data: data))
                }
            }
        }

        return normalizedChildren
    }

    private func normalizeDocumentLevelNodes(
        _ nodes: [XMLDocumentNode],
        options: XMLNormalizationOptions
    ) -> [XMLDocumentNode] {
        nodes.filter { node in
            switch node {
            case .comment:
                return options.includeComments
            case .processingInstruction:
                return options.includeProcessingInstructions
            }
        }
    }

    private func normalizeText(
        _ value: String,
        policy: XMLTreeWriter.WhitespaceTextNodePolicy
    ) -> String? {
        switch policy {
        case .preserve:
            return value
        case .omitWhitespaceOnly:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        case .trim:
            return normalizedTrimmedText(value)
        case .normalizeAndTrim:
            let normalized = value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return normalized.isEmpty ? nil : normalized
        }
    }

    private func normalizedTrimmedText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func orderedAttributes(
        _ attributes: [XMLTreeAttribute],
        policy: XMLTreeWriter.AttributeOrderingPolicy
    ) -> [XMLTreeAttribute] {
        switch policy {
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
        _ declarations: [XMLNamespaceDeclaration],
        policy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy
    ) -> [XMLNamespaceDeclaration] {
        switch policy {
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

    private func sortableQualifiedNameKey(for qualifiedName: XMLQualifiedName) -> String {
        [
            qualifiedName.namespaceURI ?? "",
            qualifiedName.prefix ?? "",
            qualifiedName.localName
        ].joined(separator: "|")
    }
}
