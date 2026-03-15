import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostic IDs

private enum XMLCodableDiagnostic {
    static let invalidDecl = DiagnosticMessage(
        id: "XML8A_INVALID_DECL",
        message: "@XMLCodable can only be attached to a struct or class declaration.",
        severity: .error
    )

    struct DiagnosticMessage: SwiftDiagnostics.DiagnosticMessage {
        let diagnosticID: MessageID
        let message: String
        let severity: DiagnosticSeverity

        init(id: String, message: String, severity: DiagnosticSeverity) {
            self.diagnosticID = MessageID(domain: "SwiftXMLCoderMacroImplementation", id: id)
            self.message = message
            self.severity = severity
        }
    }
}

// MARK: - XMLCodableMacro

/// Implementation of `@XMLCodable`.
///
/// Scans the stored properties of the attached struct or class for `@XMLAttribute` and
/// `@XMLElement` annotations, then synthesises an `XMLFieldCodingOverrideProvider`
/// extension whose `xmlFieldNodeKinds` dictionary maps each annotated field name to its
/// corresponding `XMLFieldNodeKind`.
public struct XMLCodableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {

        // Only struct / class allowed.
        guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: XMLCodableDiagnostic.invalidDecl
                )
            )
            return []
        }

        // Scan member stored properties for @XMLAttribute / @XMLElement annotations.
        var entries: [(name: String, kind: String)] = []
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Skip computed properties.
            guard varDecl.bindings.allSatisfy({ $0.accessorBlock == nil }) else { continue }

            let annotationKind = varDecl.attributes.xmlFieldAnnotationKind
            guard let kind = annotationKind else { continue }

            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                entries.append((name: identifier.identifier.text, kind: kind))
            }
        }

        // Build the dictionary body.
        let dictBody: String
        if entries.isEmpty {
            dictBody = "[:]"
        } else {
            let lines = entries.map { "        \"\($0.name)\": \($0.kind)" }
            dictBody = "[\n\(lines.joined(separator: ",\n"))\n    ]"
        }

        let extensionDecl: ExtensionDeclSyntax = try ExtensionDeclSyntax(
            """
            extension \(type): XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    \(raw: dictBody)
                }
            }
            """
        )
        return [extensionDecl]
    }
}

// MARK: - AttributeListSyntax helper

private extension AttributeListSyntax {
    /// Returns `.attribute` or `.element` if a recognised annotation is present, else `nil`.
    var xmlFieldAnnotationKind: String? {
        for attr in self {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let name = attrSyntax.attributeName.trimmedDescription
            if name == "XMLAttribute" { return ".attribute" }
            if name == "XMLElement"   { return ".element" }
        }
        return nil
    }
}
