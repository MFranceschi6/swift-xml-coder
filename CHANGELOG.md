# Changelog

All notable changes to SwiftXMLCoder will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- **`_LazyLineTable`** — line numbers are now captured lazily: the side table is populated
  only on first diagnostic access instead of being collected on every parse event. Eliminates
  one allocation and one `append` per event on the hot path when no error occurs.
- **`_XMLEventBuffer.startToEnd`** — new O(n) precomputed side table mapping every
  `.startElement` event index to its matching `.endElement` index. Enables O(1)
  `elementEndIndex(from:)`, O(1) `findRootElement()`, and subtree-skip (`index = childEnd + 1`)
  in `childElementSpans` and `lexicalText`, replacing repeated depth scans.
- **Sequential cursor (`childCursor`) in `_XMLSAXDecoder`** — keyed container decode
  now tries `childSpans[childCursor]` first before falling back to a linear scan. Because XML
  document order matches Codable declaration order in the common case, this makes the hot path
  O(1) amortised with zero additional allocation. Added `peekChildSpan` (non-consuming) for
  `contains`/`decodeNil` paths that must not advance the cursor.
- **`isNilSpan` fast-exit** — `_XMLEventBuffer.isNilSpan(from:to:)` now returns on the first
  child element or non-whitespace text node with no intermediate array allocation.
- **`parseSAX` made `public`** — `XMLStreamParser.parseSAX(data:handler:)` is now publicly
  accessible, enabling benchmark decomposition (parser-only throughput vs full decode cost).
- **Microbenchmark suite** — new `MicrobenchmarksBenchmarks.swift` and extended `Fixtures.swift`
  covering `SAXParseOnly/*` (libxml2 + event callbacks only), `KeyedDecode/Flat/*` (5 fields),
  `KeyedDecode/Wide/*` (20 fields, keyed-lookup density), and `KeyedDecode/Nested/*`
  (3-level nesting, child-span creation). Benchmark results in
  `Benchmarks/Results/2026-03-28-cursor-optimization.txt`.

- **`_XMLEventEncoder` — direct-to-events Codable encoder** — new `Encoder` implementation
  (`XMLEventEncoder+Codable.swift`) that emits `XMLStreamEvent` values into a shared
  `_XMLEventCollector` without constructing an intermediate `XMLTreeDocument`. Attribute
  deferral, optional nil strategies, CDATA, key transforms, `XMLRootNode`, per-property date
  and string hints, `@XMLAttribute`/`@XMLTextContent` property wrappers, and `nestedContainer`
  fallback via `_XMLTreeElementBox` sub-trees are all supported. `XMLEncoder.encode()` now
  routes through this path, bypassing tree construction entirely.
- **`XMLTreeElement.walkEvents(_:)`** — non-throwing helper that serialises a
  `_XMLTreeElementBox` sub-tree (nested/unkeyed fallback) to the event collector.
- **`_XMLScalarBoxer` protocol** — decouples `_XMLAttributeEncodableValue` and
  `_XMLTextContentEncodableValue` from `_XMLTreeEncoder`; both `_XMLTreeEncoder` and
  `_XMLEventEncoder` now conform, enabling the two encoders to share scalar-boxing logic
  without coupling.

- **`_XMLStreamingDecoder` — fully streaming SAX-to-Codable decoder** — new `Decoder`
  implementation (`XMLStreamingDecoder+Codable.swift`) that reads XML events directly from the
  libxml2 push parser session on demand, without buffering the entire document's events upfront.
  `XMLDecoder.decode(_:from:)` now routes through this path instead of `_XMLSAXDecoder`.
  - **Inline keyed child streaming**: in-order keyed property access reads children directly from
    the parser session — zero event copies on the happy path.
  - **Inline unkeyed child streaming**: after mode detection (items vs allChildren), subsequent
    children are consumed inline from the stream.
  - **Scalar leaf fast-path**: leaf elements (`<name>John</name>`) are decoded directly from the
    stream text without allocating `_XMLStreamingElementState` — zero heap allocation per scalar.
  - **Lazy line number resolution**: event indices are stored (one `Int` per element), and line
    numbers are resolved only on error via `_LazyLineTable` re-parse. No per-event
    `xmlSAX2GetLineNumber` call on the hot path.
  - **`ContiguousArray<XMLStreamEvent>` queue**: eliminated the `_XMLStreamingQueuedEvent` wrapper;
    events are stored directly without per-event struct overhead.
  - **Out-of-order fallback**: children accessed out of document order are buffered and decoded
    via the existing `_XMLSAXDecoder` path, preserving full Codable compatibility.
  - **Performance**: ~5% instruction count reduction and ~7-9% throughput improvement over the
    initial streaming decoder, narrowing the SAX→Tree decode gap to ~7-10%.

### Changed

- **`XMLStreamWriterSink`** — new internal incremental writer that accepts events one at a
  time and flushes serialised bytes to a callback when a configurable threshold is exceeded.
  Building block for all streaming pipeline improvements below.
- **`XMLTreeDocument.walkEvents(_:)`** — tree-to-events bridge that walks a tree document
  and emits `XMLStreamEvent` values in document order, enabling the event-based encode path.

### Changed

- **Encoder now routes through `_XMLEventEncoder`** — `XMLEncoder.encode()` no longer
  constructs an `XMLTreeDocument` as an intermediate step. Instead it accumulates events in
  `_XMLEventCollector` and serialises via `XMLStreamWriterSink`, eliminating all intermediate
  tree allocations on the hot path.
- **Streaming canonicalizer now writes incrementally** — the stream-based canonicalize path
  (`canonicalize(events:..., output:)`) feeds normalised events directly to
  `XMLStreamWriterSink` instead of accumulating all events before serialisation. The output
  callback now receives data chunks as they are produced.
- **`XMLStreamWriter` delegates to `XMLStreamWriterSink`** — `writeImpl` now creates a
  sink internally, removing duplicated libxml2 event-dispatch code.
- **`XMLItemDecoder` uses span-based decode** — item decoding now uses `nextItemSpan()` on
  the cursor to record index ranges and creates `ContiguousArray` slices from the cursor's
  backing buffer, reducing per-item copy overhead.

## [1.4.0] — 2026-03-27

### Added

- **`XMLEventTransform` protocol** — new event-level canonicalization transform hook for
  streaming pipelines. Supports per-event rewrite/filter via `process(_:)` and
  end-of-stream flush via `finalize()`.
- **CI coverage on Swift 6.1 lane** — `latest-linux` now collects code coverage and enforces
  the 90% threshold, covering `#if swift(>=6.0)` branches (typed throws, `~Copyable` ownership,
  `any Protocol` existentials) that the 5.10 lane cannot reach.
- **8 new macro tests** — peer macro expansion tests for `@XMLCDATA`, `@XMLExpandEmpty`,
  `@XMLFieldNamespace`; `XMLCodableMacro` tests for CDATA synthesis, expand-empty keys,
  field namespace (uri-only and prefix+uri variants), and computed property skip.
- **Streaming benchmarks** — SAX push, pull cursor, item-by-item decode, and stream writer
  benchmarks at scales from 10KB to 100MB.
- **Rich model benchmarks** — tree parse, decode, encode, SAX, and item-by-item decode
  with a 3-level nested model (attributes, namespaces, long text nodes).
- **Foundation comparison benchmarks** — `XMLParser` SAX and `XMLDocument` tree parse
  head-to-head with SwiftXMLCoder equivalents (10KB–100MB).
- **CoreOffice/XMLCoder comparison benchmarks** — separate `ComparisonBenchmarks` target
  comparing Codable decode/encode at 10KB–10MB. Weekly CI schedule + manual dispatch.
- **Enterprise-scale fixtures** — 10MB and 100MB pre-encoded XML data for stress testing
  streaming paths.
- **Performance section in README** — decision table (tree vs streaming), benchmark coverage
  overview, and instructions for running benchmarks.
- **Decode benchmark split (Tree vs SAX)** — internal suites now include
  `Decode/Tree/*` and `Decode/SAX/*` (including rich fixtures), and external comparison
  suites now report separate SwiftXMLCoder decode paths against Foundation/XMLCoder.
- **`_XMLSAXDecoder` — zero-tree Codable decode (XML-PERF-1)** — `XMLDecoder.decode(_:from:)`
  now drives Keyed/Unkeyed/SingleValue containers directly from `_XMLEventBuffer` without
  materializing an `XMLTreeDocument`. Eliminates the intermediate tree allocation on the
  standard decode path while preserving full API, diagnostics, and namespace/macro support.
- **12 SAX/tree parity tests** — `XMLSAXTreeParityTests` asserts that `decode(_:from:)` (SAX)
  and `decodeTree(_:from:)` (tree) produce identical results across: plain keyed structs,
  attribute+text-content mixed, nested structs, arrays, optional present/absent, ISO 8601
  dates, base64 data, namespaced fields, booleans, empty arrays, and rich multi-namespace
  invoice models.

### Changed

- **Canonicalizer API redesigned (BREAKING)** — `XMLCanonicalizer` now exposes
  `canonicalize(...)` tree and streaming entry points (data/events + output callback);
  `XMLDefaultCanonicalizer` now implements both paths and returns canonical `Data` directly.
- **`XMLNormalizationOptions` renamed to `XMLCanonicalizationOptions` (BREAKING)** —
  canonicalization options keep the same semantics while aligning naming with the new API.
- **Legacy canonicalization scaffolding removed (BREAKING)** — removed
  `XMLCanonicalView`, `XMLCanonicalizationContract`, `XMLCanonicalizationError*`,
  `XMLCanonicalizationStage`, `XMLIdentityTransform`, and `XMLCanonicalizer+Logic`.
- **Canonicalization tests/docs migrated** — `XMLCanonicalizerTests`, test-support harness,
  benchmark usage, and DocC canonicalization article updated to the new API and error model.
- **SAX parser internals now use libxml2 push parsing** — `XMLStreamParser` switched from
  `xmlSAXUserParseMemory` to `xmlCreatePushParserCtxt` + `xmlParseChunk`, aligning the
  implementation with the `XML-PERF-1` direction and enabling chunk-friendly internals.
- **Streaming SAX path now feeds large inputs incrementally by default** — `XMLStreamParser`
  resets libxml2's last error, applies the same parse options as the tree parser, and feeds
  large payloads to `xmlParseChunk` in 1 MiB blocks. This avoids the libxml2 push-parser
  `"huge input lookup"` failure seen on older platform-provided `libxml2` versions
  (fixed upstream in `2.11.3`) while keeping Apple SDKs and LTS Linux distributions working
  without requiring a system library upgrade.
- **`XMLDecoder.decode(_:from:)` now parses via SAX-to-tree bridge** — raw XML decode no
  longer goes through `XMLTreeParser`'s DOM-to-tree path; it now builds `XMLTreeDocument`
  directly from streaming events and then reuses the existing tree-based Codable decoder,
  preserving public API and diagnostics shape.
- **`XMLItemDecoder` now decodes item events directly** — per-item decode no longer
  serialises event slices back to XML bytes before decoding; it now builds a temporary
  tree in-memory from the extracted events and calls `decodeTree`, reducing extra parse/write
  work in item-by-item pipelines.
- **Scalar decode logic extracted to `_XMLScalarDecoder`** — `_XMLTreeDecoder` and
  wrapper decode paths (`XMLAttribute` / `XMLTextContent`) now delegate scalar lexical
  parsing to a shared internal component, preparing reuse for upcoming SAX container decode.
- **Lower-allocation SAX start-element path** — namespace declarations and attributes now
  reuse per-parse buffers (`removeAll(keepingCapacity: true)`) instead of allocating fresh
  arrays for each element callback.
- **Internal line-aware SAX emission hook** — `XMLStreamParser` now captures libxml2 line
  numbers (`xmlSAX2GetLineNumber`) for internal consumers, allowing decode diagnostics to
  retain source line information in the new SAX decode path.
- **`XMLQualifiedName` unchecked fast-path** — added an internal
  `init(uncheckedLocalName:namespaceURI:prefix:)` and used it in SAX callbacks to avoid
  redundant trimming of libxml2-provided names.
- **SAX limit checks now have a no-op fast path** — optional size/node/attribute limit
  checks are precomputed once per parse and skipped entirely when corresponding limits are
  disabled, reducing callback overhead on trusted/unbounded inputs.
- **Lower-allocation tree parse traversal** — `XMLTreeParser` now pre-sizes arrays for
  attributes, namespace declarations, and children based on libxml2 sibling/list counts
  before conversion to `XMLTreeElement`, reducing growth reallocations on large documents.
- **`_XMLTreeElementBox` now reserves child content capacity** — encoder mutable element boxes
  reserve an initial content capacity at creation (`estimatedContentCount`, default `4`) to
  reduce small-array growth churn during deeply nested or repetitive encodes.
- **`_XMLEventBuffer.childElementSpans` linearized** — span extraction no longer performs
  nested `elementEndIndex` rescans for each child; direct-child spans are now computed in a
  single pass with depth tracking.
- Disabled `nesting` SwiftLint rule globally (legitimate nested types in both sources and tests).
- Removed `force_unwrapping` from opt-in rules; replaced 25 force unwraps in tests with
  `XCTUnwrap`.
- Raised `file_length` warning threshold to 700 (tests are naturally longer).
- Fixed ~20 comma spacing violations in sources and tests.

## [1.3.0] — 2026-03-22

### Added (XML-R3 — Pull Cursor and Item-by-Item Decode)

- **`XMLEventCursor`** — new `final class` providing a forward-only, pull-style cursor over a
  pre-parsed sequence of ``XMLStreamEvent`` values. Created from `Data` using the existing SAX
  parser; all events are buffered on init. Exposes `next()`, `peek()`, `isAtEnd`, `count`,
  `position`, and `advance(toElement:)`. Conforms to `IteratorProtocol`. Documented as
  not thread-safe (single-caller use). `@unchecked Sendable` to allow capture in async closures.
- **`XMLItemDecoder`** — new `Sendable` struct that decodes `Decodable` items one at a time from
  a named repeating element using an `XMLEventCursor`. Internally extracts events for each item
  (handling nested same-name elements via depth tracking), serialises them as a self-contained XML
  fragment via `XMLStreamWriter`, and decodes with `XMLDecoder`. Exposes:
  - `decode(_:itemElement:from:) throws -> [T]` — synchronous; returns all items as an array.
  - `items(_:itemElement:from:) -> AsyncThrowingStream<T, Error>` — async; decodes one item at
    a time with natural backpressure (macOS 12+, iOS 15+). Task cancellation is checked before
    each yield.
  - Full decoder configuration forwarded (`dateDecodingStrategy`, `fieldCodingOverrides`,
    `keyTransformStrategy`, etc.); `rootElementName` is overridden per-call with `itemElement`.
  - Dual `#if swift(>=6.0) throws(XMLParsingError)` branch on `decode(_:itemElement:from:)`.
- **14 new tests** in `XMLEventCursorTests` covering: init/count, `next()`/`peek()` navigation,
  `isAtEnd`, `IteratorProtocol` while-loop, `advance(toElement:)` find/skip/not-found/repeated,
  `XMLItemDecoder` sync decode (3-item catalog, empty container, single item, cursor exhaustion),
  nested same-name element depth tracking, configuration forwarding (date strategy), async stream
  (yield-all, empty container), invalid XML throws, and `nextItemEvents` internal extraction.

### Changed (XML-R3 — Streaming Documentation)

- **`Articles/Streaming.md`** updated:
  - "Push Model vs Pull/Cursor" section rewritten — introduces `XMLEventCursor` and `XMLItemDecoder`
    as the pull-style counterparts to `XMLStreamParser`; clarifies the memory model (events buffered,
    smaller than full DOM tree). The old duplicate `> Note:` blocks merged into one.
  - New "Pull Cursor" section — usage example for `XMLEventCursor.next()` and `advance(toElement:)`.
  - New "Item-by-Item Codable Decode" section — sync and async `XMLItemDecoder` examples with
    configuration forwarding note.
  - "When to Use Streaming vs. Tree" table updated — replaces the "Forward-only cursor reads
    (future/planned)" row with concrete entries for `XMLEventCursor` and `XMLItemDecoder`.
  - "Roadmap" section removed (both planned items are now shipped).
  - Topics section extended with `XMLEventCursor` and `XMLItemDecoder` entries.
- **`SwiftXMLCoder.docc/SwiftXMLCoder.md`**: `XMLEventCursor` and `XMLItemDecoder` added to the
  "Streaming" topics section.

### Added (XSD-First Contract Coverage)

- **`GeneratedModelContractTests`** — new runtime contract suite exercising the shape of code emitted by `swift-xml-codegen`: `XMLRootNode`, `XMLFieldNamespaceProvider`, `@XMLAttribute`, `@XMLTextContent`, arrays, `Decimal`, `Date`, `Data`, and namespaced child fields in encode/decode round-trips.

### Changed (XML-R2 — Streaming Story)

- **`Articles/Streaming.md`** updated with:
  - "Push Model vs Pull/Cursor" section — explains the current push-only model, clarifies that
    `AsyncSequence` wraps the synchronous parser internally (no byte-by-byte streaming from
    sockets), and explicitly names pull/cursor as a planned future capability.
  - "Selective Extraction" section — depth-tracked pattern for extracting a subset of fields
    from a large document without materialising the full DOM, with a complete `PriceEntry`
    example.
  - Updated "When to Use Streaming vs. Tree" decision table — adds pull/cursor row (planned) and
    a Tip on combining ``XMLStreamParser`` with ``XMLDecoder`` for large-document `Codable` use.
  - "Roadmap" section — lists pull/cursor and item-by-item `Codable` decode as planned future
    capabilities so users know what to expect.

### Added (XML-R2 — Diagnostics)

- **`XMLSourceLocation`** — new `Sendable, Equatable` struct carrying optional `line`, `column`,
  and `byteOffset` fields. `line` is populated from libxml2 source tracking when a parse failure
  occurs on a real XML element; `column` and `byteOffset` are reserved for future SAX-level
  instrumentation and are currently always `nil`.
- **`XMLParsingError.decodeFailed(codingPath:location:message:)`** — new error case produced by
  the XML Codable layer for all field-level decode failures. Carries a `[String]` coding path
  (from root to the failing field, with array indices rendered as `[n]`), an optional
  `XMLSourceLocation`, and a stable `[CODE]`-prefixed message. Replaces `parseFailed` at all
  35 throw sites inside `XMLDecoder+Codable.swift`, making Codable decode errors structurally
  distinct from XML-level parse failures.
- **`_XMLTreeDecoder.decodeFailed(codingPath:element:message:)`** — internal helper that builds
  a `decodeFailed` error from a `[CodingKey]` path and an optional element (falls back to the
  decoder's current node for location). Convenience overload `decodeFailed(message:)` uses the
  decoder's own `codingPath` and `node`.
- **15 new tests** in `XMLDiagnosticsTests` covering `XMLSourceLocation` init/equatable,
  `decodeFailed` equatable variants, missing-key coding path content, bad-scalar error code,
  source location propagation, nested coding path, bad-date error code, XML-level failures still
  using `parseFailed`, and a regression test for successful decode producing no error.

### Changed (XML-R2 — Diagnostics)

- All `parseFailed` throws inside `_XMLKeyedDecodingContainer`, `_XMLUnkeyedDecodingContainer`,
  and `_XMLSingleValueDecodingContainer` replaced with `decodeFailed`. Key-not-found cases
  now include the missing key as the last element of the coding path for better debuggability.
- `SwiftXMLCoder.docc/SwiftXMLCoder.md`: `XMLSourceLocation` added to the "Errors" topics section.

### Added (XML-R2 — Namespace Ergonomics Per Field)

- **`XMLFieldNamespaceProvider`** — new protocol allowing a `Codable` type to declare per-field
  XML namespace overrides via a static `xmlFieldNamespaces: [String: XMLNamespace]` dictionary.
  The XML encoder and decoder consult this dictionary to qualify child elements and attributes
  with the specified namespace URI and optional prefix, mirroring the existing
  `XMLFieldCodingOverrideProvider` pattern.
- **`@XMLFieldNamespace(prefix:uri:)` / `@XMLFieldNamespace(uri:)`** — two new peer macros
  (Swift 5.9+) that can be applied to stored properties alongside `@XMLCodable`. `@XMLCodable`
  now scans for these annotations and synthesises an `XMLFieldNamespaceProvider` extension that
  maps the annotated field names to their `XMLNamespace` values.
- **Encoder namespace injection** — when a field has a namespace, the encoder creates the child
  element or attribute with a `XMLQualifiedName(localName:namespaceURI:prefix:)` and
  automatically adds a `XMLNamespaceDeclaration` to the parent element so the resulting XML is
  valid without manual namespace management.
- **Decoder namespace-aware lookup** — `_XMLTreeDecoder.firstChild(named:namespaceURI:in:)` added;
  when a field has a registered namespace, element lookup is qualified by URI, eliminating
  ambiguity between sibling elements that share a local name but differ in namespace.
- **16 new tests** in `XMLFieldNamespaceTests` covering prefixed and default-namespace element
  encoding, attribute namespace encoding, mixed-field encoding, tree-level namespace URI/prefix
  verification, namespace declaration injection on the parent element, round-trip decode
  correctness, and macro-path synthesis (prefixed and default namespace, round-trip).

### Changed (XML-R2 — Namespace Ergonomics Per Field)

- `XMLEncoder.encodeTreeImpl`: initial `_XMLTreeEncoder` now populated with
  `fieldNamespaces: _xmlFieldNamespaces(for: T.self)`, enabling namespace ergonomics for the
  top-level encoded type without requiring an intermediate nested container.
- `XMLDecoder.decodeTreeImpl`: initial `_XMLTreeDecoder` now populated with
  `fieldNamespaces: _xmlFieldNamespaces(for: T.self)` symmetrically.
- `@XMLCodable` macro declaration updated to include `XMLFieldNamespaceProvider` in its
  conformance list and `xmlFieldNamespaces` in the names list.
- `SwiftXMLCoder.docc/SwiftXMLCoder.md`: `XMLFieldNamespaceProvider` added to the
  "Field Mapping" topics section.

### Added (XML-R2 — PI/Doctype/Comment Fidelity)

- **`XMLDocumentNode`** — new `Sendable, Equatable, Codable` enum representing nodes that can
  appear at the document level (outside the root element): `.comment(String)` and
  `.processingInstruction(target:data:)`.
- **`XMLTreeNode.processingInstruction(target:data:)`** — new case enabling processing
  instructions inside element children to survive parse → write round-trips. Previously silently
  dropped by `XMLTreeParser`.
- **`XMLTreeDocument.prologueNodes`** / **`XMLTreeDocument.epilogueNodes`** — `[XMLDocumentNode]`
  arrays capturing PIs and comments that appear before/after the root element in the parsed
  document. Default `[]`; backward-compatible.
- **`XMLDoctype`** — new `Sendable, Equatable, Codable` struct holding the `name`, `systemID`,
  and `publicID` of a `<!DOCTYPE ...>` declaration.
- **`XMLDocumentStructuralMetadata.doctype`** — `XMLDoctype?` field populated from libxml2's
  internal DTD subset when parsing XML with a DOCTYPE declaration. Decoded as `nil` from older
  encoded data (backward-compatible optional field).
- **`XMLNormalizationOptions.includeProcessingInstructions`** — new `Bool` flag (default
  `false`) controlling whether PI nodes are preserved during canonicalization, analogous to the
  existing `includeComments` flag.
- **15 new tests** in `XMLStructuralFidelityTests` covering PI round-trips inside elements,
  document-level prologue/epilogue parsing and writing, SYSTEM/PUBLIC DOCTYPE extraction, and
  `XMLTreeDocument` equality with the new fields.

### Changed (XML-R2 — PI/Doctype/Comment Fidelity)

- `XMLTreeParser` now captures `XML_PI_NODE` children inside elements, walks the document-level
  node list to populate `prologueNodes`/`epilogueNodes`, and extracts DOCTYPE from
  `xmlDocPtr->intSubset`.
- `XMLTreeWriter` now writes `.processingInstruction` children via `xmlNewPI`, inserts prologue
  nodes as prev-siblings of the root element (`xmlAddPrevSibling`), appends epilogue nodes as
  next-siblings (`xmlAddNextSibling`), and writes DOCTYPE via `xmlCreateIntSubset`.
- `XMLCanonicalizer` propagates `prologueNodes`/`epilogueNodes` through normalization, filtering
  them by `includeProcessingInstructions` and `includeComments` options.
- `SwiftXMLCoder.docc/SwiftXMLCoder.md`: `XMLDocumentNode` and `XMLDoctype` added to the
  "Document & Tree" topics section.

## [1.2.0] — 2026-03-21

### Changed

- `FuzzTests/run_fuzzer.sh`: hardened harness compile flags — tightened module search paths to
  `Modules/`, `SwiftXMLCoderCShim.build`, `SwiftXMLCoderOwnership6.build`, and `CLibXML2`
  explicitly; adds `CLibXML2` module dir and auto-detects libxml2 header flags via `pkg-config`
  (with fallback to `-I/usr/include/libxml2`); falls back to linking SPM-produced object files
  when static archives are unavailable on the host platform. Fixes `SwiftXMLCoderCShim` module
  redefinition collisions in GitHub Actions fuzz runs.

### Added (Pillar II.1 — XMLStreamParser)

- **`XMLStreamEvent`** — new `Sendable, Equatable` enum with 8 cases covering the full XML
  event set: `startDocument`, `endDocument`, `startElement`, `endElement`, `text`, `cdata`,
  `comment`, `processingInstruction`.
- **`XMLStreamParser`** — SAX-style streaming parser backed by libxml2's `xmlSAXHandler`.
  Emits `XMLStreamEvent` values in document order without materialising the full DOM tree,
  making it suitable for large documents or pipeline processing.
  - Sync callback API: `parse(data:onEvent:)` — synchronous, works on all Swift versions.
    Swift 6.0+ overload uses typed throws (`throws(XMLParsingError)`).
  - Async API: `events(for:) -> AsyncThrowingStream<XMLStreamEvent, Error>` (macOS 12+,
    iOS 15+). Checks `Task.isCancelled` before each yield.
  - Reuses `XMLTreeParser.Configuration` — whitespace policy, security limits, and logger
    are fully shared between the two parser types.
  - Enforces all security limits: `maxDepth`, `maxNodeCount`, `maxTextNodeBytes`,
    `maxCDATABlockBytes`, `maxCommentBytes`, `maxInputBytes`, `maxAttributesPerElement`.
- **`XMLTreeParser.Limits.maxCommentBytes`** — new backwards-compatible `Int?` limit
  (default `nil`; `untrustedInputDefault()` caps at 256 KiB). Enforced by both
  `XMLStreamParser` and `XMLTreeParser`.

### Added (Pillar II.3 — XMLStreamWriter)

- **`XMLStreamWriter`** — event-driven XML serialiser backed by libxml2's `xmlTextWriter`.
  Consumes any `Sequence<XMLStreamEvent>` and produces well-formed UTF-8 `Data` without
  passing through `XMLTreeDocument`.
  - Sync API: `write<S: Sequence>(_ events: S) throws -> Data`. Swift 6.0+ uses typed throws.
  - Async API: `write<S: AsyncSequence>(_ events: S) async throws -> Data` (macOS 12+).
    Enables symmetric round-trip: `XMLStreamWriter().write(XMLStreamParser().events(for: data))`.
  - `XMLStreamWriter.Configuration` — `encoding`, `prettyPrinted`, `expandEmptyElements`, `limits`.
  - `XMLStreamWriter.WriterLimits` — `maxDepth`, `maxNodeCount`, `maxOutputBytes`,
    `maxTextNodeBytes`, `maxCDATABlockBytes`, `maxCommentBytes`.
    `untrustedOutputDefault()` static factory applies conservative caps.
  - `expandEmptyElements: true` forces `<tag></tag>` long form instead of `<tag/>`.
  - `prettyPrinted: true` emits indented, human-readable output (2-space indent via libxml2).
  - Namespace declarations are written as explicit `xmlns[:prefix]="uri"` attributes, avoiding
    libxml2's auto-emission which conflicted with manually specified declarations.

### Added (Pillar I.5 — Benchmark Regression CI)

- **`.github/workflows/benchmarks.yml`** — new CI workflow that runs on every PR to `main`.
  Executes `swift package benchmark baseline check i2-baseline` and posts a markdown
  comparison table to the job step summary. Regressions emit a `::warning::` annotation
  on the PR but do **not** block merging (`continue-on-error: true`). Results are uploaded
  as a GitHub Actions artifact (30-day retention, keyed by commit SHA).

### Added (Pillar III.1 — Fuzz Testing)

- **`FuzzTests/`** — standalone SPM package containing two libFuzzer harnesses:
  - `FuzzXMLParser` — exercises `XMLTreeParser.parse(data:)` with arbitrary byte sequences.
    Invariant: any input must produce either a valid `XMLTreeDocument` or a typed
    `XMLParsingError`; crashes and memory errors are reported as failures.
  - `FuzzXMLDecoder` — exercises the full `XMLDecoder` pipeline (parse → tree → Codable)
    against a representative `FuzzPayload` type with optional fields.
- **`FuzzTests/run_fuzzer.sh`** — builds each harness with `swiftc -parse-as-library
  -sanitize=address,fuzzer` (linking all SPM-produced static archives) and runs it against
  the seed corpus for `FUZZ_TIME` seconds (default 60). Crash reproducers are saved to
  `ARTIFACT_DIR`.
- **`FuzzTests/corpus/xml/`** — seed corpus with 5 XML inputs covering well-formed elements,
  attributes, namespaces, CDATA, and self-closing tags to guide initial coverage.
- **`.github/workflows/fuzz.yml`** — nightly CI job (02:00 UTC) running both harnesses
  for 120 seconds on `ubuntu-22.04` with Swift 6.1. Crash reproducers are uploaded as
  90-day artifacts. A separate `typecheck` job runs on every push/PR to ensure the
  harness code compiles and does not silently rot.

### Added (Pillar III.2 — Concurrency Stress Testing)

- **`Tests/SwiftXMLCoderTests/XMLConcurrencyStressTests.swift`** — eleven stress tests
  covering both GCD (`DispatchQueue`) and Swift structured concurrency (`async/await`
  with `TaskGroup`): shared encoder, shared decoder, per-task round-trip, shared parser,
  concurrent `xmlInitParser()` first-use, and a mixed encode/decode/parse workload.
  All six scenarios are exercised under both schedulers so TSan detects races regardless
  of which threading model the caller uses.
- **`.github/workflows/ci.yml`** — new `concurrency` job runs `XMLConcurrencyStressTests`
  with `swift test -Xswiftc -sanitize=thread` on `ubuntu-22.04` / Swift 6.1 on every
  push and PR.

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
