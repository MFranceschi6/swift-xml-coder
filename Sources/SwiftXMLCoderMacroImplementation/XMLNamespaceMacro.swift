import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostic IDs

private enum XMLNamespaceDiagnostic {
    static let invalidDecl = DiagnosticMessage(
        id: "XML8B_INVALID_DECL",
        message: "@XMLNamespace can only be attached to a struct or class declaration.",
        severity: .error
    )

    static let emptyURI = DiagnosticMessage(
        id: "XML8B_EMPTY_URI",
        message: "@XMLNamespace requires a non-empty namespace URI string.",
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

// MARK: - XMLNamespaceMacro

/// Implementation of `@XMLNamespace`.
///
/// Generates an `XMLRootNode` extension that supplies a static `xmlRootElementNamespaceURI`
/// property, wiring the provided URI into the XML encoder/decoder root element namespace.
public struct XMLNamespaceMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {

        // Only struct / class allowed.
        guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: XMLNamespaceDiagnostic.invalidDecl))
            return []
        }

        // Extract the URI string literal argument.
        guard let args = node.arguments,
              case .argumentList(let list) = args,
              let firstArg = list.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: XMLNamespaceDiagnostic.emptyURI))
            return []
        }

        let uri = segment.content.text
        guard uri.isEmpty == false else {
            context.diagnose(Diagnostic(node: node, message: XMLNamespaceDiagnostic.emptyURI))
            return []
        }

        // Derive the type name string for xmlRootElementName default.
        let typeName = type.trimmedDescription

        let ext: ExtensionDeclSyntax = try ExtensionDeclSyntax(
            """
            extension \(type): XMLRootNode {
                static var xmlRootElementName: String { "\(raw: typeName)" }
                static var xmlRootElementNamespaceURI: String? { "\(raw: uri)" }
            }
            """
        )
        return [ext]
    }
}
