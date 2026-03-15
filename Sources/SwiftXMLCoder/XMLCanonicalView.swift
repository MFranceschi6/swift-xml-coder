import Foundation

public struct XMLCanonicalView: Sendable, Equatable {
    public let normalizedDocument: XMLTreeDocument
    public let canonicalXMLData: Data

    public init(normalizedDocument: XMLTreeDocument, canonicalXMLData: Data) {
        self.normalizedDocument = normalizedDocument
        self.canonicalXMLData = canonicalXMLData
    }
}
