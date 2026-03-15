import Foundation

public struct XMLNamespace: Sendable {
    public let prefix: String?
    public let uri: String

    public init(prefix: String? = nil, uri: String) {
        let normalizedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPrefix = (normalizedPrefix?.isEmpty == true) ? nil : normalizedPrefix

        self.prefix = cleanedPrefix
        self.uri = uri
    }
}
