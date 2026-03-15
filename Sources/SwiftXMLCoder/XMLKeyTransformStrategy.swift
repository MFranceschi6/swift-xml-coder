/// Controls how Swift property names (coding keys) are transformed into XML element
/// and attribute names during encoding, and how XML names are matched to coding keys
/// during decoding.
///
/// The same transformation is applied in both directions (encode and decode), using a
/// *transform-then-match* semantic: the coding key's `stringValue` is transformed and
/// the result is used as the XML name (encoding) or as the lookup key in the tree
/// (decoding).  This means the encoder and decoder are automatically symmetric without
/// requiring an inverse function.
///
/// ```swift
/// // Encoding a SOAP-style struct:
/// let encoder = XMLEncoder(
///     configuration: .init(keyTransformStrategy: .capitalized)
/// )
/// // firstName → <FirstName>…</FirstName>
/// ```
///
/// ```swift
/// // Decoding snake_case XML:
/// let decoder = XMLDecoder(
///     configuration: .init(keyTransformStrategy: .convertToSnakeCase)
/// )
/// // property `firstName` matches XML element <first_name>…</first_name>
/// ```
public enum XMLKeyTransformStrategy: Sendable {
    /// Use the coding key's `stringValue` unchanged. This is the default.
    case useDefaultKeys
    /// Convert `camelCase` or `PascalCase` to `snake_case`.
    ///
    /// `firstName` → `first_name`, `XMLParser` → `x_m_l_parser`
    case convertToSnakeCase
    /// Convert `camelCase` or `PascalCase` to `kebab-case`.
    ///
    /// `firstName` → `first-name`
    case convertToKebabCase
    /// Capitalise the first letter of each word boundary.
    ///
    /// `firstName` → `FirstName`
    case capitalized
    /// Uppercase all characters.
    ///
    /// `firstName` → `FIRSTNAME`
    case uppercased
    /// Lowercase all characters.
    ///
    /// `FirstName` → `firstname`
    case lowercased
    /// Apply a custom transformation closure.
    ///
    /// The closure receives the coding key's `stringValue` and returns the XML name.
    case custom(@Sendable (String) -> String)

    /// Applies this strategy to `key` and returns the transformed XML name.
    func transform(_ key: String) -> String {
        switch self {
        case .useDefaultKeys:
            return key
        case .convertToSnakeCase:
            return _camelToSeparated(key, separator: "_")
        case .convertToKebabCase:
            return _camelToSeparated(key, separator: "-")
        case .capitalized:
            return _capitalize(key)
        case .uppercased:
            return key.uppercased()
        case .lowercased:
            return key.lowercased()
        case .custom(let closure):
            return closure(key)
        }
    }
}

// MARK: - Transformation helpers

/// Converts a camelCase or PascalCase string to a separator-delimited lowercase string.
/// "firstName" → "first_name", "XMLParser" → "x_m_l_parser"
private func _camelToSeparated(_ input: String, separator: String) -> String {
    guard !input.isEmpty else { return input }
    var result = ""
    result.reserveCapacity(input.count + 4)
    for (index, character) in input.enumerated() {
        if character.isUppercase && index > 0 {
            result.append(contentsOf: separator)
        }
        result.append(contentsOf: character.lowercased())
    }
    return result
}

/// Capitalises the first character of the string, leaving the rest unchanged.
/// "firstName" → "FirstName"
private func _capitalize(_ input: String) -> String {
    guard let first = input.first else { return input }
    return first.uppercased() + input.dropFirst()
}
