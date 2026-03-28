import Foundation

/// Options that control canonicalization normalization and serialization.
public struct XMLCanonicalizationOptions: Sendable, Hashable {
    /// Determines the order in which element attributes are written.
    public let attributeOrderingPolicy: XMLTreeWriter.AttributeOrderingPolicy
    /// Determines the order in which namespace declarations are written.
    public let namespaceDeclarationOrderingPolicy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy
    /// Controls how whitespace-only text nodes are handled during normalization.
    public let whitespaceTextNodePolicy: XMLTreeWriter.WhitespaceTextNodePolicy
    /// Controls determinism guarantees for the serialized output.
    public let deterministicSerializationMode: XMLTreeWriter.DeterministicSerializationMode
    /// When `true`, XML comment nodes are preserved in the output.
    public let includeComments: Bool
    /// When `true`, processing instruction nodes are preserved in the output.
    public let includeProcessingInstructions: Bool
    /// When `true`, CDATA sections are converted to plain text nodes.
    public let convertCDATAIntoText: Bool
    /// The output encoding declaration written in the XML prolog (for example, `"UTF-8"`).
    public let outputEncoding: String
    /// When `true`, output is indented for readability.
    public let prettyPrintedOutput: Bool

    /// Creates canonicalization options with deterministic defaults.
    public init(
        attributeOrderingPolicy: XMLTreeWriter.AttributeOrderingPolicy = .lexicographical,
        namespaceDeclarationOrderingPolicy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy = .lexicographical,
        whitespaceTextNodePolicy: XMLTreeWriter.WhitespaceTextNodePolicy = .normalizeAndTrim,
        deterministicSerializationMode: XMLTreeWriter.DeterministicSerializationMode = .stable,
        includeComments: Bool = false,
        includeProcessingInstructions: Bool = false,
        convertCDATAIntoText: Bool = true,
        outputEncoding: String = "UTF-8",
        prettyPrintedOutput: Bool = false
    ) {
        self.attributeOrderingPolicy = attributeOrderingPolicy
        self.namespaceDeclarationOrderingPolicy = namespaceDeclarationOrderingPolicy
        self.whitespaceTextNodePolicy = whitespaceTextNodePolicy
        self.deterministicSerializationMode = deterministicSerializationMode
        self.includeComments = includeComments
        self.includeProcessingInstructions = includeProcessingInstructions
        self.convertCDATAIntoText = convertCDATAIntoText
        self.outputEncoding = outputEncoding
        self.prettyPrintedOutput = prettyPrintedOutput
    }
}
