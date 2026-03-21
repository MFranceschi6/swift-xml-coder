import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Implementation of `@XMLText` — a pure syntax marker that generates no peers.
///
/// The macro's sole purpose is to be detectable by `@XMLCodable` when it scans the
/// member list of an annotated type.  It intentionally returns an empty peer list.
public struct XMLTextMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
