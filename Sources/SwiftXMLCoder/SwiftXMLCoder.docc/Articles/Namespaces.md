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

## Declaring a Root Namespace via Macro (Swift 5.9+)

`@XMLRootNamespace` generates an ``XMLRootNode`` conformance that sets both the root element name and its namespace URI. Import `SwiftXMLCoderMacros` and annotate the type:

```swift
import SwiftXMLCoder
import SwiftXMLCoderMacros

@XMLRootNamespace("http://schemas.example.com/orders/v2")
struct Order: Codable {
    var id: String
    var total: Double
}
// Encodes as:
// <Order xmlns="http://schemas.example.com/orders/v2">
//     <id>...</id><total>...</total>
// </Order>
```

The macro uses the type name as the root element name by default. To customise the element name, conform to ``XMLRootNode`` manually instead.

## Per-Field Namespace Override

`XMLFieldNamespaceProvider` lets a `Codable` type declare a different namespace for individual child elements and attributes, independently of the root namespace. Implement the static property `xmlFieldNamespaces` as a `[String: XMLNamespace]` dictionary keyed by coding key name:

```swift
import SwiftXMLCoder

struct Order: Codable, XMLFieldNamespaceProvider {
    var id: String
    var total: Double
    var shippingAddress: String

    static let xmlFieldNamespaces: [String: XMLNamespace] = [
        "shippingAddress": XMLNamespace(prefix: "ship", uri: "http://schemas.example.com/shipping")
    ]
}

// Encodes as:
// <Order>
//   <id>…</id>
//   <total>…</total>
//   <ship:shippingAddress xmlns:ship="http://schemas.example.com/shipping">…</ship:shippingAddress>
// </Order>
```

The `XMLEncoder` and `XMLDecoder` consult `xmlFieldNamespaces` automatically during encoding and decoding. Fields not listed in the dictionary use the document's default namespace.

### Macro Shorthand (Swift 5.9+)

When using `@XMLCodable`, annotate individual properties with `@XMLFieldNamespace` instead of implementing `XMLFieldNamespaceProvider` manually:

```swift
import SwiftXMLCoderMacros

@XMLCodable
struct Order: Codable {
    var id: String
    var total: Double
    @XMLFieldNamespace("http://schemas.example.com/shipping", prefix: "ship")
    var shippingAddress: String
}
```

`@XMLFieldNamespace` generates the `xmlFieldNamespaces` dictionary entry for the annotated property only.
