/// Controls which XML structural validations are performed at runtime.
///
/// Validation checks that element names, attribute names, and XSD temporal values
/// conform to their respective XML specifications. Disabling validation can improve
/// performance in hot paths where inputs are known to be well-formed.
///
/// ## Build-time configuration
///
/// The default policy is ``lenient`` unless the `SWIFT_XML_CODER_STRICT_VALIDATION`
/// Swift define flag is set at compile time, in which case it is ``strict``.
///
/// To activate strict validation at build time, add the flag in your `Package.swift`:
///
/// ```swift
/// .target(
///     name: "MyTarget",
///     swiftSettings: [
///         .define("SWIFT_XML_CODER_STRICT_VALIDATION")
///     ]
/// )
/// ```
///
/// ## Runtime override
///
/// Pass an explicit policy to ``XMLEncoder/Configuration`` or
/// ``XMLDecoder/Configuration`` to override the build-time default for a
/// specific encoder or decoder instance:
///
/// ```swift
/// let encoder = XMLEncoder(configuration: .init(validationPolicy: .strict))
/// ```
public struct XMLValidationPolicy: Sendable, Equatable, Hashable {
    /// When `true`, element and attribute names derived from configuration
    /// (e.g. `rootElementName`, `itemElementName`) are validated as legal
    /// XML NCNames before the document is written.
    public var validateElementNames: Bool

    /// When `true`, XSD temporal lexical values are validated strictly on
    /// parse. Invalid values throw ``XMLParsingError/parseFailed(message:)``
    /// instead of being silently ignored or partially parsed.
    public var validateXSDTemporalValues: Bool

    /// Creates a policy with explicit settings.
    ///
    /// - Parameters:
    ///   - validateElementNames: Validate element/attribute names. Defaults to `false`.
    ///   - validateXSDTemporalValues: Validate XSD temporal lexical values strictly. Defaults to `false`.
    public init(
        validateElementNames: Bool = false,
        validateXSDTemporalValues: Bool = false
    ) {
        self.validateElementNames = validateElementNames
        self.validateXSDTemporalValues = validateXSDTemporalValues
    }

    /// All validations enabled. Recommended for development and CI environments.
    public static let strict = XMLValidationPolicy(
        validateElementNames: true,
        validateXSDTemporalValues: true
    )

    /// All validations disabled. Suitable for production hot paths where inputs
    /// are known to be correct.
    public static let lenient = XMLValidationPolicy(
        validateElementNames: false,
        validateXSDTemporalValues: false
    )

    /// The default policy for the current build.
    ///
    /// Returns ``strict`` when the `SWIFT_XML_CODER_STRICT_VALIDATION` compile-time
    /// flag is defined; otherwise returns ``lenient``.
    public static var `default`: XMLValidationPolicy {
        #if SWIFT_XML_CODER_STRICT_VALIDATION
        return .strict
        #else
        return .lenient
        #endif
    }
}
