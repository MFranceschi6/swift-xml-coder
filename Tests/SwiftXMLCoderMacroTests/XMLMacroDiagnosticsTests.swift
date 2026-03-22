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
    "XMLExpandEmpty": XMLExpandEmptyMacro.self,
    "XMLFieldNamespace": XMLFieldNamespaceMacro.self,
    "XMLIgnore": XMLIgnoreMacro.self,
    "XMLNamespace": XMLNamespaceMacro.self,
    "XMLRootNamespace": XMLNamespaceMacro.self,
    "XMLText": XMLTextMacro.self
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

    // MARK: - @XMLText expansion

    func test_xmlCodable_withXMLText_generatesTextContentEntry() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Price: Codable {
                @XMLAttribute var currency: String
                @XMLText var amount: Double
            }
            """,
            expandedSource:
            """
            struct Price: Codable {
                var currency: String
                var amount: Double
            }

            extension Price: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "currency": .attribute,
                    "amount": .textContent
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLIgnore expansion

    func test_xmlCodable_withXMLIgnore_generatesIgnoredEntry() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Config: Codable {
                var host: String
                @XMLIgnore var _cache: Int?
            }
            """,
            expandedSource:
            """
            struct Config: Codable {
                var host: String
                var _cache: Int?
            }

            extension Config: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [
                    "_cache": .ignored
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLRootNamespace expansion

    func test_xmlRootNamespace_onStruct_generatesXMLRootNodeConformance() {
        assertMacroExpansion(
            """
            @XMLRootNamespace("http://example.com/orders")
            struct Order: Codable {
                var id: String
            }
            """,
            expandedSource:
            """
            struct Order: Codable {
                var id: String
            }

            extension Order: XMLRootNode {
                static var xmlRootElementName: String {
                    "Order"
                }
                static var xmlRootElementNamespaceURI: String? {
                    "http://example.com/orders"
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlRootNamespace_onEnum_emitsDiagnostic() {
        assertMacroExpansion(
            """
            @XMLRootNamespace("http://example.com")
            enum Status {
                case active
            }
            """,
            expandedSource:
            """
            enum Status {
                case active
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@XMLNamespace can only be attached to a struct or class declaration.",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Peer macro coverage: @XMLCDATA, @XMLExpandEmpty, @XMLFieldNamespace

    func test_xmlCDATA_expandsToNoPeers() {
        assertMacroExpansion(
            """
            struct S {
                @XMLCDATA var content: String
            }
            """,
            expandedSource:
            """
            struct S {
                var content: String
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlExpandEmpty_expandsToNoPeers() {
        assertMacroExpansion(
            """
            struct S {
                @XMLExpandEmpty var flag: Bool
            }
            """,
            expandedSource:
            """
            struct S {
                var flag: Bool
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlFieldNamespace_expandsToNoPeers() {
        assertMacroExpansion(
            """
            struct S {
                @XMLFieldNamespace(uri: "http://example.com") var name: String
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

    // MARK: - @XMLCodable with @XMLCDATA — synthesises XMLStringCodingOverrideProvider

    func test_xmlCodable_withCDATA_synthesisesStringHints() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Message: Codable {
                @XMLCDATA var body: String
                var subject: String
            }
            """,
            expandedSource:
            """
            struct Message: Codable {
                var body: String
                var subject: String
            }

            extension Message: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Message: XMLStringCodingOverrideProvider {
                static var xmlPropertyStringHints: [String: XMLStringEncodingHint] {
                    [
                    "body": .cdata
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLCodable with @XMLExpandEmpty — synthesises XMLExpandEmptyProvider

    func test_xmlCodable_withExpandEmpty_synthesisesExpandEmptyKeys() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Wrapper: Codable {
                @XMLExpandEmpty var enabled: Bool
                var name: String
            }
            """,
            expandedSource:
            """
            struct Wrapper: Codable {
                var enabled: Bool
                var name: String
            }

            extension Wrapper: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Wrapper: XMLExpandEmptyProvider {
                static var xmlPropertyExpandEmptyKeys: Set<String> {
                    ["enabled"]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLCodable with @XMLFieldNamespace — synthesises XMLFieldNamespaceProvider

    func test_xmlCodable_withFieldNamespace_synthesisesFieldNamespaces() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Invoice: Codable {
                @XMLFieldNamespace(uri: "http://example.com/billing") var total: Double
                var id: String
            }
            """,
            expandedSource:
            """
            struct Invoice: Codable {
                var total: Double
                var id: String
            }

            extension Invoice: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Invoice: XMLFieldNamespaceProvider {
                static var xmlFieldNamespaces: [String: XMLNamespace] {
                    [
                    "total": XMLNamespace(uri: "http://example.com/billing")
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    func test_xmlCodable_withFieldNamespace_prefixAndUri() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Invoice: Codable {
                @XMLFieldNamespace(prefix: "bill", uri: "http://example.com/billing") var total: Double
            }
            """,
            expandedSource:
            """
            struct Invoice: Codable {
                var total: Double
            }

            extension Invoice: XMLFieldCodingOverrideProvider {
                static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] {
                    [:]
                }
            }

            extension Invoice: XMLFieldNamespaceProvider {
                static var xmlFieldNamespaces: [String: XMLNamespace] {
                    [
                    "total": XMLNamespace(prefix: "bill", uri: "http://example.com/billing")
                ]
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @XMLCodable skips computed properties

    func test_xmlCodable_skipsComputedProperties() {
        assertMacroExpansion(
            """
            @XMLCodable
            struct Model: Codable {
                @XMLAttribute var id: String
                var computed: String {
                    "hello"
                }
            }
            """,
            expandedSource:
            """
            struct Model: Codable {
                var id: String
                var computed: String {
                    "hello"
                }
            }

            extension Model: XMLFieldCodingOverrideProvider {
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
}
