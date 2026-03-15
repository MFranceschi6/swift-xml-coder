import Foundation

public struct XMLTreeAttribute: Sendable, Hashable, Codable {
    public let name: XMLQualifiedName
    public let value: String

    public init(name: XMLQualifiedName, value: String) {
        self.name = name
        self.value = value
    }
}
