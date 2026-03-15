import Foundation
import XMLCoderCompatibility

public enum XMLCanonicalizationError: Error {
    case transformFailed(
        code: XMLCanonicalizationErrorCode,
        transformIndex: Int,
        transformType: String,
        underlyingError: XMLAnyError?,
        message: String?
    )
    case serializationFailed(
        code: XMLCanonicalizationErrorCode,
        underlyingError: XMLAnyError?,
        message: String?
    )
    case other(
        code: XMLCanonicalizationErrorCode,
        underlyingError: XMLAnyError?,
        message: String?
    )
}
