import Foundation

/// A namespace declaration that binds an optional prefix to a namespace URI.
///
/// A `nil` prefix represents the default namespace (`xmlns="..."`).
/// A non-nil prefix represents a prefixed declaration (`xmlns:foo="..."`).
public struct XMLNamespaceDeclaration: Sendable, Hashable, Codable {
    /// The namespace prefix, or `nil` for the default namespace.
    public let prefix: String?
    /// The namespace URI bound to ``prefix``.
    public let uri: String

    /// Creates a namespace declaration.
    ///
    /// Leading/trailing whitespace is trimmed from both `prefix` and `uri`.
    /// An empty prefix (after trimming) is treated as `nil`.
    ///
    /// - Parameters:
    ///   - prefix: The namespace prefix, or `nil` for the default namespace.
    ///   - uri: The namespace URI.
    public init(prefix: String? = nil, uri: String) {
        let cleanedPrefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        self.prefix = (cleanedPrefix?.isEmpty == true) ? nil : cleanedPrefix
        self.uri = cleanedURI
    }
}
