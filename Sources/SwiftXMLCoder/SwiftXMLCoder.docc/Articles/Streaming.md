# Streaming XML

Parse and serialise XML without materialising the full document tree.

## Overview

SwiftXMLCoder provides two event-driven types for working with XML as a stream of discrete events rather than a DOM tree:

- ``XMLStreamParser`` — reads XML data and emits ``XMLStreamEvent`` values in document order (SAX-style, push model)
- ``XMLStreamWriter`` — accepts a sequence of ``XMLStreamEvent`` values and serialises them to UTF-8 `Data`

Both types are `Sendable` and work on all Swift versions. Async APIs are available on macOS 12+, iOS 15+, watchOS 8+, and tvOS 15+.

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

## When to Use Streaming vs. Tree

| Scenario | Recommended API |
| -------- | --------------- |
| Large documents where only a subset of data is needed | ``XMLStreamParser`` |
| Transforming or filtering an XML document without full load | ``XMLStreamParser`` + ``XMLStreamWriter`` |
| Building or querying a document structure in memory | ``XMLTreeParser`` / ``XMLDocument`` |
| Encoding/decoding `Codable` types | ``XMLEncoder`` / ``XMLDecoder`` |

## Topics

### Event Type

- ``XMLStreamEvent``

### Parser

- ``XMLStreamParser``

### Writer

- ``XMLStreamWriter``
- ``XMLStreamWriter/Configuration``
- ``XMLStreamWriter/WriterLimits``
