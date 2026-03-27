import Foundation

extension XMLTreeDocument {

    /// Walks the tree document and calls `emit` for each ``XMLStreamEvent`` in document order.
    ///
    /// This is the bridge between the tree representation and the event-based pipeline.
    /// It produces the same logical event sequence as if the document had been parsed by
    /// ``XMLStreamParser`` from equivalent XML bytes.
    func walkEvents(_ emit: (XMLStreamEvent) throws -> Void) throws {
        let encoding = metadata.encoding ?? "UTF-8"
        try emit(.startDocument(version: metadata.xmlVersion, encoding: encoding, standalone: metadata.standalone))

        for node in prologueNodes {
            switch node {
            case .comment(let value):
                try emit(.comment(value))
            case .processingInstruction(let target, let data):
                try emit(.processingInstruction(target: target, data: data))
            }
        }

        try walkElement(root, emit: emit)

        for node in epilogueNodes {
            switch node {
            case .comment(let value):
                try emit(.comment(value))
            case .processingInstruction(let target, let data):
                try emit(.processingInstruction(target: target, data: data))
            }
        }

        try emit(.endDocument)
    }

    private func walkElement(_ element: XMLTreeElement, emit: (XMLStreamEvent) throws -> Void) throws {
        try emit(.startElement(
            name: element.name,
            attributes: element.attributes,
            namespaceDeclarations: element.namespaceDeclarations
        ))

        for child in element.children {
            switch child {
            case .element(let childElement):
                try walkElement(childElement, emit: emit)
            case .text(let value):
                try emit(.text(value))
            case .cdata(let value):
                try emit(.cdata(value))
            case .comment(let value):
                try emit(.comment(value))
            case .processingInstruction(let target, let data):
                try emit(.processingInstruction(target: target, data: data))
            }
        }

        try emit(.endElement(name: element.name))
    }
}
