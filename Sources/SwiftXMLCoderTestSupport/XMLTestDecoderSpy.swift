import Foundation
import SwiftXMLCoder

public final class XMLTestDecoderSpy {
    public enum Method: String, Equatable {
        case decodeData
        case decodeTree
    }

    public struct Call: Equatable {
        public let method: Method
        public let valueTypeName: String
        public let payloadSize: Int

        public init(method: Method, valueTypeName: String, payloadSize: Int) {
            self.method = method
            self.valueTypeName = valueTypeName
            self.payloadSize = payloadSize
        }
    }

    private let decoder: XMLDecoder

    public private(set) var calls: [Call] = []
    public var forcedError: Error?
    public var decodeTreeStub: ((Any.Type, XMLTreeDocument) throws -> Any)?
    public var decodeDataStub: ((Any.Type, Data) throws -> Any)?

    public init(decoder: XMLDecoder = XMLDecoder()) {
        self.decoder = decoder
    }

    public func decodeTree<T: Decodable>(_ type: T.Type, from tree: XMLTreeDocument) throws -> T {
        recordCall(method: .decodeTree, valueType: type, payloadSize: tree.root.children.count)

        if let forcedError = forcedError {
            throw forcedError
        }
        if let decodeTreeStub = decodeTreeStub {
            return try resolveStubbedValue(
                expectedType: type,
                stubbedValue: decodeTreeStub(type, tree)
            )
        }

        return try decoder.decodeTree(type, from: tree)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        recordCall(method: .decodeData, valueType: type, payloadSize: data.count)

        if let forcedError = forcedError {
            throw forcedError
        }
        if let decodeDataStub = decodeDataStub {
            return try resolveStubbedValue(
                expectedType: type,
                stubbedValue: decodeDataStub(type, data)
            )
        }

        return try decoder.decode(type, from: data)
    }

    private func recordCall<T>(method: Method, valueType: T.Type, payloadSize: Int) {
        calls.append(
            Call(
                method: method,
                valueTypeName: String(reflecting: valueType),
                payloadSize: payloadSize
            )
        )
    }

    private func resolveStubbedValue<T>(expectedType: T.Type, stubbedValue: Any) throws -> T {
        guard let typedValue = stubbedValue as? T else {
            throw XMLTestCodecError.invalidStubbedValue(
                expectedType: String(reflecting: expectedType),
                actualType: String(reflecting: type(of: stubbedValue))
            )
        }
        return typedValue
    }
}
