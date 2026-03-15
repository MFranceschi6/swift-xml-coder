import Foundation

public struct XMLCanonicalizerOrderProbeResult: Sendable, Equatable {
    public let recordedTokens: [String]
    public let traceValue: String?

    public init(recordedTokens: [String], traceValue: String?) {
        self.recordedTokens = recordedTokens
        self.traceValue = traceValue
    }
}
