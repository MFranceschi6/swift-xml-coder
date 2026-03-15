import Foundation
import XMLCoderCompatibility

/// Compatibility contract for canonicalization extension points.
///
/// External XML signature libraries can implement `XMLCanonicalizer` and reuse these helpers
/// to preserve deterministic transform ordering and stable error envelopes.
public enum XMLCanonicalizationContract: Sendable {}
