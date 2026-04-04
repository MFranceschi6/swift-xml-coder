# Swift Version Compatibility

SwiftXMLCoder supports five Swift compatibility lanes with a single source tree.

## Compatibility Matrix

| Swift version | Manifest | Features available |
|---------------|----------|--------------------|
| 5.4 | `Package.swift` | Stub only — tooling discovery |
| 5.6+ | `Package@swift-5.6.swift` | Core encoder/decoder, XPath, namespaces, canonicalization |
| 5.9+ | `Package@swift-5.9.swift` | Adds `@XMLCodable`, `@XMLAttribute`, `@XMLChild` macros |
| 5.10 | (uses 5.9 manifest) | Same as 5.9 |
| 6.0+ | `Package@swift-6.0.swift` | Adds `~Copyable` ownership wrappers for libxml2 pointers; Swift 6 language mode |
| 6.1 | `Package@swift-6.1.swift` | Latest — same as 6.0 |

## Minimum Deployment Targets

- **macOS**: 10.15 (Catalina)
- **iOS**: 15.0
- **tvOS**: 15.0
- **watchOS**: 8.0
- **Linux**: Ubuntu 20.04+ (libxml2-dev required)

iOS, tvOS, and watchOS are supported via Track 1: libxml2 is a system library embedded in every Xcode SDK sysroot. No additional configuration is needed — `pkgConfig` resolution silently no-ops on Apple device/simulator SDKs, and the `link "xml2"` directive in the module map handles linking. All existing API is available on all Apple platforms.

> **Note:** CI runs a build-only gate for iOS Simulator (`arm64-apple-ios15.0-simulator`). Test execution on Simulator is not run in CI due to runner boot time constraints; the macOS test suite provides full coverage of the shared code path.

## libxml2 Baseline

SwiftXMLCoder links against the platform-provided `libxml2`:

- On Apple platforms, this is the `xml2` library bundled in the active Xcode SDK or system runtime.
- On Linux, this is the distribution package provided via `libxml2-dev`.

This matters for streaming APIs because the upstream libxml2 fix for the push-parser
`"huge input lookup"` error landed in `2.11.3`. Several environments within SwiftXMLCoder's
supported matrix still commonly ship older `2.9.x` builds, including Apple SDKs and long-term
support Linux distributions.

For that reason, SwiftXMLCoder keeps the SAX streaming path compatibility-first by default:

- ``XMLStreamParser`` feeds large inputs to libxml2 incrementally instead of as a single monolithic chunk.
- ``XMLItemDecoder`` inherits the same behavior because it builds on top of ``XMLStreamParser``.

No configuration is required from the caller. The workaround is an internal implementation detail chosen to preserve correctness across the supported platform matrix.

## Feature Availability by Lane

### Core features (Swift 5.6+)

- `XMLEncoder` / `XMLDecoder`
- `XMLDocument` with XPath
- `XMLTreeParser` / `XMLTreeWriter`
- `XMLStreamParser` / `XMLStreamWriter` / `XMLStreamEvent` — SAX-style push streaming (async APIs on macOS 12+ / iOS 15+)
- `XMLItemDecoder` — item-by-item streaming `Codable` decode from a named repeating element (async on macOS 12+ / iOS 15+)
- `XMLNamespaceResolver`, `XMLNamespaceValidator`
- `XMLFieldNamespaceProvider` — per-field namespace override for encoder/decoder
- `XMLCanonicalizer`, `XMLDefaultCanonicalizer`, `XMLTransform`
- `XMLAttribute<Value>` / `XMLChild<Value>` property wrappers
- `XMLFieldCodingOverrides`, `XMLFieldCodingOverrideProvider`
- `XMLParsingError` with `decodeFailed(codingPath:location:message:)` case
- `XMLSourceLocation` — structured source position (line) attached to decode errors
- `SwiftXMLCoderTestSupport`

### Macros (Swift 5.9+)

- `@XMLCodable` extension macro
- `@XMLAttribute` peer macro
- `@XMLChild` peer macro
- `@XMLFieldNamespace` peer macro — per-field namespace override

Available via the `SwiftXMLCoderMacros` product:

```swift
.product(name: "SwiftXMLCoderMacros", package: "swift-xml-coder")
```

### Ownership semantics (Swift 6.0+)

The `SwiftXMLCoderOwnership6` internal module provides `~Copyable` wrappers (`OwnedXMLCharPointer`, `OwnedXPathContextPointer`, `OwnedXPathObjectPointer`) that enforce correct libxml2 pointer lifecycle at compile time. These are implementation details — the public API is unchanged.

## Conditional Compilation

If your package supports multiple Swift versions alongside SwiftXMLCoder, use `#if swift(>=5.9)` to guard macro imports:

```swift
#if swift(>=5.9)
import SwiftXMLCoderMacros
#endif
```
