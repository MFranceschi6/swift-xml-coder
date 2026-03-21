# Changelog

All notable changes to SwiftXMLCoder will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added (Pillar I.5 — Benchmark Regression CI)

- **`.github/workflows/benchmarks.yml`** — new CI workflow that runs on every PR to `main`.
  Executes `swift package benchmark baseline check i2-baseline` and posts a markdown
  comparison table to the job step summary. Regressions emit a `::warning::` annotation
  on the PR but do **not** block merging (`continue-on-error: true`). Results are uploaded
  as a GitHub Actions artifact (30-day retention, keyed by commit SHA).

## [1.1.0] — 2026-03-21

### Added (Pillar VII.5 — Source Position Diagnostics)

- **`XMLNodeStructuralMetadata.sourceLine`** — new optional `Int` property that carries the
  source line number of an XML element's opening tag as reported by libxml2's `xmlGetLineNo`.
  `nil` for programmatically constructed elements.
- **Decode error messages now include source position** — `[XML6_5_KEY_NOT_FOUND]`,
  `[XML6_5_SCALAR_PARSE_FAILED]`, and `[XML6_6_ATTRIBUTE_NOT_FOUND]` errors append
  `(line N)` when the relevant element carries source line information, making it easier
  to locate the offending node in the original XML document.

### Added (Pillar IV.4 — Community Infrastructure)

- **`CONTRIBUTING.md`** — contributor guide covering requirements, branch naming (`feature/<slug>` /
  `fix/<slug>`), coding standards, testing commands, gitmoji commit style, PR guidelines (squash
  merge), bug reporting (7-day response target), and feature request process.
- **`SECURITY.md`** — responsible disclosure policy with contact email, response SLAs (72 h ack,
  14/30-day patch targets), supported versions table, and in-scope/out-of-scope definitions.
- **`CODE_OF_CONDUCT.md`** — adopts the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/)
  via external link so it tracks upstream updates automatically.
- **`.github/ISSUE_TEMPLATE/bug_report.md`** — bug report template (environment, expected vs
  actual, minimal reproducible example, XML snippet).
- **`.github/ISSUE_TEMPLATE/feature_request.md`** — feature request template (use case, proposed
  API sketch, alternatives considered).
- **`.github/pull_request_template.md`** — PR checklist (tests, CHANGELOG, build/test/lint gates,
  gitmoji title for squash-merge commit).

### Added (Pillar VII — Macros: @XMLText, @XMLIgnore, @XMLRootNamespace)

- **`XMLFieldNodeKind.textContent`** — new case that routes a Codable field to the text content
  of the parent XML element (rather than a child element). Enables the `<price currency="USD">9.99</price>`
  pattern where attributes and a scalar value coexist on the same element.
- **`XMLTextContent<Value>` property wrapper** — mechanism A (highest precedence) conformance to
  `.textContent` node kind. Mirrors the existing `XMLAttribute<Value>` pattern.
- **`@XMLText` macro** — peer macro detected by `@XMLCodable`; synthesises `.textContent` into
  `xmlFieldNodeKinds`. Requires a scalar `Codable` type on the annotated property.
- **`XMLFieldNodeKind.ignored`** — new case that silently skips a field during encode and treats it
  as absent during decode (so `Optional` fields decode as `nil`; non-optional fields with a default
  value are unaffected by XML round-trips).
- **`@XMLIgnore` macro** — peer macro detected by `@XMLCodable`; synthesises `.ignored` into
  `xmlFieldNodeKinds`. Fields must be `Optional` or have a default value to avoid decode errors.
- **`@XMLRootNamespace(uri:)` macro** — extension macro that generates an `XMLRootNode` conformance
  supplying `xmlRootElementName` (type name as default) and `xmlRootElementNamespaceURI` on the
  annotated struct or class.

### Changed (Pillar I.3 — Allocation Optimisations)

- **Key-name transform cache** — `_XMLKeyedEncodingContainer` and `_XMLKeyedDecodingContainer`
  now cache the result of `keyTransformStrategy.transform(_:)` in a per-session
  `_XMLKeyNameCache` (a `final class` whose reference is shared across all nested encoder/decoder
  instances). Fast paths for `.useDefaultKeys` (identity, no cache) and `.custom` (stateful
  closures, no cache). After the first item in an array, all subsequent items resolve key names
  from the in-memory dictionary at O(1) cost.
- **`firstChild(named:in:)` direct scan** — replaces `childElements(of:).first(where:)`: no
  longer materialises an intermediate `[XMLTreeElement]` array for each per-field lookup.
- **`lexicalText(of:)` accumulate-in-place** — replaces `compactMap + joined`: accumulates text
  and CDATA content directly into a single optional `String`, allocating at most one string for
  the common single-text-node case.
- **`isNilElement(_:)` direct scan** — replaces `childElements(of:).isEmpty` check: iterates
  `element.children` once without building an intermediate array.

**Measured improvement vs `i2-baseline` (debug build, Apple M1, macOS 25.3, 2026-03-20):**

| Metric                        | Before  | After   | Delta     |
|:------------------------------|--------:|--------:|----------:|
| Decode/10KB wall clock        | 721 µs  | 554 µs  | **-23%**  |
| Decode/10KB mallocs           | 5,387   | 3,890   | **-28%**  |
| Decode/10KB instructions      | 9,282 K | 7,373 K | **-21%**  |
| Decode/1MB wall clock         | 70 ms   | 55 ms   | **-21%**  |
| Decode/1MB mallocs            | 534 K   | 384 K   | **-28%**  |
| Encode/10KB/snakeCase clock   | 1,174 µs| 889 µs  | **-24%**  |
| Encode/10KB/snakeCase vs plain| +40%    | +1.6%   | **≈ 0**   |
| Parse (all sizes)             | —       | —       | unchanged |
| Encode plain (all sizes)      | —       | —       | unchanged |

### Added (Pillar I.2 — Baseline Profiling)

- **Full-metrics baseline** for all four core operations at four fixture sizes (1 KB – 1 MB),
  covering wall-clock, CPU time, instructions, malloc count, and peak resident memory.
  Detailed analysis saved to `.claude/benchmarks/baseline-i2.md`.
- **Named baseline `i2-baseline`** stored in `Benchmarks/.benchmarkBaselines/` via
  `swift package --allow-writing-to-package-directory benchmark baseline update i2-baseline`.
  Future PRs can compare against this baseline with `benchmark baseline compare i2-baseline`.

**Key findings — top-5 hotspots identified:**

1. **Encoder allocation cascade** — 116 mallocs/item at 10 KB (vs 37 for parse); ~19
   allocations per XML element. Root cause: per-element `[_XMLTreeContentBox]` array
   reallocations and per-value `String` boxing in `_XMLTreeElementBox.makeElement()`.
2. **Decoder overhead over parse** — +53 mallocs/item, +6 M instructions/10 KB. Root cause:
   `keysForElement(_:)` builds a `[String]` array on every container init; per-field String
   extraction in `XMLKeyedDecodingContainer`.
3. **Snake-case key transform CPU** — +40% wall clock, +27% instructions, zero extra mallocs.
   `convertToSnakeCase` runs uncached on every field of every encoded item. A small result
   cache would reduce the overhead to near-zero after the first item.
4. **Canonicalize allocation overhead** — 7,293 mallocs/iteration vs 6,988 for encode,
   despite operating on a pre-parsed tree. Temporary `String` objects for namespace prefix
   resolution and attribute sorting are the likely cause.
5. **libxml2 tree materialization** — 37 mallocs/item during parse; ~6 Swift heap objects
   per XML element to bridge the libxml2→Swift boundary. `Substring` / pre-sized children
   arrays could reduce this.

### Added (Pillar I.1 — Benchmark Infrastructure)

- **Benchmark sub-package** at `Benchmarks/` using `ordo-one/package-benchmark` 1.31.0.
  - Separate `Benchmarks/Package.swift` (macOS 13.0+ minimum, recommended approach when main package supports older OS).
  - `swift package --disable-sandbox benchmark` from the `Benchmarks/` directory runs all suites.
  - **4 benchmark suites** covering the core operations at 4 fixture sizes (1 KB, 10 KB, 100 KB, 1 MB):
    - `Parse/*` — raw `XMLTreeParser.parse(data:)` throughput
    - `Encode/*` — end-to-end `XMLEncoder.encode(_:)` (struct → XML `Data`)
    - `Decode/*` — end-to-end `XMLDecoder.decode(_:from:)` (XML `Data` → struct)
    - `Canonicalize/*` — `XMLDefaultCanonicalizer.canonicalView(for:options:transforms:)`
  - Additional `Encode/10KB/snakeCase` benchmark isolates key-transform overhead.
  - Additional `ParseOnly/10KB` benchmark allows parse vs. full-decode comparison.
  - Metrics: wall-clock time, CPU time, instructions, malloc count, peak resident memory.

**Baseline (release build, Apple M1, macOS 25.3, 2026-03-20):**

| Benchmark             | p50 wall-clock |
|-----------------------|----------------|
| Parse/1KB             | 35 µs          |
| Parse/10KB            | 231 µs         |
| Parse/100KB           | 2.33 ms        |
| Parse/1MB             | 23 ms          |
| Decode/1KB            | 103 µs         |
| Decode/10KB           | 729 µs         |
| Decode/100KB          | 7.34 ms        |
| Decode/1MB            | 71 ms          |
| Encode/1KB            | 123 µs         |
| Encode/10KB           | 854 µs         |
| Encode/10KB/snakeCase | 1.18 ms        |
| Encode/100KB          | 8.53 ms        |
| Encode/1MB            | 86 ms          |
| Canonicalize/1KB      | 107 µs         |
| Canonicalize/10KB     | 993 µs         |

Key observations:

- Decode overhead vs parse-only at 10 KB: 729 µs vs 231 µs — ~3× (Codable traversal dominates over libxml2 parse time).
- Snake-case key transform adds ~38% overhead at 10 KB (1.18 ms vs 854 µs) — string allocation on every field.
- All four operations scale roughly linearly with document size.

## [1.0.0] — 2026-03-16

### Added (Epic H — Pre-Release API Completeness)

- **H.1 — `userInfo` on `XMLEncoder` and `XMLDecoder`:** `XMLEncoder.Configuration` and `XMLDecoder.Configuration` now accept `userInfo: [CodingUserInfoKey: Any]` (default `[:]`). Both internal types `_XMLTreeEncoder` and `_XMLTreeDecoder` now return `options.userInfo` from their `Encoder`/`Decoder` protocol property, enabling context injection into custom `Encodable`/`Decodable` implementations. Both `Configuration` structs changed from `Sendable` to `@unchecked Sendable` (required by `[CodingUserInfoKey: Any]`; same approach as `Foundation.JSONEncoder`).
- **H.2a — `NilEncodingStrategy` fix for synthesised optionals:** `_XMLKeyedEncodingContainer` now overrides all 15 concrete `encodeIfPresent(_:forKey:)` overloads (Bool, String, Double, Float, Int, Int8, Int16, Int32, Int64, UInt, UInt8, UInt16, UInt32, UInt64, and generic `T`) plus the generic `encodeIfPresent<T: Encodable>`. Previously, Swift's synthesised `encode(to:)` bypassed `encodeNil(forKey:)` entirely by calling the concrete `encodeIfPresent` overloads, making `NilEncodingStrategy` ineffective for compiler-synthesised `Encodable` conformances. All overloads delegate to `_encodeIfPresent` which routes nil through `encodeNil(forKey:)`.
- **H.3 — `XMLKeyTransformStrategy`:** New `XMLKeyTransformStrategy` enum (`useDefaultKeys`, `convertToSnakeCase`, `convertToKebabCase`, `capitalized`, `uppercased`, `lowercased`, `custom(@Sendable (String) -> String)`). Added to `XMLEncoder.Configuration` and `XMLDecoder.Configuration` (default `.useDefaultKeys`). Encoder applies the transform to `key.stringValue` before creating child element/attribute names; decoder applies the same transform to `key.stringValue` before performing lookups in the tree (transform-then-match strategy — no inverse required). Attributes (`@XMLAttribute`) respect the same transform. New file `Sources/SwiftXMLCoder/XMLKeyTransformStrategy.swift`.
- **H.4a — `StringEncodingStrategy` (global CDATA):** New `XMLEncoder.StringEncodingStrategy` enum (`.text` default, `.cdata`) added to `XMLEncoder.Configuration`. When `.cdata`, all `String` values are wrapped in CDATA sections (`<![CDATA[...]]>`). `_XMLTreeElementBox` gains `appendCDATA(_:)` and a `.cdata(String)` case on `_XMLTreeContentBox`, mapped to `XMLTreeNode.cdata` in `makeElement()`. The decode path already handled CDATA transparently via `XMLTreeParser`.
- **H.4b — `@XMLCDATA` macro (per-field CDATA):** New `@XMLCDATA()` peer macro; `XMLStringCodingOverrideProvider` protocol; `XMLStringEncodingHint` enum (`.text`, `.cdata`). `@XMLCodable` now synthesises `XMLStringCodingOverrideProvider` conformance (`xmlPropertyStringHints`) when at least one property is annotated `@XMLCDATA`. The encoder resolves: per-property hint → global `stringEncodingStrategy` → `.text`. Attributes annotated with `@XMLCDATA` compile but the hint is silently ignored (CDATA is not valid in attributes). New files: `Sources/SwiftXMLCoder/XMLStringEncodingHint.swift`, `Sources/SwiftXMLCoderMacroImplementation/XMLCDATAMacro.swift`.
- **H.5 — Whitespace policy discoverability:** `XMLDecoder` gains a `public var whitespacePolicy: XMLTreeParser.WhitespaceTextNodePolicy` computed property as a convenience accessor for `configuration.parserConfiguration.whitespaceTextNodePolicy` (previously buried 2 levels deep).
- **H.6a — `expandEmptyElements` in `XMLTreeWriter`:** `XMLTreeWriter.Configuration` gains `expandEmptyElements: Bool` (default `false`). When `true`, child-less elements are emitted as `<tag></tag>` instead of `<tag/>` by injecting an empty text node before serialisation. Implemented without `XML_SAVE_NO_EMPTY` (a libxml2 global flag); instead, the writer injects an empty text node per element — libxml2 omits self-closing only when an element has at least one child.
- **H.6b — `@XMLExpandEmpty` macro (per-field expand-empty):** New `@XMLExpandEmpty()` peer macro; `XMLExpandEmptyProvider` protocol (`xmlPropertyExpandEmptyKeys: Set<String>`). `@XMLCodable` now synthesises `XMLExpandEmptyProvider` when at least one property is annotated `@XMLExpandEmpty`. The encoder injects an empty text node into the child element box after encoding, if the box has no content and the key is in `xmlPropertyExpandEmptyKeys`. The empty text node is dropped by the parser's default `whitespaceTextNodePolicy: .dropWhitespaceOnly`, so decoded values remain semantically unchanged. New files: `Sources/SwiftXMLCoder/XMLExpandEmptyProvider.swift`, `Sources/SwiftXMLCoderMacroImplementation/XMLExpandEmptyMacro.swift`.
- `@XMLCodable` macro declaration updated: `conformances` list now includes `XMLFieldCodingOverrideProvider`, `XMLDateCodingOverrideProvider`, `XMLStringCodingOverrideProvider`, `XMLExpandEmptyProvider`; `names` list now includes all four synthesised property names.
- 42 new tests: `XMLKeyTransformStrategyTests` (12), `XMLCDATAMacroIntegrationTests` (6), `XMLExpandEmptyMacroIntegrationTests` (5), `XMLEncoderTests` H.1 (2) / H.2a (2) / H.4a (4), `XMLDecoderTests` H.1 (2), `XMLTreeParserWriterTests` H.6a (4).

### Added
- `XMLValidationPolicy`: build-time and runtime configurable validation policy. Default is `.lenient` (no validation); `.strict` enables element-name and XSD temporal validation. Set at build time via `-DSWIFT_XML_CODER_STRICT_VALIDATION`; override per-instance via `XMLEncoder.Configuration.validationPolicy` / `XMLDecoder.Configuration.validationPolicy`.
- XSD temporal value types: `XMLGYear`, `XMLGYearMonth`, `XMLGMonth`, `XMLGDay`, `XMLGMonthDay`, `XMLTime`, `XMLDuration` — all `Sendable`, `Equatable`, `Hashable`, `Codable` (encode/decode as XSD lexical strings). Each type with a `Foundation.Date` bridge where meaningful.
- `XMLTimezoneOffset`: value type for XSD timezone offsets (`Z`, `±HH:MM`); `public static let utc`.
- `TimeZone.utc`: convenience public extension.
- `DateEncodingStrategy` new cases: `.xsdDate(timeZone:)`, `.xsdTime(timeZone:)`, `.xsdGYear(timeZone:)`, `.xsdGYearMonth(timeZone:)`, `.xsdGMonth(timeZone:)`, `.xsdGDay(timeZone:)`, `.xsdGMonthDay(timeZone:)` — encode `Foundation.Date` as each XSD partial-date form.
- `DateDecodingStrategy` new cases: `.xsdDate`, `.xsdTime`, `.xsdGYear`, `.xsdGYearMonth`, `.xsdGMonth`, `.xsdGDay`, `.xsdGMonthDay` — decode XSD partial-date lexical strings into `Foundation.Date`.
- `_XMLTemporalFoundationSupport.formatXSDDate(_:timeZone:)` and `parseXSDDate(_:)` helpers for `xs:date` ↔ `Foundation.Date` conversion.
- 61 new tests in `XMLTemporalTypesTests` covering parsing, roundtrip, invalid input, `Foundation.Date` bridges, and `XMLValidationPolicy` build-time/runtime behavior.
- `XMLDocument.ParsingConfiguration.untrusted()` static factory that explicitly enforces all libxml2 hardening flags (`.forbidNetwork`, DTD forbidden, entity references preserved, blank text nodes trimmed). Intended for use with `XMLTreeParser.Limits.untrustedInputDefault()` for full defence-in-depth against malicious XML input.
- 3 new tests in `XMLTreeHardeningTests` covering `untrusted()` policy assertions, rejection of a deeply-nested XML bomb, and rejection of an oversized text node.
- `XMLRootNameResolver.explicitRootElementName(from:validationPolicy:)` and `implicitRootElementName(for:validationPolicy:)` now accept a `validationPolicy` parameter. In `.strict` mode, a `rootElementName` or `XMLRootNode.xmlRootElementName` that requires sanitization fails with `[XML6_6_ROOT_NAME_INVALID]` instead of silently correcting.
- `_XMLEncoderOptions.init` now throws `[XML6_6_ITEM_NAME_INVALID]` in `.strict` mode when `itemElementName` requires sanitization. In `.lenient` mode (default) the name is still sanitized silently.
- 8 new tests in `XMLEncoderTests` (D.1 matrix): strict rejection of `rootElementName` with space, digit-prefix, invalid `XMLRootNode` name, and `itemElementName` with space; lenient sanitization pass for root and item names; valid-name no-throw assertions.
- `Tests/.swiftlint.yml`: raised `type_body_length` warning threshold to 600 lines for test files (test classes grow with coverage matrix).
- New test target `SwiftXMLCoderMacroTests` (Swift 5.9+ manifests): uses `SwiftSyntaxMacrosTestSupport.assertMacroExpansion` to verify macro diagnostic IDs and expansion output. Covers: `@XMLCodable` on `enum` → `XML8A_INVALID_DECL` error; `@XMLCodable` on `actor` → same error; `@XMLCodable` on struct/class → correct `xmlFieldNodeKinds` expansion; `@XMLAttribute`/`@XMLChild` as pure peer markers (no generated peers).
- `@XMLDateFormat(_ hint: XMLDateFormatHint)` macro (Swift 5.9+ only): per-property date format annotation for stored properties of type `Date` or `Date?`. Apply inside a type annotated with `@XMLCodable` to override the global `dateEncodingStrategy`/`dateDecodingStrategy` for that property.
- `XMLDateFormatHint` enum: `Sendable`, `Equatable`, `Hashable`, `Codable`. Covers all XSD date strategies: `.xsdDate`, `.xsdTime`, `.xsdDateTime`, `.xsdGYear`, `.xsdGYearMonth`, `.xsdGMonth`, `.xsdGDay`, `.xsdGMonthDay`, `.xsdDateWithTimezone(identifier:)`, `.xsdTimeWithTimezone(identifier:)`, `.secondsSince1970`, `.millisecondsSince1970`. Converts to `XMLEncoder.DateEncodingStrategy` and `XMLDecoder.DateDecodingStrategy` via `.encodingStrategy` and `.decodingStrategy` computed properties.
- `XMLDateCodingOverrideProvider` protocol: synthesised by `@XMLCodable` when any property is annotated with `@XMLDateFormat`. The static `xmlPropertyDateHints: [String: XMLDateFormatHint]` dictionary is consulted by encoder and decoder before the global strategy.
- `@XMLCodable` now synthesises a second extension (`XMLDateCodingOverrideProvider`) when at least one `@XMLDateFormat` annotation is present. The `xmlPropertyDateHints` dictionary maps property names to their hints verbatim.
- `XMLEncoder` and `XMLDecoder` now apply per-property date hints from `XMLDateCodingOverrideProvider` before the instance-level strategy, for both top-level types and all nested types.
- 14 new integration tests in `XMLDateFormatMacroIntegrationTests`: hint → strategy conversions, per-property encode override, per-property decode override, roundtrip, global fallback, Codable roundtrip for all `XMLDateFormatHint` cases.
- 4 new macro expansion tests in `XMLMacroDiagnosticsTests`: `@XMLDateFormat` as pure peer marker; `@XMLCodable` with `@XMLDateFormat` → `xmlPropertyDateHints` extension; mixed `@XMLAttribute`/`@XMLDateFormat`; complex parameterised hint passed verbatim.
- `XMLCapturingLogHandler` in `SwiftXMLCoderTestSupport`: thread-safe `LogHandler` implementation that captures all log entries for assertion in tests. Provides `entries`, `entries(at:)`, `entries(containing:)`, `hasEntry(at:containing:)`, `hasEntry(at:withMetadataKey:)`, and `reset()` helpers. Enables white-box verification that log messages are emitted at the correct levels with the correct metadata.
- `XMLEncoder.Configuration` and `XMLDecoder.Configuration` now accept a `logger: Logger` parameter (default `Logger(label: "SwiftXMLCoder")`). The logger is propagated through `_XMLEncoderOptions` and `_XMLDecoderOptions` to all call sites.
- `XMLTreeParser.Configuration` now accepts a `logger: Logger` parameter; the logger is passed to `XMLDocument.init` for libxml2 diagnostics and used for structured parse-phase logging.
- `XMLEncoder` emits `.debug` at encode start (`type`, `rootElement`) and completion (`rootElement`, `childCount`). Emits `.warning` when `rootElementName` or `XMLRootNode.xmlRootElementName` is silently sanitized in lenient mode. Emits `.debug` when root element name is derived from type name.
- `XMLDecoder` emits `.debug` at decode start (`type`, `rootElement`) and completion (`rootElement`, `childCount`). Emits `.error` before throwing `XML6_5_ROOT_MISMATCH` (with `expected`, `found`, `type` metadata).
- `XMLTreeParser` emits `.debug` on parse start and completion (with `nodeCount`). Emits `.warning` when any limit is exceeded (with `code`, `context`, `actual`, `limit` metadata). Emits `.warning` once when node count or element depth first reaches 80% of the configured cap — subsequent nodes at the same level do not re-emit.
- Encoder and decoder emit `.trace` (not `.debug`) when a per-property date hint from `XMLDateCodingOverrideProvider` overrides the global strategy (with `field` and `hint` metadata).
- 20 new integration tests in `XMLStructuredLoggingTests` covering encoder/decoder/parser debug lifecycle entries with metadata assertions, root name sanitization warnings, root mismatch error log, per-property hint trace entries, limit exceeded/approaching warnings (including once-only guarantee), and `XMLCapturingLogHandler` helpers.

- iOS 15+, tvOS 15+, watchOS 8+ platform support (Epic G.1 — Track 1): libxml2 resolves via Xcode SDK sysroot; `pkgConfig` silently no-ops on device/simulator SDKs. No source changes required. CI adds `ios-simulator` build-only job (`arm64-apple-ios15.0-simulator`).
- `Platforms` badge and Requirements table in `README.md` updated to include iOS, tvOS, watchOS.
- DocC `Articles/Compatibility.md` documents new Apple platform targets and CI gate policy.

### Changed
- XML field-name validation (error code `XML6_6_FIELD_NAME_INVALID`) is now gated by `XMLValidationPolicy.validateElementNames`. Existing tests updated to use `validationPolicy: .strict` to preserve their intent. In lenient mode (default) invalid field names are silently passed through to libxml2.

### Breaking Changes
- Renamed `XMLElement<Value>` property wrapper to ``XMLChild<Value>``. The old name is retained as a `@available(*, deprecated, renamed: "XMLChild")` typealias for source compatibility.
- Renamed `@XMLElement` macro to `@XMLChild`. The old macro name is kept as a deprecated alias pointing to the same implementation (`XMLChildMacro`).
- Removed `preserveWhitespaceTextNodes: Bool` parameter from `XMLTreeParser.Configuration.init` and `Configuration.untrustedInputProfile`. Use `whitespaceTextNodePolicy: .preserve` instead.
- `XMLCanonicalizationError.code` now returns `XMLCanonicalizationErrorCode` instead of `String`. Update callers that compare `.code` to raw string literals to use the typed constant (e.g. `.code == .transformFailed`).

### Added
- `XMLNamespace` conforms to `Equatable` and `Hashable`.
- `XMLParsingError` conforms to `Equatable`. Two `.other` values are never equal (existential payload cannot be compared structurally — documented in the case's doc comment).
- `makeXMLSafeName` now strips namespace prefixes from qualified names (e.g. `"soap:Envelope"` → `"Envelope"` instead of `"soap_Envelope"`). Regression test added.
- Regression test `test_encodeTree_itemElementName_namespacePrefixed_stripsPrefix`.
- DocC catalog (`Sources/SwiftXMLCoder/SwiftXMLCoder.docc/`): landing page + 8 articles (GettingStarted, FieldMapping, Namespaces, Canonicalization, XPath, Security, Compatibility, TestSupport).
- `README.md`: installation instructions (all 3 SPM product variants), quick-start code examples, feature matrix, and links to DocC articles.
- Inline `///` doc comments on all previously undocumented public types and members: `XMLNode`, `XMLNamespaceDeclaration`, `XMLNormalizationOptions`, `XMLTemporalCoding` types (`XMLDateFormatterDescriptor`, `XMLDateCodingContext`, `XMLDateEncodingClosure`, `XMLDateDecodingClosure`), `XMLCanonicalizationErrorCode` (all static constants), `XMLNamespace`, `XMLQualifiedName`, `XMLTreeNode` (all cases), `XMLTreeAttribute`, `XMLCanonicalizationError`, `XMLCanonicalizationStage`, `XMLCanonicalView`, `XMLIdentityTransform`, `XMLDefaultCanonicalizer`, `XMLNamespaceResolver`, `XMLNamespaceValidator`, `XMLDocument` (`createElement`, `appendChild`, `serializedData`, XPath methods).
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): matrix build and test across Linux (Swift 5.6, 5.9, 5.10, 6.0, 6.1) and macOS 15 (Swift 6.1 / Xcode 16.2). Coverage report generated via `llvm-cov` and uploaded as artifact on pushes to `main`.
- GitHub Actions SwiftLint workflow (`.github/workflows/lint.yml`): runs `realm/SwiftLint@v0.57.1` with PR review annotations on every push and pull request to `main`.
- GitHub Actions DocC workflow (`.github/workflows/docc.yml`): builds documentation for the `SwiftXMLCoder` target on macOS; will enforce `--warnings-as-errors` once the DocC catalog is added in Epic B.
- `Tests/.swiftlint.yml`: nested SwiftLint config relaxing `identifier_name` (min 1) and `type_name` (min 1) for test files, and demoting `force_unwrapping` from error to warning in tests. Source code remains at full strictness.

## [0.1.0] — 2026-03-15

### Added
- Initial extraction of `SwiftXMLCoder` from `swift-soap`.
- `XMLEncoder` / `XMLDecoder`: Codable-compatible XML codec backed by libxml2.
- `XMLTreeDocument`, `XMLTreeElement`, `XMLTreeNode`, `XMLTreeAttribute`: immutable value-semantic tree model.
- `XMLTreeParser` / `XMLTreeWriter`: low-level parse and serialization.
- `XMLDocument` with XPath query support.
- `XMLCanonicalizer` protocol + `XMLDefaultCanonicalizer`: deterministic XML canonicalization (XML-DSig ready).
- `XMLTransform` pipeline: pre-canonicalization transform hooks.
- Three-tier field mapping: `XMLFieldCodingOverrides` (runtime), `XMLFieldCodingOverrideProvider` (compile-time), `@XMLAttribute`/`@XMLElement` property wrappers.
- `@XMLCodable`, `@XMLAttribute`, `@XMLElement` compiler macros (Swift 5.9+).
- Full namespace support: `XMLNamespace`, `XMLQualifiedName`, `XMLNamespaceResolver`.
- Parser security hardening: configurable depth, node, and text-size limits.
- `SwiftXMLCoderTestSupport`: spy encoders/decoders and canonicalizer contract probe.
- 243 tests covering encoding, decoding, canonicalization, XPath, namespaces, and scalar types.
- Multi-manifest compatibility: Swift 5.4 through 6.1.
