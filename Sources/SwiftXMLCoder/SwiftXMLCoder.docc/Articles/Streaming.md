# Streaming XML

Parse and serialise XML without materialising the full document tree.

## Overview

SwiftXMLCoder provides two event-driven types for working with XML as a stream of discrete events rather than a DOM tree:

- ``XMLStreamParser`` — reads XML data and emits ``XMLStreamEvent`` values in document order (SAX-style, push model)
- ``XMLStreamWriter`` — accepts a sequence of ``XMLStreamEvent`` values and serialises them to UTF-8 `Data`

Both types are `Sendable` and work on all Swift versions. Async APIs are available on macOS 12+, iOS 15+, watchOS 8+, and tvOS 15+.

### Push Model vs Pull/Cursor

The current streaming API is **push-based**: the parser drives execution, calling your handler (or yielding to your `for await` loop) for each event in document order. The caller does not control the pace.

A **pull/cursor API** — where the caller advances a cursor to request the next token, enabling selective forward-only reads without buffering — is planned for a future release and is not yet part of the public API. Use the callback or `AsyncSequence` APIs in the meantime; they are designed so selective extraction (see below) is already efficient.

> Note: The `AsyncSequence` API wraps the synchronous callback internally. Both process the full byte sequence before returning control; neither streams incrementally from a socket or file handle. Large documents are still loaded fully into the libxml2 DOM before events are emitted. For very large documents (hundreds of MB), the push API remains the most memory-efficient option in the current release.

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

## When to Use Streaming vs. Tree

| Scenario | Recommended API |
| -------- | --------------- |
| Extracting a subset of fields from a large document | ``XMLStreamParser`` (selective extraction) |
| Transforming or filtering an XML document without full load | ``XMLStreamParser`` + ``XMLStreamWriter`` |
| Building or querying a document structure in memory | ``XMLTreeParser`` / ``XMLDocument`` |
| Encoding/decoding `Codable` types | ``XMLEncoder`` / ``XMLDecoder`` |
| Forward-only cursor reads without a closure (future) | Pull/cursor API — planned, not yet available |

> Tip: If you need to decode a `Codable` type from a specific child element within a large document, extract that element's byte range first with ``XMLStreamParser``, then pass just those bytes to ``XMLDecoder``.

## Roadmap

The current push API covers event-driven parsing and serialisation. The following capabilities are planned but not yet available:

- **Pull/cursor API** — a forward-only cursor you advance explicitly (analogous to Java `StAXReader` or .NET `XmlReader`), enabling selective reads without a closure or async overhead.
- **Item-by-item `Codable` decode** — decode one item at a time from a collection in a large document, without buffering the entire sequence.

These are targeted at a future release. If your use case requires them today, the selective extraction pattern above is the recommended approach.

## Topics

### Event Type

- ``XMLStreamEvent``

### Parser

- ``XMLStreamParser``

### Writer

- ``XMLStreamWriter``
- ``XMLStreamWriter/Configuration``
- ``XMLStreamWriter/WriterLimits``
