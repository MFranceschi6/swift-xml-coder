import Foundation
import SwiftXMLCoder

public final class XMLTestEncoderSpy {
    public enum Method: String, Equatable {
        case encodeData
        case encodeTree
    }

    public struct Call: Equatable {
        public let method: Method
        public let valueTypeName: String

        public init(method: Method, valueTypeName: String) {
            self.method = method
            self.valueTypeName = valueTypeName
        }
    }

    private let encoder: XMLEncoder

    public private(set) var calls: [Call] = []
    public var forcedError: Error?
    public var stubbedTreeDocument: XMLTreeDocument?
    public var stubbedData: Data?

    public init(encoder: XMLEncoder = XMLEncoder()) {
        self.encoder = encoder
    }

    public func encodeTree<T: Encodable>(_ value: T) throws -> XMLTreeDocument {
        recordCall(method: .encodeTree, valueType: T.self)

        if let forcedError = forcedError {
            throw forcedError
        }
        if let stubbedTreeDocument = stubbedTreeDocument {
            return stubbedTreeDocument
        }

        return try encoder.encodeTree(value)
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        recordCall(method: .encodeData, valueType: T.self)

        if let forcedError = forcedError {
            throw forcedError
        }
        if let stubbedData = stubbedData {
            return stubbedData
        }

        return try encoder.encode(value)
    }

    private func recordCall<T>(method: Method, valueType: T.Type) {
        calls.append(
            Call(
                method: method,
                valueTypeName: String(reflecting: valueType)
            )
        )
    }
}
