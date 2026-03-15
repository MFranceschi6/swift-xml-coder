# XPath Queries

Query parsed XML documents using XPath 1.0 expressions.

## Overview

``XMLDocument`` exposes XPath evaluation via ``XMLDocument/xpathFirstNode(_:namespaces:)`` and ``XMLDocument/xpathNodes(_:namespaces:)``. Queries are evaluated against the libxml2 XPath engine and return ``XMLNode`` wrappers.

## Querying a Single Node

```swift
import SwiftXMLCoder

let xml = Data("""
<library>
  <book id="1"><title>Swift in Practice</title></book>
  <book id="2"><title>Advanced Swift</title></book>
</library>
""".utf8)

let doc = try XMLDocument(data: xml)
let node = try doc.xpathFirstNode("/library/book[@id='1']/title")
print(node?.content ?? "not found")
// "Swift in Practice"
```

## Querying Multiple Nodes

```swift
let nodes = try doc.xpathNodes("/library/book/title")
for node in nodes {
    print(node.content ?? "")
}
// "Swift in Practice"
// "Advanced Swift"
```

## Namespace-Aware Queries

Register prefix-to-URI bindings to query documents that use XML namespaces:

```swift
let xml = Data("""
<lib:library xmlns:lib="http://example.com/library">
  <lib:book><lib:title>Swift</lib:title></lib:book>
</lib:library>
""".utf8)

let doc = try XMLDocument(data: xml)
let node = try doc.xpathFirstNode(
    "/lib:library/lib:book/lib:title",
    namespaces: ["lib": "http://example.com/library"]
)
print(node?.content ?? "")
// "Swift"
```

The `namespaces` dictionary maps the XPath prefix (used in the expression) to the namespace URI declared in the document. The prefixes in the expression do not need to match those in the document.

## Accessing Node Properties

Each returned ``XMLNode`` exposes:

- `content` — text content of the node
- `name` — local element name
- `attributes` — dictionary of attribute name → value
- `children` — child nodes
