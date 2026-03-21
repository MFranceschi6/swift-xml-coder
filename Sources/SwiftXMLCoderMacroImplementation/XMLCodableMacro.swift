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
/// Scans the stored properties of the attached struct or class for `@XMLAttribute`,
/// `@XMLChild`, `@XMLDateFormat`, `@XMLCDATA`, and `@XMLExpandEmpty` annotations,
/// then synthesises:
///
/// 1. An `XMLFieldCodingOverrideProvider` extension whose `xmlFieldNodeKinds` dictionary
///    maps each `@XMLAttribute`/`@XMLChild`-annotated field name to its `XMLFieldNodeKind`.
/// 2. An `XMLDateCodingOverrideProvider` extension whose `xmlPropertyDateHints` dictionary
///    maps each `@XMLDateFormat`-annotated field name to its `XMLDateFormatHint`.
///    This extension is only emitted when at least one `@XMLDateFormat` annotation is present.
/// 3. An `XMLStringCodingOverrideProvider` extension whose `xmlPropertyStringHints` dictionary
///    maps each `@XMLCDATA`-annotated field name to `.cdata`.
///    This extension is only emitted when at least one `@XMLCDATA` annotation is present.
/// 4. An `XMLExpandEmptyProvider` extension whose `xmlPropertyExpandEmptyKeys` set contains
///    each `@XMLExpandEmpty`-annotated field name.
///    This extension is only emitted when at least one `@XMLExpandEmpty` annotation is present.
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

        // Scan member stored properties for annotations.
        var fieldKindEntries: [(name: String, kind: String)] = []
        var dateHintEntries: [(name: String, hint: String)] = []
        var stringHintEntries: [String] = []    // property names annotated with @XMLCDATA
        var expandEmptyEntries: [String] = []   // property names annotated with @XMLExpandEmpty

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Skip computed properties.
            guard varDecl.bindings.allSatisfy({ $0.accessorBlock == nil }) else { continue }

            let annotationKind = varDecl.attributes.xmlFieldAnnotationKind
            let dateHint = varDecl.attributes.xmlDateFormatHint
            let hasCDATAAnnotation = varDecl.attributes.hasXMLCDATAAnnotation
            let hasExpandEmptyAnnotation = varDecl.attributes.hasXMLExpandEmptyAnnotation

            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                let name = identifier.identifier.text
                if let kind = annotationKind {
                    fieldKindEntries.append((name: name, kind: kind))
                }
                if let hint = dateHint {
                    dateHintEntries.append((name: name, hint: hint))
                }
                if hasCDATAAnnotation {
                    stringHintEntries.append(name)
                }
                if hasExpandEmptyAnnotation {
                    expandEmptyEntries.append(name)
                }
            }
        }

        // Build the xmlFieldNodeKinds dictionary body.
        let kindDictBody: String
        if fieldKindEntries.isEmpty {
            kindDictBody = "[:]"
        } else {
            let lines = fieldKindEntries.map { "        \"\($0.name)\": \($0.kind)" }
            kindDictBody = "[\n\(lines.joined(separator: ",\n"))\n    ]"
        }

        let fieldKindsExtension: ExtensionDeclSyntax = try ExtensionDeclSyntax(
            """
            extension \(type): XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    \(raw: kindDictBody)
                }
            }
            """
        )

        var extensions: [ExtensionDeclSyntax] = [fieldKindsExtension]

        // Only emit the date hints extension when at least one @XMLDateFormat is present.
        if dateHintEntries.isEmpty == false {
            let hintLines = dateHintEntries.map { "        \"\($0.name)\": \($0.hint)" }
            let hintDictBody = "[\n\(hintLines.joined(separator: ",\n"))\n    ]"
            let dateHintsExtension: ExtensionDeclSyntax = try ExtensionDeclSyntax(
                """
                extension \(type): XMLDateCodingOverrideProvider {
                    static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
                        \(raw: hintDictBody)
                    }
                }
                """
            )
            extensions.append(dateHintsExtension)
        }

        // Only emit the string hints extension when at least one @XMLCDATA is present.
        if stringHintEntries.isEmpty == false {
            let stringLines = stringHintEntries.map { "        \"\($0)\": .cdata" }
            let stringDictBody = "[\n\(stringLines.joined(separator: ",\n"))\n    ]"
            let stringHintsExtension: ExtensionDeclSyntax = try ExtensionDeclSyntax(
                """
                extension \(type): XMLStringCodingOverrideProvider {
                    static var xmlPropertyStringHints: [String: XMLStringEncodingHint] {
                        \(raw: stringDictBody)
                    }
                }
                """
            )
            extensions.append(stringHintsExtension)
        }

        // Only emit the expand-empty extension when at least one @XMLExpandEmpty is present.
        if expandEmptyEntries.isEmpty == false {
            let keySetBody = expandEmptyEntries.map { "\"\($0)\"" }.joined(separator: ", ")
            let expandEmptyExtension: ExtensionDeclSyntax = try ExtensionDeclSyntax(
                """
                extension \(type): XMLExpandEmptyProvider {
                    static var xmlPropertyExpandEmptyKeys: Set<String> {
                        [\(raw: keySetBody)]
                    }
                }
                """
            )
            extensions.append(expandEmptyExtension)
        }

        return extensions
    }
}

// MARK: - AttributeListSyntax helpers

private extension AttributeListSyntax {
    /// Returns `.attribute`, `.element`, `.textContent`, or `.ignored` if a recognised annotation is present, else `nil`.
    var xmlFieldAnnotationKind: String? {
        for attr in self {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let name = attrSyntax.attributeName.trimmedDescription
            if name == "XMLAttribute" { return ".attribute" }
            if name == "XMLChild"     { return ".element" }
            if name == "XMLText"      { return ".textContent" }
            if name == "XMLIgnore"    { return ".ignored" }
        }
        return nil
    }

    /// Returns `true` if a `@XMLExpandEmpty` annotation is present on the property.
    var hasXMLExpandEmptyAnnotation: Bool {
        for attr in self {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            if attrSyntax.attributeName.trimmedDescription == "XMLExpandEmpty" { return true }
        }
        return false
    }

    /// Returns `true` if a `@XMLCDATA` annotation is present on the property.
    var hasXMLCDATAAnnotation: Bool {
        for attr in self {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            if attrSyntax.attributeName.trimmedDescription == "XMLCDATA" { return true }
        }
        return false
    }

    /// Returns the verbatim argument expression of `@XMLDateFormat(...)` if present, else `nil`.
    ///
    /// The returned string is the trimmed description of the first argument expression
    /// (e.g. `".xsdDate"`, `".xsdDateWithTimezone(identifier: \"UTC\")"`) and is emitted
    /// verbatim into the synthesised `xmlPropertyDateHints` dictionary.
    var xmlDateFormatHint: String? {
        for attr in self {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let name = attrSyntax.attributeName.trimmedDescription
            guard name == "XMLDateFormat" else { continue }
            guard let args = attrSyntax.arguments,
                  case .argumentList(let list) = args,
                  let first = list.first else { continue }
            return first.expression.trimmedDescription
        }
        return nil
    }
}
