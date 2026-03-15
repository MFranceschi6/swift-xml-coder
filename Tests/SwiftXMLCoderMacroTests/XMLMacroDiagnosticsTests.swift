import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SwiftXMLCoderMacroImplementation

// Macro registry used by assertMacroExpansion.
private let testMacros: [String: any Macro.Type] = [
    "XMLCodable": XMLCodableMacro.self,
    "XMLAttribute": XMLAttributeMacro.self,
    "XMLCDATA": XMLCDATAMacro.self,
    "XMLChild": XMLChildMacro.self,
    "XMLDateFormat": XMLDateFormatMacro.self,
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

    func test_xmlDateFormat_expandsToNoPeers() {
        // PeerMacro that generates no peers: annotation stripped, property unchanged.
        assertMacroExpansion(
            """
            struct S {
                @XMLDateFormat(.xsdDate) var birthDate: Date
            }
            """,
            expandedSource:
            """
            struct S {
                var birthDate: Date
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLCodable with @XMLDateFormat — synthesises xmlPropertyDateHints

    func test_xmlCodable_withDateFormat_synthesisesDateHints() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Schedule: Codable {
                @XMLDateFormat(.xsdDate) var startDate: Date
                @XMLDateFormat(.xsdTime) var startTime: Date
                var createdAt: Date
            }
            """,
            expandedSource:
            """
            struct Schedule: Codable {
                var startDate: Date
                var startTime: Date
                var createdAt: Date
            }

            extension Schedule: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Schedule: XMLDateCodingOverrideProvider {
                static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
                    [
                    "startDate": .xsdDate,
                    "startTime": .xsdTime
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_withMixedAnnotations_synthesisesBothDictionaries() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Event: Codable {
                @XMLAttribute var id: String
                @XMLDateFormat(.xsdDate) var date: Date
                var name: String
            }
            """,
            expandedSource:
            """
            struct Event: Codable {
                var id: String
                var date: Date
                var name: String
            }

            extension Event: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "id": .attribute
                ]
                }
            }

            extension Event: XMLDateCodingOverrideProvider {
                static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
                    [
                    "date": .xsdDate
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_withNoDateFormat_doesNotSynthesiseDateHintsExtension() {
        // When there are no @XMLDateFormat annotations, no XMLDateCodingOverrideProvider
        // extension must be emitted.
        assertMacroExpansion(
            """
            @XMLCodable
            struct Plain: Codable {
                @XMLAttribute var id: String
                var name: String
            }
            """,
            expandedSource:
            """
            struct Plain: Codable {
                var id: String
                var name: String
            }

            extension Plain: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "id": .attribute
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_withComplexDateFormatArg_passesVerbatim() {
        // @XMLDateFormat with a parameterised case: the argument is emitted verbatim
        // into the synthesised dictionary.
        assertMacroExpansion(
            """
            @XMLCodable
            struct Tz: Codable {
                @XMLDateFormat(.xsdDateWithTimezone(identifier: "Europe/Rome")) var date: Date
            }
            """,
            expandedSource:
            """
            struct Tz: Codable {
                var date: Date
            }

            extension Tz: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Tz: XMLDateCodingOverrideProvider {
                static var xmlPropertyDateHints: [String: XMLDateFormatHint] {
                    [
                    "date": .xsdDateWithTimezone(identifier: "Europe/Rome")
                ]
                }
            }
            """,
            macros: testMacros
        )
    }
}
