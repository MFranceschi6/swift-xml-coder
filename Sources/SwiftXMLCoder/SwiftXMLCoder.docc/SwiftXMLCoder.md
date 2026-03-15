# ``SwiftXMLCoder``

A Codable-compatible XML encoder and decoder backed by libxml2, with XPath, namespace, canonicalization, and macro support.

## Overview

SwiftXMLCoder lets you encode and decode Swift `Codable` types to and from XML with full control over element vs. attribute mapping, namespaces, date strategies, and serialization policies.

```swift
import SwiftXMLCoder

struct Book: Codable {
    var title: String
    var author: String
    var year: Int
}

let book = Book(title: "Swift in Practice", author: "Apple", year: 2024)
let encoder = XMLEncoder()
let data = try encoder.encode(book)
// <Book><title>Swift in Practice</title><author>Apple</author><year>2024</year></Book>

let decoder = XMLDecoder()
let decoded = try decoder.decode(Book.self, from: data)
```

## Topics

### Getting Started

- <doc:GettingStarted>

### Core Encoder & Decoder

- ``XMLEncoder``
- ``XMLDecoder``

### Document & Tree

- ``XMLDocument``
- ``XMLTreeDocument``
- ``XMLTreeElement``
- ``XMLTreeNode``
- ``XMLTreeAttribute``
- ``XMLTreeParser``
- ``XMLTreeWriter``

### Field Mapping

- <doc:FieldMapping>
- ``XMLFieldCodingOverrides``
- ``XMLFieldCodingOverrideProvider``
- ``XMLFieldNodeKind``
- ``XMLAttribute``
- ``XMLChild``
- ``XMLRootNode``
- ``XMLStringEncodingHint``
- ``XMLStringCodingOverrideProvider``
- ``XMLExpandEmptyProvider``
- ``XMLDateCodingOverrideProvider``

### Key Transformation

- ``XMLKeyTransformStrategy``

### Date & Temporal Types

- ``XMLDateFormatHint``
- ``XMLTime``
- ``XMLGYear``
- ``XMLGYearMonth``
- ``XMLGMonth``
- ``XMLGDay``
- ``XMLGMonthDay``
- ``XMLDuration``
- ``XMLTimezoneOffset``

### Validation

- ``XMLValidationPolicy``

### Namespaces

- <doc:Namespaces>
- ``XMLNamespace``
- ``XMLQualifiedName``
- ``XMLNamespaceResolver``
- ``XMLNamespaceValidator``

### Canonicalization

- <doc:Canonicalization>
- ``XMLCanonicalizer``
- ``XMLDefaultCanonicalizer``
- ``XMLTransform``

### XPath Queries

- <doc:XPath>

### Security

- <doc:Security>

### Swift Version Compatibility

- <doc:Compatibility>

### Test Support

- <doc:TestSupport>

### Errors

- ``XMLParsingError``
- ``XMLCanonicalizationError``
- ``XMLNamespaceResolutionError``
