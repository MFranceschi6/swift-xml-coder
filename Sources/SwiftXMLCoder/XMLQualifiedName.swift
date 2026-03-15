import Foundation

public struct XMLQualifiedName: Sendable, Hashable, Codable {
    public let localName: String
    public let namespaceURI: String?
    public let prefix: String?

    public init(
        localName: String,
        namespaceURI: String? = nil,
        prefix: String? = nil
    ) {
        let cleanedLocalName = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNamespaceURI = namespaceURI?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.localName = cleanedLocalName
        self.namespaceURI = (cleanedNamespaceURI?.isEmpty == true) ? nil : cleanedNamespaceURI
        self.prefix = (cleanedPrefix?.isEmpty == true) ? nil : cleanedPrefix
    }

    public var qualifiedName: String {
        if let prefix = prefix {
            return "\(prefix):\(localName)"
        }
        return localName
    }
}
