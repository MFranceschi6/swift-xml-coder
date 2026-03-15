# Namespaces

Encode and decode XML documents that use XML namespaces.

## Overview

SwiftXMLCoder represents namespaces through ``XMLNamespace`` and resolves qualified names through ``XMLNamespaceResolver``. Namespace-aware encoding is configured at the document level, and decoding tolerates namespace-prefixed elements transparently.

## Declaring a Namespace on Encode

Pass a root namespace to `XMLDocument` or use `XMLEncoder.Configuration.writerConfiguration`:

```swift
import SwiftXMLCoder

let soapNS = XMLNamespace(prefix: "soap", uri: "http://schemas.xmlsoap.org/soap/envelope/")

let encoder = XMLEncoder(configuration: .init(
    rootElementName: "Envelope",
    writerConfiguration: .init(
        rootNamespace: soapNS
    )
))
```

## Namespace-Aware Tree Building

Use ``XMLDocument`` directly to build a document tree with mixed namespaces:

```swift
let ns = XMLNamespace(prefix: "ex", uri: "http://example.com/")
let doc = try XMLDocument(rootElementName: "root", rootNamespace: ns)
let child = try doc.createElement(named: "child", namespace: ns)
try doc.appendChild(child, to: doc.rootElement()!)
let data = try doc.serializedData()
// <ex:root xmlns:ex="http://example.com/"><ex:child/></ex:root>
```

## Resolving Namespaces

``XMLNamespaceResolver`` maintains a scoped prefix-to-URI stack during document traversal:

```swift
var resolver = XMLNamespaceResolver()
try resolver.push(declarations: [
    XMLNamespaceDeclaration(prefix: "ex", namespaceURI: "http://example.com/")
])

let uri = resolver.namespaceURI(forPrefix: "ex")
// "http://example.com/"

let qualified = try resolver.resolveElementName(
    XMLQualifiedName(localName: "item", prefix: "ex")
)
// XMLQualifiedName(localName: "item", prefix: "ex", namespaceURI: "http://example.com/")

resolver.pop()
```

## Validating Namespaces

``XMLNamespaceValidator`` checks a fully-built ``XMLTreeDocument`` for namespace consistency:

```swift
try XMLNamespaceValidator.validate(document: tree)
// throws XMLNamespaceResolutionError if any prefix is undeclared
```

Use `.strict` mode to also reject default-namespace shadowing and duplicate prefix declarations.
