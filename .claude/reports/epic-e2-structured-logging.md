# Step Report — Epic E.2: Structured Logging Integration

**Date:** 2026-03-15
**Branch:** `claude/epic-d-quality-hardening` (continues epic-e work on same branch)
**Status:** ✅ Complete

---

## Scope

- **Task:** E.2 — Structured logging integration with `swift-log`: `Logger` injected per-instance via `Configuration` structs, log calls at meaningful lifecycle points with structured metadata, limit boundary warnings that fire exactly once.
- **Boundaries:** SwiftXMLCoder module + SwiftXMLCoderTestSupport only. No changes to Package manifests, CI, or external dependencies (`swift-log` was already a declared dependency).

---

## Public API Changes

### Added

- **`XMLCapturingLogHandler`** (`Sources/SwiftXMLCoderTestSupport/XMLCapturingLogHandler.swift`)
  - `public final class XMLCapturingLogHandler: LogHandler, @unchecked Sendable`
  - Thread-safe via `NSLock`. Captures every `log(level:message:metadata:source:file:function:line:)` call.
  - Query helpers: `entries`, `entries(at:)`, `entries(containing:)`, `hasEntry(at:containing:)`, `hasEntry(at:withMetadataKey:)`, `reset()`
  - `XMLLogEntry` struct: carries `level`, `message`, `metadata`, `label`, `file`, `function`, `line`

### Changed

- **`XMLEncoder.Configuration`** — added `public let logger: Logger` (default `Logger(label: "SwiftXMLCoder")`)
- **`XMLDecoder.Configuration`** — added `public let logger: Logger` (default `Logger(label: "SwiftXMLCoder")`)
- **`XMLTreeParser.Configuration`** — added `public let logger: Logger` (default `Logger(label: "SwiftXMLCoder")`); removed `Hashable` conformance (Logger is not Hashable)
- **`_XMLEncoderOptions`** — added `let logger: Logger`, populated from `configuration.logger`
- **`_XMLDecoderOptions`** — added `let logger: Logger`, populated from `configuration.logger`
- **`XMLTreeParser.ParseState`** — added `warnedNodeCountApproaching: Bool` and `warnedDepthApproaching: Bool` flags to suppress repeated "approaching limit" warnings

### Log Calls Added

| Location | Level | Message | Metadata |
|---|---|---|---|
| `XMLEncoder.encodeTreeImpl` | `.debug` | `"XML encode started"` | `type`, `rootElement` |
| `XMLEncoder.encodeTreeImpl` | `.debug` | `"XML encode completed"` | `rootElement`, `childCount` |
| `XMLEncoder.resolveRootElementName` | `.warning` | `"rootElementName sanitized"` | `original`, `sanitized` |
| `XMLEncoder.resolveRootElementName` | `.warning` | `"XMLRootNode.xmlRootElementName sanitized"` | `type`, `original`, `sanitized` |
| `XMLEncoder.resolveRootElementName` | `.debug` | `"Root element name derived from type name"` | `type`, `rootElement` |
| `XMLDecoder.decodeTreeImpl` | `.debug` | `"XML decode started"` | `type`, `rootElement` |
| `XMLDecoder.decodeTreeImpl` | `.debug` | `"XML decode completed"` | `rootElement`, `childCount` |
| `XMLDecoder.decodeTreeImpl` | `.error` | `"XML root element mismatch"` | `expected`, `found`, `type` |
| `XMLTreeParser+Logic.parseDocument` | `.debug` | `"XML parse started"` | — |
| `XMLTreeParser+Logic.parseDocument` | `.debug` | `"XML parse completed"` | `nodeCount` |
| `XMLTreeParser+Logic.ensureLimit` | `.warning` | `"XML parse limit exceeded"` | `code`, `context`, `actual`, `limit` |
| `XMLTreeParser+Logic.ensureDepth` | `.warning` | `"XML parse depth limit exceeded"` | `code`, `depth`, `limit` |
| `XMLTreeParser+Logic.ensureDepth` | `.warning` | `"XML parse depth approaching limit"` | `code`, `depth`, `limit` (once only) |
| `XMLTreeParser+Logic.incrementNodeCount` | `.warning` | `"XML parse node count approaching limit"` | `code`, `nodeCount`, `limit` (once only) |
| `_XMLTreeEncoder.boxedDate` | `.trace` | `"Per-property date hint applied"` | `field`, `hint` |
| `_XMLTreeDecoder.parseDate` | `.trace` | `"Per-property date hint applied"` | `field`, `hint` |

---

## Implementation Notes

### Design choices

**Why `Logger` in `Configuration` structs rather than a global?**
Allows test code to inject a `XMLCapturingLogHandler`-backed logger scoped to a single encoder/decoder/parser instance without global state mutations. This is the standard swift-log injection pattern and keeps components independently observable.

**Why no `Hashable` on `XMLTreeParser.Configuration` after adding `Logger`?**
`Logger` is not `Hashable` (its metadata dictionary contains values of type `Logger.MetadataValue` which is not `Hashable`). The `Hashable` conformance was removed from the configuration struct; it was not used in any public API or test assertion.

**"Approaching limit" warning fires exactly once per parse**
Naive implementations call `ensureLimit` for every node, which would emit the warning O(N) times on large documents. The fix tracks `warnedNodeCountApproaching` and `warnedDepthApproaching` booleans in `ParseState`. For limits checked once per document (e.g. `maxInputBytes`, `maxAttributesPerElement`, `maxTextNodeBytes`), the approaching warning is not emitted — only the exceeded warning fires. This keeps the warning signal/noise ratio high.

**`.trace` for per-property date hints, `.debug` for lifecycle**
Production code with an application-bootstrapped logger at `.debug` gets useful encode/decode lifecycle info without per-field noise. `.trace` is reserved for fine-grained field-level events. Both levels are no-ops by default until `LoggingSystem.bootstrap` is called.

**`component` metadata key via local `var logger` copy**
Set on a `var logger = configuration.logger` copy at the call-site to avoid mutating shared state. The metadata is correctly scoped to the current encode/decode/parse call.

**`childCount` in encode/decode completion**
Provides a rough structural measure of what was serialised/deserialised without walking the entire tree. For encode: `root.children.count` (direct children of the root element). For decode: `tree.root.children.count` (direct children of the parsed root). Not a deep node count, but enough to detect unexpected empty or single-child structures.

**Root name sanitization warning**
In lenient mode, `makeXMLSafeName` silently replaces invalid characters. The encoder now compares the resolved name against the configured/declared name and emits a `.warning` if they differ. This surfaces misconfigured `rootElementName` or `XMLRootNode.xmlRootElementName` values that would otherwise be invisible. Root mismatch in the decoder emits `.error` before throwing, giving log-consuming infrastructure a chance to react before the exception propagates.

### Two-phase logging for XMLDecoder

`XMLDecoder.Configuration.logger` is separate from `XMLTreeParser.Configuration.logger` (nested inside `parserConfiguration`). When a caller constructs `XMLDecoder` with a custom logger:

- **Decode-phase log calls** (decode start/completion, root mismatch, per-property hints) go to `configuration.logger`.
- **Parse-phase log calls** (parse start/completion, limit warnings) go to `parserConfiguration.logger`.

Both default to `Logger(label: "SwiftXMLCoder")`. A caller who wants all logs in one place should pass the same logger instance to both:

```swift
let logger = Logger(label: "MyApp")
let decoder = XMLDecoder(configuration: .init(
    parserConfiguration: .init(logger: logger),
    logger: logger
))
```

---

## Validation Evidence

- **Build:** `swift build -c debug` → `Build complete!` ✅
- **Tests:** `swift test --enable-code-coverage` → `371 tests, 0 failures` ✅
  - 20 new tests in `XMLStructuredLoggingTests`
- **Lint:** `swiftlint lint` → `187 violations, 0 serious` ✅ (all warnings; preexisting `line_length`/`cyclomatic_complexity` unchanged)

---

## Risks and Follow-ups

### Residual risks

- `XMLDecoder.Configuration.logger` and `parserConfiguration.logger` are independent. Documented in the step report and in the `Configuration.logger` property doc comment. No API change needed — this is the correct design for two-phase observability.

### Non-blocking follow-ups

- E-bis (round-trip-safe numeric codec) or F (documentation + DocC polish) is next in the plan.
- Consider adding `.trace` per-element traversal logging behind a `#if DEBUG` or compile-time flag for deep debugging if demand arises.