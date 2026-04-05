# Canonicalization

Produce deterministic XML output suitable for digest and signature workflows.

## Overview

``XMLCanonicalizer`` defines two canonicalization styles:

- Tree-based canonicalization from ``XMLTreeDocument`` using ``XMLTransform``.
- Streaming canonicalization from raw `Data` or ``XMLStreamEvent`` using ``XMLEventTransform``.

`SwiftXMLCoder` ships ``XMLDefaultCanonicalizer`` as the default implementation.

## Tree-Based Usage

```swift
import SwiftXMLCoder

let parser = XMLTreeParser()
let tree = try parser.parse(data: xmlData)

let canonicalizer = XMLDefaultCanonicalizer()
let canonical = try canonicalizer.canonicalize(tree)
```

Customize behavior with ``XMLCanonicalizationOptions`` and transforms:

```swift
let data = try canonicalizer.canonicalize(
    tree,
    options: XMLCanonicalizationOptions(includeComments: true),
    transforms: [MyTreeTransform()]
)
```

## Streaming Usage

Canonicalize directly from input bytes:

```swift
let canonical = try canonicalizer.canonicalize(
    data: xmlData,
    options: XMLCanonicalizationOptions(),
    eventTransforms: [MyEventTransform()]
)
```

Or emit through a callback sink:

```swift
try canonicalizer.canonicalize(
    data: xmlData,
    options: XMLCanonicalizationOptions(),
    eventTransforms: []
) { chunk in
    sink.write(chunk)
}
```

## Writing Custom Transforms

Implement ``XMLTransform`` (tree path) or ``XMLEventTransform`` (streaming path) to inject
preprocessing steps into the canonicalization pipeline.

### Tree transform example

Use ``XMLTransform`` when your logic needs random access to the document structure —
for example, to strip a subtree, inject elements, or reorder children.

```swift
struct StripCommentsTransform: XMLTransform {
    func apply(
        to document: XMLTreeDocument,
        options: XMLCanonicalizationOptions
    ) throws -> XMLTreeDocument {
        let strippedRoot = strip(element: document.root)
        return XMLTreeDocument(
            root: strippedRoot,
            metadata: document.metadata,
            prologueNodes: document.prologueNodes,
            epilogueNodes: document.epilogueNodes
        )
    }

    private func strip(element: XMLTreeElement) -> XMLTreeElement {
        let children: [XMLTreeNode] = element.children.compactMap { node in
            switch node {
            case .comment: return nil
            case .element(let child): return .element(strip(element: child))
            default: return node
            }
        }
        return XMLTreeElement(
            name: element.name,
            attributes: element.attributes,
            namespaceDeclarations: element.namespaceDeclarations,
            children: children
        )
    }
}

// Usage
let canonical = try XMLDefaultCanonicalizer().canonicalize(
    tree,
    options: XMLCanonicalizationOptions(),
    transforms: [StripCommentsTransform()]
)
```

### Event transform example

Use ``XMLEventTransform`` when you want to operate in the streaming path — for example,
to filter elements, rename tags, or inject events on the fly. Implement `process(_:)` to
map one input event to zero or more output events, and `finalize()` to flush any buffered
state at the end of the stream.

```swift
struct RenameElementTransform: XMLEventTransform {
    let from: String
    let to: String

    mutating func process(_ event: XMLStreamEvent) throws -> [XMLStreamEvent] {
        switch event {
        case .startElement(let name, let attrs, let nsDecls) where name.localName == from:
            let renamed = XMLQualifiedName(localName: to, namespaceURI: name.namespaceURI)
            return [.startElement(name: renamed, attributes: attrs, namespaceDeclarations: nsDecls)]
        case .endElement(let name) where name.localName == from:
            let renamed = XMLQualifiedName(localName: to, namespaceURI: name.namespaceURI)
            return [.endElement(name: renamed)]
        default:
            return [event]
        }
    }

    mutating func finalize() throws -> [XMLStreamEvent] { [] }
}

// Usage
let canonical = try XMLDefaultCanonicalizer().canonicalize(
    data: xmlData,
    options: XMLCanonicalizationOptions(),
    eventTransforms: [RenameElementTransform(from: "oldName", to: "newName")]
)
```

Transforms in a pipeline run in order: the output of stage *n* is the input of stage *n+1*.
`finalize()` is called on each transform in order after the last event, allowing buffered
transforms (e.g. accumulators, sorters) to emit their final output.

## Error Handling

Canonicalization APIs throw ``XMLParsingError``.
