import Foundation

/// Stable diagnostic code used by canonicalization errors.
///
/// Integrators can introduce custom codes via `init(rawValue:)` while still supporting
/// default runtime codes exposed by this module.
public struct XMLCanonicalizationErrorCode: RawRepresentable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The transform pipeline produced an error during application.
    public static let transformFailed: XMLCanonicalizationErrorCode = .init(
        rawValue: "XML6_9_CANONICAL_TRANSFORM_FAILED"
    )
    /// The XML serialisation step failed (e.g. encoding error, writer failure).
    public static let serializationFailed: XMLCanonicalizationErrorCode = .init(
        rawValue: "XML6_9_CANONICAL_SERIALIZATION_FAILED"
    )
    /// An unexpected internal error occurred during canonicalization.
    public static let unexpected: XMLCanonicalizationErrorCode = .init(
        rawValue: "XML6_9_CANONICAL_UNEXPECTED"
    )
}
