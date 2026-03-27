# Plan: Streaming Internals — Fully Event-Driven Internal Pipelines

## Goal

Make all internal encode/decode/canonicalize pipelines truly streaming (event-driven,
bounded memory). Public synchronous Codable APIs (`encode`/`decode` accepting `Data`) are
preserved — they wrap the streaming internals.

## Architecture After

```
Encode:  Codable → _XMLEventEncoder → XMLStreamEvent* → XMLStreamWriterSink → callback(Data)
Decode:  Data → XMLStreamParser (push, chunked) → _XMLEventBuffer → _XMLSAXDecoder → Codable
Canon:   Data → SAX → XMLEventTransform* → normalize(event) → XMLStreamWriterSink → callback(Data)
Items:   XMLEventCursor → span(start,end) → _XMLEventBuffer(slice) → _XMLSAXDecoder → T
```

## Phase 1 — XMLStreamWriterSink

**Status:** complete

Extract the `writeImpl` loop from `XMLStreamWriter+Logic.swift` into an incremental
`XMLStreamWriterSink` that:
1. Accepts one `XMLStreamEvent` at a time via `func write(_ event:) throws`
2. Flushes accumulated bytes to a `(Data) throws -> Void` callback after each event (or
   after a configurable byte threshold)
3. Calls a `func finish() throws` to flush final bytes + free libxml2 resources
4. Reuses the existing `writeEvent(_:writer:state:)` logic unchanged

`XMLStreamWriter.write(_:)` becomes a thin wrapper: create sink → feed all events → finish → return accumulated Data.

**Files:**
- New: `XMLStreamWriterSink.swift`, `XMLStreamWriterSink+Logic.swift`
- Modified: `XMLStreamWriter+Logic.swift` (extract shared event-dispatch)

**Tests:** existing XMLStreamWriter tests must still pass; add incremental output test.

## Phase 2 — Streaming Canonicalizer

**Status:** complete

Wire `XMLDefaultCanonicalizer`'s stream path to use `XMLStreamWriterSink` for per-event output.

Currently `canonicalize(events:...) throws` accumulates all normalised events into an array,
then calls `XMLStreamWriter.write()` at the end. After this phase, each normalised event is
fed directly to a sink, and the `output` callback receives data chunks incrementally.

**Files:**
- Modified: `XMLDefaultCanonicalizer.swift` (stream path uses sink)

**Tests:** existing canonicalizer tests must pass; add test verifying multiple output chunks.

## Phase 3 — SAX Encoder (_XMLEventEncoder)

**Status:** complete

New internal `_XMLEventEncoder` that implements `Encoder` and emits `XMLStreamEvent` values
during Codable encoding, without building an intermediate tree.

Key design:
- Each keyed container buffers attributes (via `_xmlFieldNodeKinds` metadata from `XMLFieldCoding`)
  until the first child element or text, then emits `.startElement` with accumulated attrs.
- Text/CDATA values emit immediately as `.text`/`.cdata`.
- Container close emits `.endElement`.
- Unkeyed containers emit wrapper elements per item.

`XMLEncoder.encode()` becomes: create `_XMLEventEncoder` → encode → collect events →
`XMLStreamWriterSink` → Data.

**Files:**
- New: `XMLEventEncoder+Codable.swift`
- Modified: `XMLEncoder.swift` (add `encodeEvents` internal path)

**Tests:** encode parity tests (tree vs event encoder produce identical XML).

## Phase 4 — XMLItemDecoder Span-Based Decode

**Status:** complete

`XMLItemDecoder` currently copies events per item into a new `_XMLEventBuffer`. Instead:
- Track `(startIndex, endIndex)` spans in the shared event buffer
- Create `_XMLEventBuffer` views (or pass range) to avoid copies
- For SAX decode path, pass the span directly to `_XMLSAXDecoder`

**Files:**
- Modified: `XMLItemDecoder.swift`

**Tests:** existing item decoder tests must pass; add test for large item count.

## Phase 5 — Parity Tests and Benchmarks

**Status:** complete

- Streaming encode vs tree encode parity (round-trip identical XML)
- Incremental canonicalize output test (multiple chunks)
- Benchmark: streaming encode vs tree encode
- Benchmark: streaming canonicalize memory (peak RSS or malloc count)
- Update `Benchmarks/Results/` with findings
- CHANGELOG entry for streaming internals work
