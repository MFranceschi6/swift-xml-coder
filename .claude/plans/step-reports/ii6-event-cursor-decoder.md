# Step Report — II.6 Event-Cursor Decoder

## Scope

- **Task:** Replace the `buildDocument → XMLTreeDocument → XMLDecoder` pipeline in
  `XMLStreamDecoder` with a direct `Decoder` conformance that operates on `[XMLStreamEvent]`
  via index, eliminating intermediate tree node allocations.
- **Boundaries:** Internal refactor only. No public API changes. No changes to
  `XMLStreamEncoder`, `XMLStreamParser`, or `XMLStreamWriter`.

---

## Public API Changes

- **Added:** none (new types are `internal`)
- **Changed:** none (public signatures of `XMLStreamDecoder.decode` are unchanged)
- **Removed:** `buildDocument` and `popElement` private methods from `XMLStreamDecoder`

---

## Implementation Notes

### Core logic

New file: `Sources/SwiftXMLCoder/XMLStreamEventDecoder.swift`

**`EventRange`** (`struct { start: Int; end: Int }`) — indices into the flat `[XMLStreamEvent]`
array where `events[start]` is `.startElement` and `events[end]` is the matching `.endElement`.

**Three free helper functions:**

| Function | Purpose |
|---|---|
| `_streamBuildChildIndex(events:scope:)` | Returns `[String: [EventRange]]` — one forward pass, direct children only |
| `_streamDirectChildren(events:scope:)` | Returns `[EventRange]` in document order |
| `_streamExtractText(events:scope:)` | Concatenates `.text` + `.cdata` at depth-0 inside scope |

**`XMLStreamEventDecoder: Decoder`** — holds `events`, `scope`, `options`, `fieldNodeKinds`,
`codingPath`, and a `scalarOracle: _XMLTreeDecoder` (dummy element used only for
`decodeScalarFromLexical`).

**`_StreamKeyedContainer<Key>`** — keyed container:
- Builds `childIndex` and `attributes` dict once in `init` (O(n) forward pass).
- `resolvedNodeKind(for:xmlName:)` mirrors `_XMLKeyedDecodingContainer`:
  type wrappers → macro dict → runtime overrides → `.element` default.
- `xmlName(for:)` applies `keyTransformStrategy` with `_XMLKeyNameCache`.
- `decodeAttribute` / `decodeTextContent` / `tryDecodeScalar` for the three non-element paths.
- `isNil(scope:)` mirrors `_XMLTreeDecoder.isNilElement` — true when no child elements and
  no non-whitespace text content.

**`_StreamUnkeyedContainer`** — advances a cursor index over `children: [EventRange]`;
filters to `itemElementName` children when present (mirrors `_XMLUnkeyedDecodingContainer`).

**`_StreamSingleValueContainer`** — used for top-level scalar decoding.

Modified file: `Sources/SwiftXMLCoder/XMLStreamDecoder.swift`

- `decodeImpl` now: `Array(events)` → `findRootScope` → root name validation →
  `XMLStreamEventDecoder` init → scalar intercept → `T(from: eventDecoder)`.
- Scalar intercept mirrors `XMLDecoder.decodeTreeImpl`: `String` bypasses oracle; other
  scalars use `scalarOracle.decodeScalarFromLexical`.
- `findRootScope` / `resolveExpectedRootName` are new private helpers replicating the
  logic previously handled inside `XMLDecoder`.

### Edge cases handled

- Out-of-order fields: child index lookup is O(1) map access; no backtracking required.
- Optional absent: `childIndex` miss → `decodeNil` returns `true` → nil.
- Mixed text+CDATA: `_streamExtractText` concatenates all in sequence.
- Attributes-only field kind: extracted from `.startElement` attributes list at init time.
- `textContent` field kind: `_streamExtractText` on the parent scope.
- `itemElementName` filtering in unkeyed container: if any children match the configured
  item element name, only those are yielded; otherwise all children.
- `perPropertyDateHints`: copied into `nestedOptions` before each nested decoder creation.

### Design rationale and rejected alternatives

**Scalar oracle pattern:** `decodeScalarFromLexical` is a ~200-line function in
`_XMLTreeDecoder` handling all numeric types, `Bool`, `Date` (all strategies), `Data`,
`URL`, `Decimal`, and custom scalar protocols. Rather than duplicating it, we instantiate
a `_XMLTreeDecoder` with a dummy `XMLTreeElement` and call through it. The dummy element
is never navigated — it is only a method carrier. Considered extracting as a free function
but that would require `internal` visibility changes across more files.

**EventRange end-inclusive vs exclusive:** `end` is inclusive (`events[end]` is the
`.endElement`). This matches the structure of the event stream and makes `findRootScope`
natural (returns immediately when depth hits 0 at an `.endElement`).

**No streaming decode:** `Decodable` requires synchronous random-access key lookup, so
buffering the full event array is unavoidable. This is documented in the public API doc
comment.

---

## Validation Evidence

- **Build:** `swift build -c debug` → `Build complete!` (0 errors, 0 warnings)
- **Tests:** `swift test --enable-code-coverage` → **514 tests, 0 failures**
  - 12 new tests in `XMLStreamEventDecoderTests` all pass
  - All 502 pre-existing tests continue to pass
- **Lint:** `swiftlint lint` → **0 errors, 257 warnings** (all pre-existing; no new violations)

---

## Risks and Follow-ups

- **Residual risk — scalar oracle dummy allocation:** The `_XMLTreeDecoder` scalar oracle
  creates a dummy `XMLTreeElement` per top-level decode call. This is a small, bounded
  allocation with no semantic side effects. Acceptable for now; could be eliminated in a
  future refactor by extracting `decodeScalarFromLexical` as a free function.
- **Non-blocking follow-up — II.7 encodeEach:** `XMLStreamEncoder+Sequence.swift` is the
  next independent step. Plan: `encode-each-async.md`.
- **Non-blocking follow-up — III.4 fuzz harness for streaming:** Depends on II.6 being
  complete (now satisfied). Can be scheduled alongside or after II.7.