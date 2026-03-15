import Foundation
import XMLCoderCompatibility

/// Errors produced by the XML parsing, encoding, and decoding layer.
///
/// `XMLParsingError` is thrown by ``XMLEncoder``, ``XMLDecoder``, ``XMLTreeParser``,
/// ``XMLTreeWriter``, and related types whenever the XML layer encounters a structural
/// or content violation.
public enum XMLParsingError: Error {
    /// The input data contains bytes that are not valid UTF-8.
    case invalidUTF8

    /// The XML parser or Codable decoding layer failed to process the document.
    ///
    /// - Parameter message: A diagnostic message with a stable `[CODE]` prefix where applicable.
    case parseFailed(message: String?)

    /// An XPath expression evaluation failed.
    ///
    /// - Parameters:
    ///   - expression: The XPath expression that failed.
    ///   - message: A human-readable description of the failure, if available.
    case xpathFailed(expression: String, message: String?)

    /// The XML document could not be created (e.g. libxml2 returned a null document pointer).
    ///
    /// - Parameter message: A human-readable description of the failure, if available.
    case documentCreationFailed(message: String?)

    /// An XML node could not be created (e.g. invalid element name, null return from libxml2).
    ///
    /// - Parameters:
    ///   - name: The element or node name that could not be created.
    ///   - message: A human-readable description of the failure, if available.
    case nodeCreationFailed(name: String, message: String?)

    /// The namespace configuration is invalid (e.g. conflicting prefix/URI pair).
    ///
    /// - Parameters:
    ///   - prefix: The namespace prefix, if available.
    ///   - uri: The namespace URI, if available.
    case invalidNamespaceConfiguration(prefix: String?, uri: String?)

    /// A node manipulation operation (append, remove, move) failed.
    ///
    /// - Parameter message: A human-readable description of the failure, if available.
    case nodeOperationFailed(message: String?)

    /// A catch-all case for unexpected errors not covered by more specific cases.
    ///
    /// - Parameters:
    ///   - underlyingError: The original error in a type-erased container, if available.
    ///   - message: A human-readable description of the situation, if available.
    ///
    /// - Note: Two `.other` values are never considered equal regardless of their payloads,
    ///   because `XMLAnyError` is an existential and cannot be compared structurally.
    case other(underlyingError: XMLAnyError?, message: String?)
}

extension XMLParsingError: Equatable {
    public static func == (lhs: XMLParsingError, rhs: XMLParsingError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidUTF8, .invalidUTF8):
            return true
        case (.parseFailed(let lhsMsg), .parseFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.xpathFailed(let lhsExpr, let lhsMsg), .xpathFailed(let rhsExpr, let rhsMsg)):
            return lhsExpr == rhsExpr && lhsMsg == rhsMsg
        case (.documentCreationFailed(let lhsMsg), .documentCreationFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.nodeCreationFailed(let lhsName, let lhsMsg), .nodeCreationFailed(let rhsName, let rhsMsg)):
            return lhsName == rhsName && lhsMsg == rhsMsg
        case (.invalidNamespaceConfiguration(let lhsPrefix, let lhsURI), .invalidNamespaceConfiguration(let rhsPrefix, let rhsURI)):
            return lhsPrefix == rhsPrefix && lhsURI == rhsURI
        case (.nodeOperationFailed(let lhsMsg), .nodeOperationFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.other, .other):
            return false
        default:
            return false
        }
    }
}
