# Field Mapping

Control whether each field is encoded as an XML element or an XML attribute.

## Overview

By default every field in a `Codable` type is encoded as a child element. SwiftXMLCoder provides three complementary mechanisms to change this, evaluated in priority order:

1. **Property wrappers** — `@XMLAttribute` / `@XMLChild` (all Swift versions)
2. **Macros** — `@XMLCodable` + `@XMLAttribute` / `@XMLChild` (Swift 5.9+, no boxing)
3. **Runtime overrides** — `XMLFieldCodingOverrides` passed via encoder/decoder configuration

## Property Wrappers

Wrap a field with ``XMLAttribute`` to encode it as an XML attribute, or ``XMLChild`` to keep the default element behaviour explicitly:

```swift
import SwiftXMLCoder

struct Product: Codable {
    @XMLAttribute var id: String
    var name: String
    var price: Double
}

let product = Product(id: "SKU-1", name: "Widget", price: 9.99)
let encoder = XMLEncoder()
let data = try encoder.encode(product)
// <Product id="SKU-1"><name>Widget</name><price>9.99</price></Product>
```

> Note: `@XMLAttribute` and `@XMLChild` box the value — the Swift property type becomes `XMLAttribute<String>`, not `String`. This is transparent at the `Codable` level, but affects pattern matching and direct property access.

## Macros (Swift 5.9+)

Import `SwiftXMLCoderMacros` and annotate the type with `@XMLCodable`. Then annotate individual properties with `@XMLAttribute` or `@XMLChild`. The macro keeps the field's Swift type unboxed:

```swift
import SwiftXMLCoder
import SwiftXMLCoderMacros

@XMLCodable
struct Product: Codable {
    @XMLAttribute var id: String    // stays String, not XMLAttribute<String>
    var name: String
    var price: Double
}
```

The `@XMLCodable` macro synthesises an `XMLFieldCodingOverrideProvider` conformance that the encoder/decoder consults automatically.

## Runtime Overrides

Use ``XMLFieldCodingOverrides`` when you cannot modify the model type — for example, when decoding a third-party type:

```swift
let overrides = XMLFieldCodingOverrides()
    .setting(path: [], key: "id", as: .attribute)

let decoder = XMLDecoder(configuration: .init(fieldCodingOverrides: overrides))
let product = try decoder.decode(Product.self, from: data)
```

The `path` parameter is the dotted coding-key path leading to the field. For top-level fields, pass `[]`; for nested fields, pass the parent key path as an array of strings.

## Per-Property Overrides (Swift 5.9+)

When using `@XMLCodable`, additional peer macros let you set per-property encoding behaviour without touching the encoder/decoder configuration.

### Date Format

`@XMLDateFormat` declares the XSD date strategy for a single `Date` or `Date?` property, overriding the global `dateEncodingStrategy`/`dateDecodingStrategy`:

```swift
@XMLCodable
struct Schedule: Codable {
    @XMLDateFormat(.xsdDate)     var startDate: Date   // encodes as "2024-03-15"
    @XMLDateFormat(.xsdDateTime) var createdAt: Date   // encodes as "2024-03-15T10:30:00Z"
    var updatedAt: Date                                 // uses encoder-level strategy
}
```

### CDATA Sections

`@XMLCDATA` marks a `String` or `String?` property to always be wrapped in a `<![CDATA[...]]>` section, regardless of the encoder's global `stringEncodingStrategy`:

```swift
@XMLCodable
struct Article: Codable {
    var title: String            // plain text element
    @XMLCDATA var body: String   // <body><![CDATA[...]]></body>
}
```

> Note: `@XMLCDATA` on an `@XMLAttribute`-annotated property has no effect — attributes cannot contain CDATA sections.

### Expand Empty Elements

`@XMLExpandEmpty` forces an element to always serialise in expanded form (`<field></field>`) instead of self-closing (`<field/>`), even when the element has no content. Useful for interoperability with XML processors that distinguish between the two forms:

```swift
@XMLCodable
struct Envelope: Codable {
    @XMLExpandEmpty var header: String?  // → <header></header>
    var body: String                      // → <body/> when empty (default)
}
```

The decoded value is semantically identical either way.

## Priority Chain

When encoding or decoding a field, the encoder/decoder evaluates:

1. Property wrapper (`XMLAttribute<Value>` or `XMLChild<Value>` Swift type)
2. `XMLFieldCodingOverrideProvider.xmlFieldNodeKinds` (synthesised by `@XMLCodable`)
3. `XMLFieldCodingOverrides` in configuration
4. Default: `.element`

The first match wins.
