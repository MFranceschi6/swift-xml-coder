import Foundation

/// Errors produced by ``XMLNamespaceResolver`` when resolving or validating namespace prefixes.
public enum XMLNamespaceResolutionError: Error, Equatable {
    /// A namespace prefix is used but has no active binding in the current scope.
    case undefinedPrefix(prefix: String, localName: String)
    /// A prefix is bound to a different URI than the one declared on the qualified name.
    case prefixNamespaceMismatch(prefix: String, localName: String, expectedURI: String, providedURI: String)
    /// An element requires a default namespace that is not currently bound.
    case missingDefaultNamespaceBinding(localName: String, requiredURI: String)
    /// An attribute is unprefixed but carries a namespace URI, which is illegal in XML Namespaces 1.0.
    case unprefixedAttributeWithNamespace(localName: String, namespaceURI: String)
    /// Two declarations in the same scope bind the same prefix to different URIs.
    case conflictingDeclarations(prefix: String?, firstURI: String, secondURI: String)
}

/// A scoped, stack-based resolver for XML namespace prefix-to-URI mappings.
///
/// Push a new scope when entering an element and pop it when leaving. The resolver
/// searches scopes from innermost to outermost, implementing the XML Namespaces 1.0
/// scoping rules:
///
/// ```swift
/// var resolver = XMLNamespaceResolver()
/// try resolver.push(declarations: [.init(prefix: "ex", namespaceURI: "http://example.com/")])
/// let uri = resolver.namespaceURI(forPrefix: "ex") // "http://example.com/"
/// resolver.pop()
/// ```
public struct XMLNamespaceResolver: Sendable {
    private var scopes: [[String: String]]

    /// Creates an empty namespace resolver with a single root scope.
    public init() {
        self.scopes = [[:]]
    }

    /// Pushes a new namespace scope with the given declarations.
    ///
    /// - Parameter declarations: The namespace declarations to register in the new scope.
    /// - Throws: ``XMLNamespaceResolutionError/conflictingDeclarations(_:_:_:)`` if any two
    ///   declarations in `declarations` bind the same prefix to different URIs.
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

    /// Pops the current namespace scope. The root scope is never removed.
    public mutating func pop() {
        if scopes.count > 1 {
            scopes.removeLast()
        }
    }

    /// Returns the namespace URI bound to `prefix` in the innermost scope, or `nil` if not bound.
    /// Pass `nil` for `prefix` to look up the default namespace.
    public func namespaceURI(forPrefix prefix: String?) -> String? {
        let normalizedPrefix = normalizedPrefix(prefix)
        for scope in scopes.reversed() {
            if let uri = scope[normalizedPrefix] {
                return uri
            }
        }
        return nil
    }

    /// Resolves an element's qualified name, filling in the namespace URI from the current scope.
    ///
    /// - Throws: ``XMLNamespaceResolutionError`` if the prefix is undefined or the URI mismatches.
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

    /// Resolves an attribute's qualified name, filling in the namespace URI from the current scope.
    ///
    /// Unlike elements, unprefixed attributes do **not** inherit the default namespace.
    /// - Throws: ``XMLNamespaceResolutionError`` if the prefix is undefined, the URI mismatches,
    ///   or an unprefixed attribute carries a namespace URI.
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

    /// Returns a deterministic prefix for `namespaceURI`, preferring `preferredPrefix` when it is
    /// already bound to that URI. Returns `nil` if the URI is bound to the default namespace.
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

/// Validates XML tree namespace declarations for consistency and completeness.
public enum XMLNamespaceValidator {
    /// Strategy used when a namespace declaration is missing.
    public enum Mode: Sendable, Hashable {
        /// Throw ``XMLNamespaceResolutionError/undefinedPrefix(_:_:)`` on any undeclared prefix.
        case strict
        /// Attempt to synthesise missing namespace declarations automatically.
        case synthesizeMissingDeclarations
    }

    /// Validates the document using ``Mode/strict`` mode.
    ///
    /// - Throws: ``XMLNamespaceResolutionError`` if any prefix is undeclared.
    public static func validate(document: XMLTreeDocument) throws {
        try validate(document: document, mode: .strict)
    }

    /// Validates the document using the specified `mode`.
    ///
    /// - Throws: ``XMLNamespaceResolutionError`` if validation fails.
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
