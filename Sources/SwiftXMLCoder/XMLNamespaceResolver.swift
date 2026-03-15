import Foundation

public enum XMLNamespaceResolutionError: Error, Equatable {
    case undefinedPrefix(prefix: String, localName: String)
    case prefixNamespaceMismatch(prefix: String, localName: String, expectedURI: String, providedURI: String)
    case missingDefaultNamespaceBinding(localName: String, requiredURI: String)
    case unprefixedAttributeWithNamespace(localName: String, namespaceURI: String)
    case conflictingDeclarations(prefix: String?, firstURI: String, secondURI: String)
}

public struct XMLNamespaceResolver: Sendable {
    private var scopes: [[String: String]]

    public init() {
        self.scopes = [[:]]
    }

    public mutating func push(declarations: [XMLNamespaceDeclaration]) throws {
        var scope: [String: String] = [:]

        for declaration in declarations {
            let normalizedPrefix = normalizedPrefix(declaration.prefix)

            if let existingURI = scope[normalizedPrefix], existingURI != declaration.uri {
                throw XMLNamespaceResolutionError.conflictingDeclarations(
                    prefix: declaration.prefix,
                    firstURI: existingURI,
                    secondURI: declaration.uri
                )
            }
            scope[normalizedPrefix] = declaration.uri
        }

        scopes.append(scope)
    }

    public mutating func pop() {
        if scopes.count > 1 {
            scopes.removeLast()
        }
    }

    public func namespaceURI(forPrefix prefix: String?) -> String? {
        let normalizedPrefix = normalizedPrefix(prefix)
        for scope in scopes.reversed() {
            if let uri = scope[normalizedPrefix] {
                return uri
            }
        }
        return nil
    }

    public func resolveElementName(_ name: XMLQualifiedName) throws -> XMLQualifiedName {
        if let prefix = name.prefix {
            guard let resolvedURI = namespaceURI(forPrefix: prefix) else {
                throw XMLNamespaceResolutionError.undefinedPrefix(prefix: prefix, localName: name.localName)
            }

            if let providedURI = name.namespaceURI, providedURI != resolvedURI {
                throw XMLNamespaceResolutionError.prefixNamespaceMismatch(
                    prefix: prefix,
                    localName: name.localName,
                    expectedURI: resolvedURI,
                    providedURI: providedURI
                )
            }

            return XMLQualifiedName(localName: name.localName, namespaceURI: resolvedURI, prefix: prefix)
        }

        let resolvedDefaultURI = namespaceURI(forPrefix: nil)
        if let requiredURI = name.namespaceURI {
            guard resolvedDefaultURI == requiredURI else {
                throw XMLNamespaceResolutionError.missingDefaultNamespaceBinding(
                    localName: name.localName,
                    requiredURI: requiredURI
                )
            }
        }

        return XMLQualifiedName(localName: name.localName, namespaceURI: resolvedDefaultURI, prefix: nil)
    }

    public func resolveAttributeName(_ name: XMLQualifiedName) throws -> XMLQualifiedName {
        if let prefix = name.prefix {
            guard let resolvedURI = namespaceURI(forPrefix: prefix) else {
                throw XMLNamespaceResolutionError.undefinedPrefix(prefix: prefix, localName: name.localName)
            }

            if let providedURI = name.namespaceURI, providedURI != resolvedURI {
                throw XMLNamespaceResolutionError.prefixNamespaceMismatch(
                    prefix: prefix,
                    localName: name.localName,
                    expectedURI: resolvedURI,
                    providedURI: providedURI
                )
            }

            return XMLQualifiedName(localName: name.localName, namespaceURI: resolvedURI, prefix: prefix)
        }

        if let namespaceURI = name.namespaceURI {
            throw XMLNamespaceResolutionError.unprefixedAttributeWithNamespace(
                localName: name.localName,
                namespaceURI: namespaceURI
            )
        }

        return XMLQualifiedName(localName: name.localName)
    }

    public func deterministicPrefix(forNamespaceURI namespaceURI: String, preferredPrefix: String? = nil) -> String? {
        if let preferredPrefix = preferredPrefix,
           self.namespaceURI(forPrefix: preferredPrefix) == namespaceURI {
            return preferredPrefix
        }

        var matchingPrefixes: Set<String> = []
        for scope in scopes {
            for (prefix, uri) in scope where uri == namespaceURI {
                matchingPrefixes.insert(prefix)
            }
        }

        if matchingPrefixes.contains(Self.defaultPrefixToken) {
            return nil
        }

        return matchingPrefixes.sorted().first
    }

    private func normalizedPrefix(_ prefix: String?) -> String {
        prefix ?? Self.defaultPrefixToken
    }

    private static let defaultPrefixToken = ""
}

public enum XMLNamespaceValidator {
    public enum Mode: Sendable, Hashable {
        case strict
        case synthesizeMissingDeclarations
    }

    public static func validate(document: XMLTreeDocument) throws {
        try validate(document: document, mode: .strict)
    }

    public static func validate(document: XMLTreeDocument, mode: Mode) throws {
        var resolver = XMLNamespaceResolver()
        try validate(element: document.root, mode: mode, resolver: &resolver)
    }

    private static func validate(
        element: XMLTreeElement,
        mode: Mode,
        resolver: inout XMLNamespaceResolver
    ) throws {
        try resolver.push(declarations: element.namespaceDeclarations)
        defer { resolver.pop() }

        switch mode {
        case .strict:
            _ = try resolver.resolveElementName(element.name)
        case .synthesizeMissingDeclarations:
            try validateElementNameForSynthesis(element.name, resolver: resolver)
        }

        for attribute in element.attributes {
            switch mode {
            case .strict:
                _ = try resolver.resolveAttributeName(attribute.name)
            case .synthesizeMissingDeclarations:
                try validateAttributeNameForSynthesis(attribute.name, resolver: resolver)
            }
        }

        for child in element.children {
            if case .element(let childElement) = child {
                try validate(element: childElement, mode: mode, resolver: &resolver)
            }
        }
    }

    private static func validateElementNameForSynthesis(
        _ name: XMLQualifiedName,
        resolver: XMLNamespaceResolver
    ) throws {
        if let prefix = name.prefix {
            if name.namespaceURI != nil {
                return
            }

            guard resolver.namespaceURI(forPrefix: prefix) != nil else {
                throw XMLNamespaceResolutionError.undefinedPrefix(prefix: prefix, localName: name.localName)
            }
            return
        }
    }

    private static func validateAttributeNameForSynthesis(
        _ name: XMLQualifiedName,
        resolver: XMLNamespaceResolver
    ) throws {
        if let prefix = name.prefix {
            if name.namespaceURI != nil {
                return
            }

            guard resolver.namespaceURI(forPrefix: prefix) != nil else {
                throw XMLNamespaceResolutionError.undefinedPrefix(prefix: prefix, localName: name.localName)
            }
            return
        }
    }
}
