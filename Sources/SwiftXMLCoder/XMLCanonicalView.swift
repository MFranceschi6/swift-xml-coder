import Foundation

/// The result of a canonicalization pass: the normalised tree and the canonical byte sequence.
///
/// Returned by ``XMLCanonicalizer/canonicalView(for:options:transforms:)``.
/// The ``canonicalXMLData`` is deterministic: identical logical documents produce identical bytes.
public struct XMLCanonicalView: Sendable, Equatable {
    /// The normalised ``XMLTreeDocument`` after all transforms have been applied.
    public let normalizedDocument: XMLTreeDocument
    /// The canonical XML representation as UTF-8 encoded bytes.
    public let canonicalXMLData: Data

    /// Creates a canonical view.
    /// - Parameters:
    ///   - normalizedDocument: The post-transform tree.
    ///   - canonicalXMLData: The deterministic XML byte sequence.
    public init(normalizedDocument: XMLTreeDocument, canonicalXMLData: Data) {
        self.normalizedDocument = normalizedDocument
        self.canonicalXMLData = canonicalXMLData
    }
}
