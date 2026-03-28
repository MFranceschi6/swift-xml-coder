# Plan: XML-PERF-1 — SAX Decoder + Performance Overhaul

## Status

**Complete.** All phases (1–8) done. Tagged as 1.4.0.

## Architecture (reference)

```
Decode (new):  Data → XMLStreamParser (push) → _XMLEventBuffer → _XMLSAXDecoder → Codable
Decode (tree): Data → XMLTreeParser → XMLTreeDocument → _XMLTreeDecoder → Codable
Canon (tree):  XMLTreeDocument → walk + sort → XMLStreamWriter → Data
Canon (stream): Data → SAX → XMLEventTransform* → sort → serialize → output callback
```

Key files: `XMLSAXDecoder+Codable.swift`, `XMLScalarDecoder.swift`, `XMLEventTransform.swift`,
`XMLDefaultCanonicalizer.swift`, `XMLCanonicalizationOptions.swift`.

## Completed Phases

| Phase | Summary |
|-------|---------|
| 1 | SAX push parser, unchecked QName init, buffer reuse, limits fast-path, tree pre-sizing |
| 2 | `_XMLScalarDecoder` extracted, tree decoder delegates |
| 3 | `_XMLEventBuffer` with line numbers side table |
| 4 | SAX keyed/unkeyed/single-value containers |
| 5 | `decode(_:from:)` wired to SAX, `XMLItemDecoder` uses direct events |
| 6 | E1: `reserveCapacity` on encoder element boxes |
| 7 | Canonicalizer redesign: dual entry points, `XMLEventTransform`, 13→5 files |

## Remaining Work (Phase 8)

- [x] ~E2: Deferred — `_XMLTreeContentBox` removal requires restructuring class-ref accumulation; real fix is streaming encoder (future plan)~
- [x] Benchmark validation — SAX decode wins at 10MB (64% faster), competitive at medium sizes; stream canonicalize 27–38% faster than tree
- [x] Benchmark results documented in `Benchmarks/Results/`
- [x] Lint pass — 0 serious violations
- [x] Release notes in CHANGELOG.md — 1.4.0 stamped

## Post-1.4.0 Follow-On — SAX Decode Hot-Path Tightening — **Complete (2026-03-28)**

Achieved −8-10% vs baseline across all sizes. `Decode/SAX/100KB` now beats `Decode/Tree/100KB`
(5247 μs vs 5304 μs). Results in `Benchmarks/Results/2026-03-28-cursor-optimization.txt`.

Goal: make the current buffered SAX-to-Codable path materially faster before or alongside
the fully streaming decode work tracked elsewhere.

Context:
- Current architecture is still `Data -> XMLStreamParser -> ContiguousArray events + lineNumbers
  -> _XMLEventBuffer -> _XMLSAXDecoder -> Codable`, so decode is not yet truly streaming.
- Current benchmark note above reflects an earlier run. The latest 2026-03-27 benchmarks in
  `Benchmarks/Results/2026-03-27-full-comparison-summary.md` show `Decode/Tree` still ahead
  of `Decode/SAX` on the current fixtures at `10KB`, `100KB`, `1MB`, and `10MB`.
- The likely reason is CPU overhead in the SAX decode layer rather than parser throughput:
  `_XMLEventBuffer` repeatedly reconstructs structure from flat events, and keyed/unkeyed
  containers still do many linear scans over spans.
- Non-goal: this section does not replace the true streaming decode plan. It is intended to
  tighten the hot path of the current event-buffer architecture and any buffered fallback path.

Priority steps (all completed):

1. [x] Structural side tables in `_XMLEventBuffer`
   - Precompute `rootStart/rootEnd` once.
   - Precompute `startIndex -> endIndex` for element spans.
   - Optionally precompute direct-child span lists for each element start index.
   - Target files: `XMLDecoder.swift`, `XMLSAXDecoder+Codable.swift`.
   - Why: remove repeated depth scans in `findRootElement`, `elementEndIndex`, and
     `childElementSpans`.

2. [x] Sequential cursor (`childCursor`) for keyed decode — replaces per-span dict caches
   (Steps 2/3 were implemented as dict caches, benchmarked, found to be +5-10% regression due
   to malloc overhead for N≤8 required fields. Reverted. Implemented cursor instead.)

3. [x] (reverted — see Step 2 note above)

4. [x] Optional or lazy line-number capture
   - Make line-number side-table construction opt-in for benchmark / fast path scenarios, or
     capture lazily only when diagnostics are needed.
   - Preserve existing rich diagnostics by default in public APIs unless an internal fast path
     is explicitly selected.
   - Target files: `XMLDecoder.swift`, `XMLStreamParser+SAX.swift`, `XMLSAXDecoder+Codable.swift`.
   - Why: line collection currently adds one append per event even when no error occurs.

5. [x] Profiling and benchmark decomposition
   - Add focused microbenchmarks for:
     - `_XMLEventBuffer.findRootElement`
     - `_XMLEventBuffer.childElementSpans`
     - keyed `contains` / `decodeScalar` on representative flat and nested fixtures
     - lexical-text extraction on scalar-heavy payloads
   - Keep end-to-end benchmarks for `Decode/SAX/*` vs `Decode/Tree/*`.
   - Why: separate parser cost from buffer/index cost so improvements are attributable.

6. Acceptance targets
   - `Decode/SAX` should at least reach parity with `Decode/Tree` on `100KB` and `1MB`
     current fixtures, and clearly win on `10MB`.
   - `Decode/SAX` should retain its existing memory advantage over tree decode on
     `Malloc (total)`.
   - Raw parser-only results should move closer to Foundation's `XMLParser`, but raw SAX parse
     parity is not itself the acceptance bar for full `Codable` decode.

7. Post-optimization decision gate: evaluate a pure-Swift parser core
   - Only after the steps above are implemented and re-benchmarked.
   - Goal: determine whether the remaining gap is mostly in the current
     `libxml2 + callback bridge + event-buffer` architecture, or whether `libxml2`
     is still the right parser core once the surrounding Swift hot path is tightened.
   - Evaluation options:
     - keep `libxml2` and continue optimizing the current buffered/streaming decode layers
     - build a hybrid Swift structural indexer/tokenizer on top of raw bytes
     - build a pure-Swift parser for the performance-oriented subset
   - Initial pure-Swift scope, if explored:
     - UTF-8 only
     - well-formed XML fast path
     - namespaces supported
     - no DTD engine in the first iteration
     - optimized for `Codable` decode and internal pipelines, not full libxml2 feature parity
   - What to measure:
     - end-to-end `Decode/SAX/*` vs `Decode/Tree/*`
     - parser-only throughput vs Foundation / current `XMLStreamParser`
     - `Malloc (total)` and peak RSS
     - implementation complexity, maintenance cost, and compatibility risk
   - Exit criteria:
     - pursue pure Swift only if the optimized SAX path still leaves a meaningful
       performance or allocation gap that looks parser-core / bridge-bound rather
       than decoder-logic-bound

Suggested implementation order:
- Side tables
- Keyed lookup indexes
- Scalar / nil caches
- Optional line-number fast path
- Re-benchmark and profile again
- Then decide whether a pure-Swift parser experiment is justified

## Breaking Changes (vs 1.3.0)

- `XMLCanonicalizer` protocol: new `canonicalize(...)` methods replace `canonicalView`
- `XMLNormalizationOptions` → `XMLCanonicalizationOptions`
- Removed: `XMLCanonicalView`, `XMLCanonicalizationContract`, `XMLCanonicalizationError*`,
  `XMLCanonicalizationStage`, `XMLIdentityTransform`
- New: `XMLEventTransform` protocol
