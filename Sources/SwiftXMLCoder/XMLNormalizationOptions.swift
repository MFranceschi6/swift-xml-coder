import Foundation

/// Options that control how an XML tree is normalised and serialised during canonicalization.
///
/// Pass an instance to ``XMLCanonicalizer/canonicalView(for:options:transforms:)`` to customise
/// attribute ordering, whitespace handling, comment inclusion, CDATA conversion, and encoding.
public struct XMLNormalizationOptions: Sendable, Hashable {
    /// Determines the order in which element attributes are written.
    public let attributeOrderingPolicy: XMLTreeWriter.AttributeOrderingPolicy
    /// Determines the order in which namespace declarations are written.
    public let namespaceDeclarationOrderingPolicy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy
    /// Controls how whitespace-only text nodes are handled during normalisation.
    public let whitespaceTextNodePolicy: XMLTreeWriter.WhitespaceTextNodePolicy
    /// Controls determinism guarantees for the serialised output.
    public let deterministicSerializationMode: XMLTreeWriter.DeterministicSerializationMode
    /// When `true`, XML comment nodes are preserved in the output. Defaults to `false`.
    public let includeComments: Bool
    /// When `true`, CDATA sections are converted to plain text nodes. Defaults to `true`.
    public let convertCDATAIntoText: Bool
    /// The output encoding declaration written in the XML prolog (e.g. `"UTF-8"`).
    public let outputEncoding: String
    /// When `true`, the output is indented for human readability. Defaults to `false`.
    public let prettyPrintedOutput: Bool

    /// Creates a normalisation options value.
    ///
    /// All parameters have canonical defaults suitable for deterministic output.
    public init(
        attributeOrderingPolicy: XMLTreeWriter.AttributeOrderingPolicy = .lexicographical,
        namespaceDeclarationOrderingPolicy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy = .lexicographical,
        whitespaceTextNodePolicy: XMLTreeWriter.WhitespaceTextNodePolicy = .normalizeAndTrim,
        deterministicSerializationMode: XMLTreeWriter.DeterministicSerializationMode = .stable,
        includeComments: Bool = false,
        convertCDATAIntoText: Bool = true,
        outputEncoding: String = "UTF-8",
        prettyPrintedOutput: Bool = false
    ) {
        self.attributeOrderingPolicy = attributeOrderingPolicy
        self.namespaceDeclarationOrderingPolicy = namespaceDeclarationOrderingPolicy
        self.whitespaceTextNodePolicy = whitespaceTextNodePolicy
        self.deterministicSerializationMode = deterministicSerializationMode
        self.includeComments = includeComments
        self.convertCDATAIntoText = convertCDATAIntoText
        self.outputEncoding = outputEncoding
        self.prettyPrintedOutput = prettyPrintedOutput
    }
}
