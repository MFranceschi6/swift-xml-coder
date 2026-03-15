import Foundation

public struct XMLNamespaceDeclaration: Sendable, Hashable, Codable {
    public let prefix: String?
    public let uri: String

    public init(prefix: String? = nil, uri: String) {
        let cleanedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        self.prefix = (cleanedPrefix?.isEmpty == true) ? nil : cleanedPrefix
        self.uri = cleanedURI
    }
}
