import Foundation

public struct XMLCanonicalizerFailureProbeResult: Sendable, Equatable {
    public let message: String?
    public let recordedTokens: [String]

    public init(message: String?, recordedTokens: [String]) {
        self.message = message
        self.recordedTokens = recordedTokens
    }
}
