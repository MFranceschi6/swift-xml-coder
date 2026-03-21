import Foundation

public struct XMLCanonicalizationMetadata: Sendable, Equatable, Codable {
    public let attributeOrderIsSignificant: Bool
    public let namespaceOrderIsSignificant: Bool
    public let whitespaceIsSignificant: Bool

    public init(
        attributeOrderIsSignificant: Bool = false,
        namespaceOrderIsSignificant: Bool = false,
        whitespaceIsSignificant: Bool = true
    ) {
        self.attributeOrderIsSignificant = attributeOrderIsSignificant
        self.namespaceOrderIsSignificant = namespaceOrderIsSignificant
        self.whitespaceIsSignificant = whitespaceIsSignificant
    }
}

public struct XMLNodeStructuralMetadata: Sendable, Equatable, Codable {
    public let sourceOrder: Int?
    public let originalPrefix: String?
    public let wasSelfClosing: Bool?
    /// Source line number of the opening tag in the original XML document, if available.
    ///
    /// Populated from libxml2's `xmlGetLineNo` during parsing. `nil` when the element was
    /// constructed programmatically rather than parsed from XML bytes.
    public let sourceLine: Int?

    public init(
        sourceOrder: Int? = nil,
        originalPrefix: String? = nil,
        wasSelfClosing: Bool? = nil,
        sourceLine: Int? = nil
    ) {
        self.sourceOrder = sourceOrder
        self.originalPrefix = originalPrefix
        self.wasSelfClosing = wasSelfClosing
        self.sourceLine = sourceLine
    }
}

public struct XMLDocumentStructuralMetadata: Sendable, Equatable, Codable {
    public let xmlVersion: String?
    public let encoding: String?
    public let standalone: Bool?
    public let canonicalization: XMLCanonicalizationMetadata

    public init(
        xmlVersion: String? = nil,
        encoding: String? = nil,
        standalone: Bool? = nil,
        canonicalization: XMLCanonicalizationMetadata = XMLCanonicalizationMetadata()
    ) {
        self.xmlVersion = xmlVersion
        self.encoding = encoding
        self.standalone = standalone
        self.canonicalization = canonicalization
    }
}
