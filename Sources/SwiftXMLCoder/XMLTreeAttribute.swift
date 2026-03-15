import Foundation

/// An immutable XML attribute: a qualified name and a string value.
public struct XMLTreeAttribute: Sendable, Hashable, Codable {
    /// The qualified name of the attribute.
    public let name: XMLQualifiedName
    /// The string value of the attribute.
    public let value: String

    /// Creates an XML tree attribute.
    /// - Parameters:
    ///   - name: The qualified attribute name.
    ///   - value: The attribute value.
    public init(name: XMLQualifiedName, value: String) {
        self.name = name
        self.value = value
    }
}
