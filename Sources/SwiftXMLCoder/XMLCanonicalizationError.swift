import Foundation
import XMLCoderCompatibility

/// Errors produced during XML canonicalization.
///
/// Every case carries a stable ``XMLCanonicalizationErrorCode`` for programmatic
/// handling and an optional human-readable `message` for diagnostics.
public enum XMLCanonicalizationError: Error {
    /// A pre-canonicalization ``XMLTransform`` failed.
    ///
    /// - Parameters:
    ///   - code: The stable error code.
    ///   - transformIndex: Zero-based index of the failing transform in the pipeline.
    ///   - transformType: The Swift type name of the failing transform.
    ///   - underlyingError: The original error thrown by the transform, if any.
    ///   - message: A human-readable description, if available.
    case transformFailed(
        code: XMLCanonicalizationErrorCode,
        transformIndex: Int,
        transformType: String,
        underlyingError: XMLAnyError?,
        message: String?
    )
    /// Serialization of the canonical form failed.
    ///
    /// - Parameters:
    ///   - code: The stable error code.
    ///   - underlyingError: The original error, if any.
    ///   - message: A human-readable description, if available.
    case serializationFailed(
        code: XMLCanonicalizationErrorCode,
        underlyingError: XMLAnyError?,
        message: String?
    )
    /// A catch-all for unexpected canonicalization failures.
    ///
    /// - Parameters:
    ///   - code: The stable error code.
    ///   - underlyingError: The original error, if any.
    ///   - message: A human-readable description, if available.
    case other(
        code: XMLCanonicalizationErrorCode,
        underlyingError: XMLAnyError?,
        message: String?
    )
}
