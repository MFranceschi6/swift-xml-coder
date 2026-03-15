import Foundation

public protocol XMLRootNode {
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

    static func makeXMLSafeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        var result = value.unicodeScalars.map { scalar in
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
