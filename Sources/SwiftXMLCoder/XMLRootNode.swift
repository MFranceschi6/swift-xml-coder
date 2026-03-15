import Foundation

/// A type that declares a fixed XML root element name and optional namespace URI.
///
/// Conform your `Codable` type to `XMLRootNode` to override the default root element
/// name (which falls back to the type name) and to attach a namespace URI to the root:
///
/// ```swift
/// struct Envelope: Codable, XMLRootNode {
///     static let xmlRootElementName = "Envelope"
///     static let xmlRootElementNamespaceURI: String? = "http://schemas.xmlsoap.org/soap/envelope/"
/// }
/// ```
///
/// Both ``XMLEncoder`` and ``XMLDecoder`` check for this conformance before falling
/// back to the configuration-level `rootElementName`.
public protocol XMLRootNode {
    /// The XML element name to use as the document root when encoding this type.
    static var xmlRootElementName: String { get }
    /// The XML namespace URI for the root element, or `nil` for no namespace.
    static var xmlRootElementNamespaceURI: String? { get }
}

public extension XMLRootNode {
    static var xmlRootElementNamespaceURI: String? { nil }
}

enum XMLRootNameResolver {
    static func explicitRootElementName(from configuredName: String?) -> String? {
        guard let configuredName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines),
              configuredName.isEmpty == false else {
            return nil
        }
        return makeXMLSafeName(configuredName)
    }

    static func implicitRootElementName<T>(for type: T.Type) throws -> String? {
        guard let rootNodeType = type as? XMLRootNode.Type else {
            return nil
        }

        let configuredName = rootNodeType.xmlRootElementName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuredName.isEmpty == false else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_7_ROOT_NAME_EMPTY] Type '\(String(describing: type))' provides an empty xmlRootElementName."
            )
        }
        return makeXMLSafeName(configuredName)
    }

    static func implicitRootElementNamespaceURI<T>(for type: T.Type) -> String? {
        (type as? XMLRootNode.Type)?.xmlRootElementNamespaceURI
    }

    static func fallbackRootElementName<T>(for type: T.Type) -> String {
        let typeName = String(describing: type)
        let shortName = typeName.split(separator: ".").last.map(String.init) ?? "Root"
        return makeXMLSafeName(shortName)
    }

    /// Sanitises `value` into a valid XML NCName (no-colon name).
    ///
    /// If the value contains a `:`, the namespace prefix is stripped and only the local
    /// part is retained (e.g. `"soap:Envelope"` → `"Envelope"`). Any remaining
    /// non-alphanumeric characters other than `_` and `-` are replaced with `_`.
    /// A leading digit is prefixed with `_`. An empty result falls back to `"Root"`.
    static func makeXMLSafeName(_ value: String) -> String {
        // Strip namespace prefix — take only the local part after the last colon.
        let localPart = value.contains(":") ? String(value.split(separator: ":", maxSplits: 1).last ?? Substring(value)) : value

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        var result = localPart.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }

        if result.isEmpty {
            result = Array("Root")
        }

        if let first = result.first, first.isNumber {
            result.insert("_", at: result.startIndex)
        }

        return String(result)
    }
}
