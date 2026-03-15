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

    public var code: String {
        switch self {
        case .transformFailed(let code, _, _, _, _):
            return code.rawValue
        case .serializationFailed(let code, _, _):
            return code.rawValue
        case .other(let code, _, _):
            return code.rawValue
        }
    }
}
