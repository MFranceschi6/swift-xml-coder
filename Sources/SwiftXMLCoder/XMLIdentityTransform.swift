import Foundation

public struct XMLIdentityTransform: XMLTransform {
    public init() {}

    public func apply(
        to document: XMLTreeDocument,
        options: XMLNormalizationOptions
    ) throws -> XMLTreeDocument {
        document
    }
}
