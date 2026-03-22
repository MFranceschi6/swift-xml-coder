# Streaming XML

Parse and serialise XML without materialising the full document tree.

## Overview

SwiftXMLCoder provides two event-driven types for working with XML as a stream of discrete events rather than a DOM tree:

- ``XMLStreamParser`` — reads XML data and emits ``XMLStreamEvent`` values in document order (SAX-style, push model)
- ``XMLStreamWriter`` — accepts a sequence of ``XMLStreamEvent`` values and serialises them to UTF-8 `Data`

Both types are `Sendable` and work on all Swift versions. Async APIs are available on macOS 12+, iOS 15+, watchOS 8+, and tvOS 15+.

### Push Model vs Pull/Cursor

``XMLStreamParser`` uses a **push-based** model: the parser drives execution, calling your handler (or yielding to your `for await` loop) for each event in document order. The caller does not control the pace.

``XMLEventCursor`` provides a **pull-based** interface: you advance the cursor explicitly by calling ``XMLEventCursor/next()`` or ``XMLEventCursor/advance(toElement:)``; events are returned on demand. ``XMLItemDecoder`` builds on top of the cursor to decode `Codable` items one at a time from a named repeating element.

> Note: All three APIs — callback, `AsyncSequence`, and cursor — parse the full byte sequence before returning control. ``XMLEventCursor`` pre-buffers all events on creation; the memory advantage over ``XMLTreeParser`` is that events are smaller than the full DOM tree, not that events are produced lazily from a socket or file handle. For very large documents (hundreds of MB), the push callback API remains the most memory-efficient option.

## XMLStreamEvent

``XMLStreamEvent`` is an enum with eight cases that cover the complete XML event set:

| Case | Description |
| ---- | ----------- |
| `.startDocument(version:encoding:standalone:)` | XML declaration at the top of the document |
| `.endDocument` | End of the document |
| `.startElement(name:attributes:namespaceDeclarations:)` | Opening element tag |
| `.endElement(name:)` | Closing element tag |
| `.text(_:)` | Text content between tags |
| `.cdata(_:)` | CDATA section |
| `.comment(_:)` | XML comment |
| `.processingInstruction(target:data:)` | Processing instruction |

Events are always emitted in document order: `.startDocument` first, `.endDocument` last, with element and content events interleaved.

## Parsing

### Callback API (all Swift versions)

``XMLStreamParser/parse(data:onEvent:)`` is synchronous and works on all supported Swift versions. The closure is called in document order from the calling thread:

```swift
let parser = XMLStreamParser()
try parser.parse(data: xmlData) { event in
    switch event {
    case .startElement(let name, _, _):
        print("Element: \(name.localName)")
    case .text(let content):
        print("Text: \(content)")
    default:
        break
    }
}
```

### AsyncSequence API (macOS 12+, iOS 15+)

``XMLStreamParser/events(for:)`` returns an `AsyncThrowingStream` you can iterate with `for try await`:

```swift
let parser = XMLStreamParser()
for try await event in parser.events(for: xmlData) {
    if case .startElement(let name, let attrs, _) = event {
        let id = attrs.first { $0.name.localName == "id" }?.value
        print("\(name.localName) id=\(id ?? "none")")
    }
}
```

Task cancellation is checked before each yield. If the task is cancelled, the stream terminates cleanly without throwing.

### Parser Configuration

``XMLStreamParser`` reuses ``XMLTreeParser/Configuration``, so whitespace policy, security limits, and logger are fully shared with ``XMLTreeParser``:

```swift
let config = XMLTreeParser.Configuration(
    whitespaceTextNodePolicy: .omitWhitespaceOnly,
    limits: .untrustedInputDefault()
)
let parser = XMLStreamParser(configuration: config)
```

For untrusted input, use ``XMLTreeParser/Configuration/untrustedInputProfile(whitespaceTextNodePolicy:logger:)`` to apply conservative security limits automatically.

## Serialising

### Sync API (all Swift versions)

``XMLStreamWriter/write(_:)`` accepts any `Sequence<XMLStreamEvent>`:

```swift
var events: [XMLStreamEvent] = []
try XMLStreamParser().parse(data: inputData) { events.append($0) }
let output: Data = try XMLStreamWriter().write(events)
```

### Async API (macOS 12+, iOS 15+)

``XMLStreamWriter`` also accepts any `AsyncSequence<XMLStreamEvent>`:

```swift
let output = try await XMLStreamWriter().write(XMLStreamParser().events(for: inputData))
```

This is the symmetric round-trip pattern: the parser and writer are chained directly without buffering the event array.

### Writer Configuration

``XMLStreamWriter/Configuration`` controls encoding, formatting, and output limits:

```swift
let config = XMLStreamWriter.Configuration(
    encoding: "UTF-8",
    prettyPrinted: true,
    expandEmptyElements: false,
    limits: .untrustedOutputDefault()
)
let writer = XMLStreamWriter(configuration: config)
```

- `prettyPrinted: true` emits indented, human-readable output (2-space indent).
- `expandEmptyElements: true` forces `<tag></tag>` instead of `<tag/>`.
- ``XMLStreamWriter/WriterLimits/untrustedOutputDefault()`` applies conservative caps on depth, node count, and output size.

## Selective Extraction

A common reason to prefer streaming over tree-loading is **selective extraction**: reading only the fields you need from a large document without constructing the full DOM.

The pattern uses a depth counter to track element nesting and a flag to know when you are inside the target element:

```swift
struct PriceEntry: Sendable {
    let sku: String
    let price: Double
}

func extractPrices(from xmlData: Data) throws -> [PriceEntry] {
    var results: [PriceEntry] = []
    var depth = 0
    var insideItem = false
    var currentSKU = ""
    var currentPrice = 0.0

    try XMLStreamParser().parse(data: xmlData) { event in
        switch event {
        case .startElement(let name, let attrs, _):
            depth += 1
            if name.localName == "item" {
                insideItem = true
                currentSKU = attrs.first { $0.name.localName == "sku" }?.value ?? ""
            } else if insideItem && name.localName == "price" {
                // content follows in the next .text event
            }

        case .text(let value) where insideItem:
            currentPrice = Double(value.trimmingCharacters(in: .whitespaces)) ?? 0

        case .endElement(let name):
            depth -= 1
            if name.localName == "item" {
                results.append(PriceEntry(sku: currentSKU, price: currentPrice))
                insideItem = false
            }

        default:
            break
        }
    }
    return results
}
```

This approach keeps peak memory proportional to the number of matched items, not to the size of the document.

## Pull Cursor

``XMLEventCursor`` provides a pull-style interface for consuming events one at a time:

```swift
let cursor = try XMLEventCursor(data: xmlData)
while let event = cursor.next() {
    if case .startElement(let name, _, _) = event {
        print(name.localName)
    }
}
```

Use ``XMLEventCursor/advance(toElement:)`` to skip ahead to a named element without writing a manual depth-tracking loop:

```swift
let cursor = try XMLEventCursor(data: xmlData)
while cursor.advance(toElement: "Product") != nil {
    // cursor is now positioned right after <Product> — read child events until </Product>
}
```

## Item-by-Item Codable Decode

``XMLItemDecoder`` connects the cursor API with `Codable`: it finds each occurrence of a named element, serialises its events as a self-contained XML fragment, and decodes it using ``XMLDecoder``. Only one item's events are in a temporary buffer at a time.

```swift
struct Product: Decodable {
    let sku: String
    let price: Double
}

let cursor = try XMLEventCursor(data: catalogData)
let products = try XMLItemDecoder().decode(Product.self, itemElement: "Product", from: cursor)
```

For backpressure-aware processing on macOS 12+ / iOS 15+, use the async stream overload. The next item is not decoded until the consumer requests it:

```swift
let cursor = try XMLEventCursor(data: catalogData)
for try await product in XMLItemDecoder().items(Product.self, itemElement: "Product", from: cursor) {
    await persist(product)
}
```

Pass a ``XMLDecoder/Configuration`` to ``XMLItemDecoder/init(configuration:)`` to forward date strategies, key transforms, field overrides, and other decoder settings to each item decode call.

## When to Use Streaming vs. Tree

| Scenario | Recommended API |
| -------- | --------------- |
| Extracting a subset of fields from a large document | ``XMLStreamParser`` (selective extraction) |
| Transforming or filtering an XML document without full load | ``XMLStreamParser`` + ``XMLStreamWriter`` |
| Building or querying a document structure in memory | ``XMLTreeParser`` / ``XMLDocument`` |
| Encoding/decoding `Codable` types | ``XMLEncoder`` / ``XMLDecoder`` |
| Forward-only cursor reads without a closure | ``XMLEventCursor`` |
| Decoding a repeating element one item at a time | ``XMLItemDecoder`` |

> Tip: If you need to decode a `Codable` type from a specific child element within a large document, use ``XMLItemDecoder`` to locate and decode just that element without constructing the full DOM.

## Topics

### Event Type

- ``XMLStreamEvent``

### Parser

- ``XMLStreamParser``

### Writer

- ``XMLStreamWriter``
- ``XMLStreamWriter/Configuration``
- ``XMLStreamWriter/WriterLimits``

### Cursor

- ``XMLEventCursor``

### Item-by-Item Decoder

- ``XMLItemDecoder``
