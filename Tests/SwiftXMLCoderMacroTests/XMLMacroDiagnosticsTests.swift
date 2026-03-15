import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SwiftXMLCoderMacroImplementation

// Macro registry used by assertMacroExpansion.
private let testMacros: [String: any Macro.Type] = [
    "XMLCodable": XMLCodableMacro.self,
    "XMLAttribute": XMLAttributeMacro.self,
    "XMLChild": XMLChildMacro.self
]

final class XMLMacroDiagnosticsTests: XCTestCase {

    // MARK: - @XMLCodable on invalid targets

    func test_xmlCodable_onEnum_emitsDiagnostic() {
        assertMacroExpansion(
            """
            @XMLCodable
            enum Status: String {
                case active
                case inactive
            }
            """,
            expandedSource:
            """
            enum Status: String {
                case active
                case inactive
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@XMLCodable can only be attached to a struct or class declaration.",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }

    func test_xmlCodable_onActor_emitsDiagnostic() {
        assertMacroExpansion(
            """
            @XMLCodable
            actor Worker {
                var id: Int = 0
            }
            """,
            expandedSource:
            """
            actor Worker {
                var id: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@XMLCodable can only be attached to a struct or class declaration.",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - @XMLCodable on valid targets — no diagnostics

    func test_xmlCodable_onStruct_expandsCorrectly() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Item: Codable {
                @XMLAttribute var id: String
                @XMLChild var name: String
                var value: Int
            }
            """,
            expandedSource:
            """
            struct Item: Codable {
                var id: String
                var name: String
                var value: Int
            }

            extension Item: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "id": .attribute,
                    "name": .element
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_onClass_expandsCorrectly() {
        assertMacroExpansion(
            """
            @XMLCodable
            class Order: Codable {
                @XMLAttribute var orderId: String = ""
            }
            """,
            expandedSource:
            """
            class Order: Codable {
                var orderId: String = ""
            }

            extension Order: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "orderId": .attribute
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_noAnnotations_producesEmptyDict() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Plain: Codable {
                var name: String
                var count: Int
            }
            """,
            expandedSource:
            """
            struct Plain: Codable {
                var name: String
                var count: Int
            }

            extension Plain: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLAttribute and @XMLChild as pure peer markers — no expansion

    func test_xmlAttribute_expandsToNoPeers() {
        // PeerMacro that generates no peers: the attribute annotation is consumed,
        // the property remains unchanged (annotation stripped from expanded output).
        assertMacroExpansion(
            """
            struct S {
                @XMLAttribute var id: Int
            }
            """,
            expandedSource:
            """
            struct S {
                var id: Int
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlChild_expandsToNoPeers() {
        // PeerMacro that generates no peers: annotation stripped, property unchanged.
        assertMacroExpansion(
            """
            struct S {
                @XMLChild var name: String
            }
            """,
            expandedSource:
            """
            struct S {
                var name: String
            }
            """,
            macros: testMacros
        )
    }
}
