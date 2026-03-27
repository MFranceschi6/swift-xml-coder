import Foundation
import SwiftXMLCoder

public struct XMLTestFailingTransform: XMLTransform {
    public let token: String
    public let recorder: XMLTestCallRecorder?
    public let error: Error

    public init(token: String, recorder: XMLTestCallRecorder? = nil, error: Error) {
        self.token = token
        self.recorder = recorder
        self.error = error
    }

    public func apply(
        to _: XMLTreeDocument,
        options _: XMLCanonicalizationOptions
    ) throws -> XMLTreeDocument {
        recorder?.record(token)
        throw error
    }
}
