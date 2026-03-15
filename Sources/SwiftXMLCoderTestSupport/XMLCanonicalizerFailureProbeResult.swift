import Foundation
import SwiftXMLCoder

public struct XMLCanonicalizerFailureProbeResult: Sendable, Equatable {
    public let stage: XMLCanonicalizationStage
    public let code: XMLCanonicalizationErrorCode
    public let recordedTokens: [String]

    public init(stage: XMLCanonicalizationStage, code: XMLCanonicalizationErrorCode, recordedTokens: [String]) {
        self.stage = stage
        self.code = code
        self.recordedTokens = recordedTokens
    }
}
