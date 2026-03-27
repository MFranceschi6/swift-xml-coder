import Foundation

// Internal SAX-event to XMLTreeDocument bridge used by decode paths that want
// to avoid the libxml2 DOM -> Swift tree double materialization.
struct _XMLSAXTreeBuilder {
    private struct ElementFrame {
        let name: XMLQualifiedName
        let attributes: [XMLTreeAttribute]
        let namespaceDeclarations: [XMLNamespaceDeclaration]
        let sourceLine: Int?
        var children: [XMLTreeNode] = []
    }

    private var stack: [ElementFrame] = []
    private var root: XMLTreeElement?
    private var seenRoot: Bool = false
    private var closedRoot: Bool = false
    private var prologueNodes: [XMLDocumentNode] = []
    private var epilogueNodes: [XMLDocumentNode] = []
    private var metadata = XMLDocumentStructuralMetadata()

    mutating func consume(event: XMLStreamEvent, line: Int?) throws {
        switch event {
        case .startDocument(let version, let encoding, let standalone):
            metadata = XMLDocumentStructuralMetadata(
                xmlVersion: version,
                encoding: encoding,
                standalone: standalone
            )
        case .endDocument:
            break
        case .startElement(let name, let attributes, let namespaceDeclarations):
            if closedRoot {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNEXPECTED_TRAILING_ELEMENT] Found element '\(name.localName)' after root end."
                )
            }
            if stack.isEmpty {
                seenRoot = true
            }
            stack.append(
                ElementFrame(
                    name: name,
                    attributes: attributes,
                    namespaceDeclarations: namespaceDeclarations,
                    sourceLine: line
                )
            )
        case .endElement(let name):
            guard let frame = stack.popLast() else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNBALANCED_END] Found closing tag '\(name.localName)' with no matching start element."
                )
            }
            guard frame.name == name else {
                throw XMLParsingError.parseFailed(
                    message: "[XML6_5_UNBALANCED_END] Closing tag '\(name.qualifiedName)' does not match open tag '\(frame.name.qualifiedName)'."
                )
            }
            let element = XMLTreeElement(
                name: frame.name,
                attributes: frame.attributes,
                namespaceDeclarations: frame.namespaceDeclarations,
                children: frame.children,
                metadata: XMLNodeStructuralMetadata(sourceLine: frame.sourceLine)
            )
            if stack.isEmpty {
                root = element
                closedRoot = true
            } else {
                stack[stack.count - 1].children.append(.element(element))
            }
        case .text(let text):
            guard !text.isEmpty else { return }
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].children.append(.text(text))
        case .cdata(let text):
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].children.append(.cdata(text))
        case .comment(let text):
            if stack.isEmpty {
                if seenRoot {
                    epilogueNodes.append(.comment(text))
                } else {
                    prologueNodes.append(.comment(text))
                }
            } else {
                stack[stack.count - 1].children.append(.comment(text))
            }
        case .processingInstruction(let target, let data):
            if stack.isEmpty {
                if seenRoot {
                    epilogueNodes.append(.processingInstruction(target: target, data: data))
                } else {
                    prologueNodes.append(.processingInstruction(target: target, data: data))
                }
            } else {
                stack[stack.count - 1].children.append(.processingInstruction(target: target, data: data))
            }
        }
    }

    func finalize() throws -> XMLTreeDocument {
        guard stack.isEmpty else {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_UNBALANCED_START] XML ended before all open elements were closed."
            )
        }
        guard let root else {
            throw XMLParsingError.parseFailed(message: "[XML6_5_MISSING_ROOT] XML document does not contain a root element.")
        }
        return XMLTreeDocument(
            root: root,
            metadata: metadata,
            prologueNodes: prologueNodes,
            epilogueNodes: epilogueNodes
        )
    }
}
