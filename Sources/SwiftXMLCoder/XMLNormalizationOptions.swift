import Foundation

public struct XMLNormalizationOptions: Sendable, Hashable {
    public let attributeOrderingPolicy: XMLTreeWriter.AttributeOrderingPolicy
    public let namespaceDeclarationOrderingPolicy: XMLTreeWriter.NamespaceDeclarationOrderingPolicy
    public let whitespaceTextNodePolicy: XMLTreeWriter.WhitespaceTextNodePolicy
    public let deterministicSerializationMode: XMLTreeWriter.DeterministicSerializationMode
    public let includeComments: Bool
    public let convertCDATAIntoText: Bool
    public let outputEncoding: String
    public let prettyPrintedOutput: Bool

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
