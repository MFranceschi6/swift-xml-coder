# Security

Configure parser limits to protect against malicious XML input.

## Overview

SwiftXMLCoder parses XML using libxml2. Without limits, a hostile document can trigger excessive memory usage through deep nesting ("XML bomb"), enormous text nodes, or an unbounded number of elements. ``XMLTreeParser/Limits`` provides per-configuration caps that reject over-limit input with a stable error before the tree is materialised.

By default all limits are `nil` (unlimited), appropriate for trusted, internal XML. For any input that crosses a trust boundary, apply the built-in conservative preset or configure explicit limits.

## Untrusted Input Preset

```swift
import SwiftXMLCoder

let parser = XMLTreeParser(configuration: .init(
    limits: .untrustedInputDefault()
))
let tree = try parser.parse(data: untrustedData)
```

`untrustedInputDefault()` applies these caps:

| Limit | Value |
|-------|-------|
| `maxInputBytes` | 16 MiB |
| `maxDepth` | 256 |
| `maxNodeCount` | 200,000 |
| `maxAttributesPerElement` | 256 |
| `maxTextNodeBytes` | 1 MiB |
| `maxCDATABlockBytes` | 4 MiB |

## Custom Limits

```swift
let strictLimits = XMLTreeParser.Limits(
    maxInputBytes: 1 * 1024 * 1024,   // 1 MiB
    maxDepth: 64,
    maxNodeCount: 10_000,
    maxAttributesPerElement: 32,
    maxTextNodeBytes: 64 * 1024,       // 64 KiB
    maxCDATABlockBytes: 256 * 1024     // 256 KiB
)

let parser = XMLTreeParser(configuration: .init(limits: strictLimits))
```

## External Resources and DTD

By default SwiftXMLCoder disables:

- **Network access** — external entity references that reference URLs are rejected
- **DTD loading** — no external DTD is fetched or processed

These defaults are enforced by `XMLDocument.ParsingConfiguration` and cannot be accidentally relaxed without an explicit opt-in:

```swift
// Only enable DTD loading if you trust and control the XML source
let parsingConfig = XMLDocument.ParsingConfiguration(loadDTD: true)
let parser = XMLTreeParser(configuration: .init(parsingConfiguration: parsingConfig))
```

## Error Handling

A limit violation throws ``XMLParsingError`` with the `.limitExceeded` case, which carries the specific limit that was hit:

```swift
do {
    let tree = try parser.parse(data: input)
} catch let error as XMLParsingError {
    switch error {
    case .limitExceeded(let reason):
        print("Input rejected:", reason)
    default:
        print("Parse error:", error)
    }
}
```
