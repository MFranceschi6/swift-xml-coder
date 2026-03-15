import Foundation

/// An XML qualified name consisting of a local name, optional namespace URI, and optional prefix.
///
/// Qualified names appear on element and attribute nodes. A name without a prefix and namespace
/// is a simple local name. A name with both prefix and URI is fully qualified:
///
/// ```swift
/// let name = XMLQualifiedName(localName: "body",
///                             namespaceURI: "http://schemas.xmlsoap.org/soap/envelope/",
///                             prefix: "soap")
/// print(name.qualifiedName) // "soap:body"
/// ```
public struct XMLQualifiedName: Sendable, Hashable, Codable {
    /// The local part of the name (without prefix).
    public let localName: String
    /// The namespace URI, or `nil` for an unqualified name.
    public let namespaceURI: String?
    /// The namespace prefix (e.g. `"soap"`), or `nil` for an unprefixed name.
    public let prefix: String?

    /// Creates a qualified name.
    /// - Parameters:
    ///   - localName: The local element or attribute name.
    ///   - namespaceURI: The namespace URI. Whitespace-only values are normalized to `nil`.
    ///   - prefix: The namespace prefix. Whitespace-only values are normalized to `nil`.
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

    /// The prefix-qualified name (e.g. `"soap:body"`), or just `localName` if unprefixed.
    public var qualifiedName: String {
        if let prefix = prefix {
            return "\(prefix):\(localName)"
        }
        return localName
    }
}
