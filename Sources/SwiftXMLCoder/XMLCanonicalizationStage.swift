import Foundation

/// The canonicalization pipeline stage at which an error occurred.
public enum XMLCanonicalizationStage: String, Sendable, Hashable {
    /// Error occurred during a pre-canonicalization transform.
    case transform
    /// Error occurred during serialization to canonical XML bytes.
    case serialization
    /// Error occurred at an unspecified or unexpected stage.
    case other
}
