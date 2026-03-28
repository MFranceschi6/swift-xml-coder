import Foundation

/// The default ``XMLCanonicalizer`` implementation.
public struct XMLDefaultCanonicalizer: XMLCanonicalizer {
    /// Creates a default canonicalizer.
    public init() {}

    // MARK: - Tree-based API

    public func canonicalize(
        _ document: XMLTreeDocument,
        options: XMLCanonicalizationOptions,
        transforms: XMLTransformPipeline = []
    ) throws -> Data {
        let transformedDocument = try applyTreeTransforms(
            to: document,
            options: options,
            transforms: transforms
        )

        let normalizedDocument = normalize(document: transformedDocument, options: options)
        let writer = XMLTreeWriter(configuration: writerConfiguration(for: options))
        return try writer.writeData(normalizedDocument)
    }

    /// Convenience tree-based canonicalization with full defaults.
    public func canonicalize(_ document: XMLTreeDocument) throws -> Data {
        try canonicalize(
            document,
            options: XMLCanonicalizationOptions(),
            transforms: []
        )
    }

    // MARK: - Stream-based API

    public func canonicalize(
        data: Data,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws {
        var parsedEvents: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: data) { event in
            parsedEvents.append(event)
        }

        try canonicalize(
            events: parsedEvents,
            options: options,
            eventTransforms: eventTransforms,
            output: output
        )
    }

    public func canonicalize<S: Sequence>(
        events: S,
        options: XMLCanonicalizationOptions,
        eventTransforms: XMLEventTransformPipeline,
        output: (Data) throws -> Void
    ) throws where S.Element == XMLStreamEvent {
        // The sink's closure is @escaping but its lifetime is bounded to this scope.
        try withoutActuallyEscaping(output) { escapableOutput in
            let sink = try XMLStreamWriterSink(
                configuration: streamWriterConfiguration(for: options),
                output: escapableOutput
            )
            var transforms = eventTransforms

            for event in events {
                let produced = try runPipeline(
                    initialEvents: [event],
                    through: &transforms,
                    startIndex: 0
                )
                try writeNormalized(produced, options: options, sink: sink)
            }

            for index in transforms.indices {
                let finalizedEvents: [XMLStreamEvent]
                do {
                    finalizedEvents = try transforms[index].finalize()
                } catch let parsingError as XMLParsingError {
                    throw parsingError
                } catch {
                    throw XMLParsingError.other(
                        underlyingError: error,
                        message: "[XML6_9_CANONICAL_EVENT_TRANSFORM_FAILED] Event transform finalize #\(index) failed."
                    )
                }

                let downstream = try runPipeline(
                    initialEvents: finalizedEvents,
                    through: &transforms,
                    startIndex: index + 1
                )
                try writeNormalized(downstream, options: options, sink: sink)
            }

            try sink.finish()
        }
    }

    /// Convenience stream-based canonicalization from raw XML data that returns `Data`.
    public func canonicalize(
        data: Data,
        options: XMLCanonicalizationOptions = XMLCanonicalizationOptions(),
        eventTransforms: XMLEventTransformPipeline = []
    ) throws -> Data {
        var chunks: [Data] = []
        try canonicalize(data: data, options: options, eventTransforms: eventTransforms) { chunk in
            chunks.append(chunk)
        }
        return chunks.reduce(into: Data(), { $0.append($1) })
    }

    /// Convenience stream-based canonicalization from pre-parsed events that returns `Data`.
    public func canonicalize<S: Sequence>(
        events: S,
        options: XMLCanonicalizationOptions = XMLCanonicalizationOptions(),
        eventTransforms: XMLEventTransformPipeline = []
    ) throws -> Data where S.Element == XMLStreamEvent {
        var chunks: [Data] = []
        try canonicalize(events: events, options: options, eventTransforms: eventTransforms) { chunk in
            chunks.append(chunk)
        }
        return chunks.reduce(into: Data(), { $0.append($1) })
    }

    private func applyTreeTransforms(
        to document: XMLTreeDocument,
        options: XMLCanonicalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> XMLTreeDocument {
        var current = document
        for (index, transform) in transforms.enumerated() {
            do {
                current = try transform.apply(to: current, options: options)
            } catch let parsingError as XMLParsingError {
                throw parsingError
            } catch {
                throw XMLParsingError.other(
                    underlyingError: error,
                    message: "[XML6_9_CANONICAL_TRANSFORM_FAILED] Tree transform #\(index) (\(String(describing: type(of: transform)))) failed."
                )
            }
        }
        return current
    }

    // MARK: - Normalization helpers

    private func writerConfiguration(for options: XMLCanonicalizationOptions) -> XMLTreeWriter.Configuration {
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

    private func streamWriterConfiguration(for options: XMLCanonicalizationOptions) -> XMLStreamWriter.Configuration {
        XMLStreamWriter.Configuration(
            encoding: options.outputEncoding,
            prettyPrinted: options.prettyPrintedOutput,
            expandEmptyElements: true,
            limits: XMLStreamWriter.WriterLimits()
        )
    }

    private func normalize(
        document: XMLTreeDocument,
        options: XMLCanonicalizationOptions
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
            canonicalization: canonicalizationMetadata,
            doctype: document.metadata.doctype
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
        options: XMLCanonicalizationOptions
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
        options: XMLCanonicalizationOptions
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
        options: XMLCanonicalizationOptions
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

    // MARK: - Event pipeline

    private func writeNormalized(
        _ events: [XMLStreamEvent],
        options: XMLCanonicalizationOptions,
        sink: XMLStreamWriterSink
    ) throws {
        for event in events {
            if let normalized = normalize(event: event, options: options) {
                try sink.write(normalized)
            }
        }
    }

    private func runPipeline(
        initialEvents: [XMLStreamEvent],
        through transforms: inout XMLEventTransformPipeline,
        startIndex: Int
    ) throws -> [XMLStreamEvent] {
        guard startIndex < transforms.count else {
            return initialEvents
        }

        var stageEvents = initialEvents
        for index in transforms.indices where index >= startIndex {
            var nextEvents: [XMLStreamEvent] = []
            for event in stageEvents {
                let produced: [XMLStreamEvent]
                do {
                    produced = try transforms[index].process(event)
                } catch let parsingError as XMLParsingError {
                    throw parsingError
                } catch {
                    throw XMLParsingError.other(
                        underlyingError: error,
                        message: "[XML6_9_CANONICAL_EVENT_TRANSFORM_FAILED] Event transform #\(index) failed."
                    )
                }
                nextEvents.append(contentsOf: produced)
            }
            stageEvents = nextEvents
        }
        return stageEvents
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func normalize(
        event: XMLStreamEvent,
        options: XMLCanonicalizationOptions
    ) -> XMLStreamEvent? {
        switch event {
        case .startDocument(let version, _, let standalone):
            return .startDocument(version: version, encoding: options.outputEncoding, standalone: standalone)
        case .endDocument:
            return .endDocument
        case .startElement(let name, let attributes, let namespaceDeclarations):
            return .startElement(
                name: name,
                attributes: orderedAttributes(attributes, policy: options.attributeOrderingPolicy),
                namespaceDeclarations: orderedNamespaceDeclarations(
                    namespaceDeclarations,
                    policy: options.namespaceDeclarationOrderingPolicy
                )
            )
        case .endElement(let name):
            return .endElement(name: name)
        case .text(let value):
            guard let normalized = normalizeText(value, policy: options.whitespaceTextNodePolicy) else {
                return nil
            }
            return .text(normalized)
        case .cdata(let value):
            if options.convertCDATAIntoText {
                guard let normalized = normalizeText(value, policy: options.whitespaceTextNodePolicy) else {
                    return nil
                }
                return .text(normalized)
            }
            return .cdata(value)
        case .comment(let value):
            guard options.includeComments else { return nil }
            return .comment(value)
        case .processingInstruction(let target, let data):
            guard options.includeProcessingInstructions else { return nil }
            return .processingInstruction(target: target, data: data)
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
