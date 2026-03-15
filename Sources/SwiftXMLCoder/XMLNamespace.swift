import Foundation

/// An XML namespace binding: an optional prefix and a required URI.
///
/// A `nil` prefix represents the default namespace (`xmlns="..."`).
/// A non-`nil` prefix represents a prefixed namespace (`xmlns:prefix="..."`).
public struct XMLNamespace: Sendable {
    /// The namespace prefix, or `nil` for the default namespace.
    public let prefix: String?
    /// The namespace URI (e.g. `"http://www.w3.org/2001/XMLSchema"`).
    public let uri: String

    /// Creates an XML namespace.
    /// - Parameters:
    ///   - prefix: The namespace prefix. Pass `nil` for the default namespace.
    ///   - uri: The namespace URI.
    public init(prefix: String? = nil, uri: String) {
        let normalizedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPrefix = (normalizedPrefix?.isEmpty == true) ? nil : normalizedPrefix

        self.prefix = cleanedPrefix
        self.uri = uri
    }
}
