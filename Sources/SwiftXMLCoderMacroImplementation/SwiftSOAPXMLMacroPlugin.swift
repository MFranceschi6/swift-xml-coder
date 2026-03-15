import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftXMLCoderMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        XMLAttributeMacro.self,
        XMLElementMacro.self,
        XMLCodableMacro.self,
    ]
}
