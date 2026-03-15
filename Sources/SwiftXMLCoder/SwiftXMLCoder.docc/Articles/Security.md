# Security

Configure parser limits and parsing policies to protect against malicious XML input.

## Overview

SwiftXMLCoder parses XML using libxml2. Without limits, a hostile document can trigger excessive memory usage through deep nesting ("XML bomb"), enormous text nodes, or an unbounded number of elements. ``XMLTreeParser/Limits`` provides per-configuration caps that reject over-limit input with a stable error before the tree is materialised.

By default, network access and DTD loading are always disabled. Input size limits default to `nil` (unlimited), which is appropriate for trusted, internal XML. For any input that crosses a trust boundary, apply the built-in conservative presets or configure explicit limits.

## Untrusted Input Preset

Combine ``XMLDocument/ParsingConfiguration/untrusted()`` with ``XMLTreeParser/Limits/untrustedInputDefault()`` for full defence-in-depth:

```swift
import SwiftXMLCoder

let parser = XMLTreeParser(configuration: .init(
    parsingConfiguration: .untrusted(),
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

`untrusted()` enforces the most restrictive libxml2 parsing flags:

| Policy | Value |
| ------ | ----- |
| `externalResourceLoadingPolicy` | `.forbidNetwork` |
| `dtdLoadingPolicy` | `.forbid` |
| `entityDecodingPolicy` | `.preserveReferences` |

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

These defaults are enforced by ``XMLDocument/ParsingConfiguration`` and cannot be accidentally relaxed without an explicit opt-in. To allow DTD loading only when you trust and fully control the XML source:

```swift
// Only enable DTD loading if you trust and control the XML source
let parsingConfig = XMLDocument.ParsingConfiguration(dtdLoadingPolicy: .allow)
let parser = XMLTreeParser(configuration: .init(parsingConfiguration: parsingConfig))
```

## Error Handling

A limit violation throws ``XMLParsingError`` with the `.parseFailed` case. The error message contains a stable bracket-delimited diagnostic code for programmatic handling:

```swift
do {
    let tree = try parser.parse(data: input)
} catch XMLParsingError.parseFailed(let message) {
    // message contains a stable code, e.g. "[XML6_2H_MAX_DEPTH] ..."
    print("Input rejected:", message ?? "unknown")
} catch {
    print("Parse error:", error)
}
```

Stable error codes for limit violations:

| Code | Limit exceeded |
| ---- | -------------- |
| `[XML6_2H_MAX_INPUT_BYTES]` | `maxInputBytes` |
| `[XML6_2H_MAX_DEPTH]` | `maxDepth` |
| `[XML6_2H_MAX_NODE_COUNT]` | `maxNodeCount` |
| `[XML6_2H_MAX_ATTRIBUTES_PER_ELEMENT]` | `maxAttributesPerElement` |
| `[XML6_2H_MAX_TEXT_NODE_BYTES]` | `maxTextNodeBytes` |
| `[XML6_2H_MAX_CDATA_BYTES]` | `maxCDATABlockBytes` |
