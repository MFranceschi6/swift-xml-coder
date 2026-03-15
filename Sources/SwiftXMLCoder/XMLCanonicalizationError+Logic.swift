import Foundation

extension XMLCanonicalizationError {
    public var stage: XMLCanonicalizationStage {
        switch self {
        case .transformFailed:
            return .transform
        case .serializationFailed:
            return .serialization
        case .other:
            return .other
        }
    }

    /// The stable error code identifying the failure category.
    public var code: XMLCanonicalizationErrorCode {
        switch self {
        case .transformFailed(let code, _, _, _, _):
            return code
        case .serializationFailed(let code, _, _):
            return code
        case .other(let code, _, _):
            return code
        }
    }
}
