import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftXMLCoderMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        XMLAttributeMacro.self,
        XMLCDATAMacro.self,
        XMLChildMacro.self,
        XMLCodableMacro.self,
        XMLDateFormatMacro.self,
        XMLExpandEmptyMacro.self,
        XMLIgnoreMacro.self,
        XMLNamespaceMacro.self,
        XMLTextMacro.self,
    ]
}
