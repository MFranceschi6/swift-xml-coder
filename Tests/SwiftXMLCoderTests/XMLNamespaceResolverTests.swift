import SwiftXMLCoder
import XCTest

final class XMLNamespaceResolverTests: XCTestCase {
    func test_resolveElementName_withDefaultNamespace_resolvesNamespaceURI() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [XMLNamespaceDeclaration(uri: "urn:default")])

        let resolved = try resolver.resolveElementName(
            XMLQualifiedName(localName: "Root")
        )

        XCTAssertEqual(resolved.localName, "Root")
        XCTAssertEqual(resolved.namespaceURI, "urn:default")
        XCTAssertNil(resolved.prefix)
    }

    func test_resolveElementName_withExplicitPrefix_resolvesNamespaceURI() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [XMLNamespaceDeclaration(prefix: "m", uri: "urn:messages")])

        let resolved = try resolver.resolveElementName(
            XMLQualifiedName(localName: "Echo", prefix: "m")
        )

        XCTAssertEqual(resolved.localName, "Echo")
        XCTAssertEqual(resolved.namespaceURI, "urn:messages")
        XCTAssertEqual(resolved.prefix, "m")
    }

    func test_resolveElementName_withUndefinedPrefix_throws() throws {
        let resolver = XMLNamespaceResolver()

        XCTAssertThrowsError(
            try resolver.resolveElementName(XMLQualifiedName(localName: "Echo", prefix: "m"))
        ) { error in
            guard case XMLNamespaceResolutionError.undefinedPrefix(prefix: "m", localName: "Echo") = error else {
                return XCTFail("Expected undefinedPrefix error, got: \(error)")
            }
        }
    }

    func test_resolveElementName_withRequiredDefaultNamespaceButNoBinding_throws() throws {
        let resolver = XMLNamespaceResolver()

        XCTAssertThrowsError(
            try resolver.resolveElementName(XMLQualifiedName(localName: "Root", namespaceURI: "urn:default"))
        ) { error in
            guard case XMLNamespaceResolutionError.missingDefaultNamespaceBinding(
                localName: "Root",
                requiredURI: "urn:default"
            ) = error else {
                return XCTFail("Expected missingDefaultNamespaceBinding error, got: \(error)")
            }
        }
    }

    func test_resolveEquivalentPrefixVariants_mapsToSameNamespaceURI() throws {
        var resolverA = XMLNamespaceResolver()
        try resolverA.push(declarations: [XMLNamespaceDeclaration(prefix: "a", uri: "urn:messages")])

        var resolverB = XMLNamespaceResolver()
        try resolverB.push(declarations: [XMLNamespaceDeclaration(prefix: "b", uri: "urn:messages")])

        let resolvedA = try resolverA.resolveElementName(XMLQualifiedName(localName: "Echo", prefix: "a"))
        let resolvedB = try resolverB.resolveElementName(XMLQualifiedName(localName: "Echo", prefix: "b"))

        XCTAssertEqual(resolvedA.localName, resolvedB.localName)
        XCTAssertEqual(resolvedA.namespaceURI, resolvedB.namespaceURI)
    }

    func test_deterministicPrefix_prefersLexicographicallySmallestPrefix() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [
            XMLNamespaceDeclaration(prefix: "z", uri: "urn:messages"),
            XMLNamespaceDeclaration(prefix: "a", uri: "urn:messages")
        ])

        let prefix = resolver.deterministicPrefix(forNamespaceURI: "urn:messages")

        XCTAssertEqual(prefix, "a")
    }

    func test_writer_namespaceValidation_missingDeclaration_throwsDeterministicError() {
        let writer = XMLTreeWriter()
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Envelope", namespaceURI: "urn:messages", prefix: "m")
            )
        )

        XCTAssertThrowsError(try writer.writeDocument(tree)) { error in
            guard case XMLParsingError.parseFailed(let message) = error else {
                return XCTFail("Expected parseFailed, got: \(error)")
            }
            XCTAssertTrue(message?.contains("[XML6_3_NAMESPACE_VALIDATION]") == true)
        }
    }

    func test_writer_strictPolicy_missingDefaultNamespaceDeclaration_throwsDeterministicError() {
        let writer = XMLTreeWriter(
            configuration: .init(namespaceValidationMode: .strict)
        )
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Envelope", namespaceURI: "urn:messages")
            )
        )

        XCTAssertThrowsError(try writer.writeDocument(tree)) { error in
            guard case XMLParsingError.parseFailed(let message) = error else {
                return XCTFail("Expected parseFailed, got: \(error)")
            }
            XCTAssertTrue(message?.contains("[XML6_3_NAMESPACE_VALIDATION]") == true)
        }
    }

    func test_writer_synthesizePolicy_allowsMissingDefaultNamespaceDeclaration() throws {
        let writer = XMLTreeWriter(
            configuration: .init(namespaceValidationMode: .synthesizeMissingDeclarations)
        )
        let parser = XMLTreeParser()
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Envelope", namespaceURI: "urn:messages")
            )
        )

        let data = try writer.writeData(tree)
        let roundtripped = try parser.parse(data: data)

        XCTAssertEqual(roundtripped.root.name.localName, "Envelope")
        XCTAssertEqual(roundtripped.root.name.namespaceURI, "urn:messages")
        XCTAssertNil(roundtripped.root.name.prefix)
    }

    // MARK: - Additional resolver coverage

    func test_resolver_push_conflictingDeclarations_throws() throws {
        var resolver = XMLNamespaceResolver()
        XCTAssertThrowsError(
            try resolver.push(declarations: [
                XMLNamespaceDeclaration(prefix: "ns", uri: "urn:first"),
                XMLNamespaceDeclaration(prefix: "ns", uri: "urn:second")
            ])
        ) { error in
            guard case XMLNamespaceResolutionError.conflictingDeclarations(let prefix, _, _) = error else {
                return XCTFail("Expected conflictingDeclarations, got \(error)")
            }
            XCTAssertEqual(prefix, "ns")
        }
    }

    func test_resolver_resolveElementName_prefixNamespaceMismatch_throws() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [XMLNamespaceDeclaration(prefix: "m", uri: "urn:messages")])

        let name = XMLQualifiedName(localName: "Echo", namespaceURI: "urn:other", prefix: "m")
        XCTAssertThrowsError(try resolver.resolveElementName(name)) { error in
            guard case XMLNamespaceResolutionError.prefixNamespaceMismatch(let prefix, _, _, _) = error else {
                return XCTFail("Expected prefixNamespaceMismatch, got \(error)")
            }
            XCTAssertEqual(prefix, "m")
        }
    }

    func test_resolver_resolveElementName_missingDefaultNamespace_throws() throws {
        var resolver = XMLNamespaceResolver()
        // No default namespace pushed; element requires one
        let name = XMLQualifiedName(localName: "Root", namespaceURI: "urn:required")
        XCTAssertThrowsError(try resolver.resolveElementName(name)) { error in
            guard case XMLNamespaceResolutionError.missingDefaultNamespaceBinding(let localName, let required) = error else {
                return XCTFail("Expected missingDefaultNamespaceBinding, got \(error)")
            }
            XCTAssertEqual(localName, "Root")
            XCTAssertEqual(required, "urn:required")
        }
    }

    func test_resolver_resolveAttributeName_undefinedPrefix_throws() throws {
        var resolver = XMLNamespaceResolver()
        // No prefix "a" declared
        let name = XMLQualifiedName(localName: "id", prefix: "a")
        XCTAssertThrowsError(try resolver.resolveAttributeName(name)) { error in
            guard case XMLNamespaceResolutionError.undefinedPrefix(let prefix, _) = error else {
                return XCTFail("Expected undefinedPrefix, got \(error)")
            }
            XCTAssertEqual(prefix, "a")
        }
    }

    func test_resolver_resolveAttributeName_prefixNamespaceMismatch_throws() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [XMLNamespaceDeclaration(prefix: "a", uri: "urn:attrs")])

        let name = XMLQualifiedName(localName: "id", namespaceURI: "urn:different", prefix: "a")
        XCTAssertThrowsError(try resolver.resolveAttributeName(name)) { error in
            guard case XMLNamespaceResolutionError.prefixNamespaceMismatch(let prefix, _, _, _) = error else {
                return XCTFail("Expected prefixNamespaceMismatch, got \(error)")
            }
            XCTAssertEqual(prefix, "a")
        }
    }

    func test_resolver_resolveAttributeName_unprefixedWithNamespace_throws() throws {
        var resolver = XMLNamespaceResolver()
        // Attribute has no prefix but has a namespaceURI (invalid for attributes)
        let name = XMLQualifiedName(localName: "id", namespaceURI: "urn:attrs")
        XCTAssertThrowsError(try resolver.resolveAttributeName(name)) { error in
            guard case XMLNamespaceResolutionError.unprefixedAttributeWithNamespace(
                let localName, let namespaceURI
            ) = error else {
                return XCTFail("Expected unprefixedAttributeWithNamespace, got \(error)")
            }
            XCTAssertEqual(localName, "id")
            XCTAssertEqual(namespaceURI, "urn:attrs")
        }
    }

    func test_resolver_deterministicPrefix_preferredPrefixMatches_returnsPreferred() throws {
        var resolver = XMLNamespaceResolver()
        try resolver.push(declarations: [XMLNamespaceDeclaration(prefix: "soap", uri: "urn:soap")])

        let prefix = resolver.deterministicPrefix(forNamespaceURI: "urn:soap", preferredPrefix: "soap")
        XCTAssertEqual(prefix, "soap")
    }

    func test_resolver_deterministicPrefix_defaultNamespaceMapping_returnsNil() throws {
        var resolver = XMLNamespaceResolver()
        // Push a default namespace (nil prefix) mapping to the URI
        try resolver.push(declarations: [XMLNamespaceDeclaration(uri: "urn:default")])

        let prefix = resolver.deterministicPrefix(forNamespaceURI: "urn:default")
        XCTAssertNil(prefix)
    }

    func test_namespaceValidator_validate_strictMode_noArgs() throws {
        // Exercises the validate(document:) single-argument overload
        let tree = XMLTreeDocument(root: XMLTreeElement(name: XMLQualifiedName(localName: "Root")))
        XCTAssertNoThrow(try XMLNamespaceValidator.validate(document: tree))
    }

    func test_namespaceValidator_synthesize_elementWithPrefixAndNamespaceURI_succeeds() throws {
        // Element with both prefix and namespaceURI → validateElementNameForSynthesis returns early
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root", namespaceURI: "urn:foo", prefix: "foo")
            )
        )
        XCTAssertNoThrow(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations))
    }

    func test_namespaceValidator_synthesize_elementWithPrefixNoURIUndefined_throws() {
        // Element with prefix but no namespaceURI and no declaration → throws undefinedPrefix
        let tree = XMLTreeDocument(
            root: XMLTreeElement(name: XMLQualifiedName(localName: "Root", prefix: "foo"))
        )
        XCTAssertThrowsError(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations)) { error in
            guard case XMLNamespaceResolutionError.undefinedPrefix = error else {
                return XCTFail("Expected undefinedPrefix, got \(error)")
            }
        }
    }

    func test_namespaceValidator_synthesize_elementWithPrefixNoURIDefined_succeeds() throws {
        // Element with prefix, no namespaceURI, but prefix IS declared → succeeds
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root", prefix: "foo"),
                namespaceDeclarations: [XMLNamespaceDeclaration(prefix: "foo", uri: "urn:foo")]
            )
        )
        XCTAssertNoThrow(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations))
    }

    func test_namespaceValidator_synthesize_attributeWithPrefixAndNamespaceURI_succeeds() throws {
        // Attribute with prefix AND namespaceURI → validateAttributeNameForSynthesis returns early
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(
                        name: XMLQualifiedName(localName: "id", namespaceURI: "urn:attrs", prefix: "a"),
                        value: "123"
                    )
                ]
            )
        )
        XCTAssertNoThrow(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations))
    }

    func test_namespaceValidator_synthesize_attributeWithPrefixUndefined_throws() {
        // Attribute with prefix but no namespaceURI, prefix not declared → throws undefinedPrefix
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(
                        name: XMLQualifiedName(localName: "id", prefix: "a"),
                        value: "123"
                    )
                ]
            )
        )
        XCTAssertThrowsError(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations)) { error in
            guard case XMLNamespaceResolutionError.undefinedPrefix = error else {
                return XCTFail("Expected undefinedPrefix, got \(error)")
            }
        }
    }

    func test_namespaceValidator_synthesize_attributeWithPrefixDefined_succeeds() throws {
        // Attribute with prefix, no namespaceURI, prefix IS declared → succeeds
        let tree = XMLTreeDocument(
            root: XMLTreeElement(
                name: XMLQualifiedName(localName: "Root"),
                attributes: [
                    XMLTreeAttribute(
                        name: XMLQualifiedName(localName: "id", prefix: "a"),
                        value: "123"
                    )
                ],
                namespaceDeclarations: [XMLNamespaceDeclaration(prefix: "a", uri: "urn:attrs")]
            )
        )
        XCTAssertNoThrow(try XMLNamespaceValidator.validate(document: tree, mode: .synthesizeMissingDeclarations))
    }
}
