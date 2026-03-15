# Getting Started

Add SwiftXMLCoder to your project and encode or decode your first XML document.

## Installation

Add SwiftXMLCoder to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MFranceschi6/swift-xml-coder.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftXMLCoder", package: "swift-xml-coder")
        ]
    )
]
```

Swift 5.9 or later is required for macro support (`@XMLCodable`, `@XMLAttribute`, `@XMLChild`). Swift 5.6+ is sufficient for the core encoder/decoder.

## Encoding

Conform your type to `Codable` and call ``XMLEncoder/encode(_:)``:

```swift
import SwiftXMLCoder

struct Person: Codable {
    var name: String
    var age: Int
}

let person = Person(name: "Alice", age: 30)
let encoder = XMLEncoder()
let data = try encoder.encode(person)
// <Person><name>Alice</name><age>30</age></Person>
```

The root element name defaults to the type name. Override it via the encoder configuration:

```swift
let encoder = XMLEncoder(configuration: .init(rootElementName: "person"))
// <person><name>Alice</name><age>30</age></person>
```

## Decoding

Call ``XMLDecoder/decode(_:from:)`` with the XML `Data` and target type:

```swift
let xml = Data("<Person><name>Alice</name><age>30</age></Person>".utf8)
let decoder = XMLDecoder()
let person = try decoder.decode(Person.self, from: xml)
```

## Encode/Decode Roundtrip

Both `XMLEncoder` and `XMLDecoder` operate on `XMLTreeDocument` internally. You can access the intermediate tree:

```swift
let tree = try encoder.encodeTree(person)
// Inspect or transform tree here
let data = try encoder.encode(person)
```

## Next Steps

- <doc:FieldMapping> — control which fields become attributes vs. elements
- <doc:Namespaces> — add XML namespace declarations
- <doc:Security> — configure parser limits for untrusted input
