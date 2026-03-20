# Pillar I.2 — Baseline Profiling

**Date:** 2026-03-20
**Machine:** Apple M1, macOS 25.3 (Darwin 25.3.0)
**Build:** debug (package-benchmark default)
**Tool:** ordo-one/package-benchmark 1.31.0, jemalloc 5.3.0
**Named baseline:** `i2-baseline` (stored in `Benchmarks/.benchmarkBaselines/`)

---

## Full Metrics Table (p50)

### Parse

| Metric              | 1 KB   | 10 KB    | 100 KB    | 1 MB     |
|:--------------------|-------:|---------:|----------:|---------:|
| Wall clock          | 35 µs  | 239 µs   | 2.31 ms   | 23 ms    |
| CPU total           | 37 µs  | 241 µs   | 2.31 ms   | 23 ms    |
| Instructions        | 427 K  | 3,281 K  | 32,000 K  | 337 M    |
| Malloc (total)      | 256    | 2,222    | 22,000    | 222 K    |
| Peak resident mem   | 12 MB  | 13 MB    | 16 MB     | 41 MB    |

### ParseOnly/10KB (control — identical to Parse/10KB)

| Metric              | 10 KB    |
|:--------------------|----------:|
| Wall clock          | 238 µs   |
| Instructions        | 3,283 K  |
| Malloc (total)      | 2,222    |

> ParseOnly and Parse are statistically identical — confirms there is no measurable overhead
> in the benchmark harness itself and that `XMLTreeParser` is the whole cost of "parse".

### Decode

| Metric              | 1 KB   | 10 KB    | 100 KB    | 1 MB     |
|:--------------------|-------:|---------:|----------:|---------:|
| Wall clock          | 101 µs | 721 µs   | 7.12 ms   | 70 ms    |
| CPU total           | 102 µs | 723 µs   | 7.12 ms   | 70 ms    |
| Instructions        | 1,280 K| 9,282 K  | 94,000 K  | 916 M    |
| Malloc (total)      | 608    | 5,387    | 53,000    | 534 K    |
| Peak resident mem   | 12 MB  | 13 MB    | 16–22 MB  | 43 MB    |

### Encode

| Metric              | 1 KB   | 10 KB    | 10 KB/snake | 100 KB    | 1 MB     |
|:--------------------|-------:|---------:|------------:|----------:|---------:|
| Wall clock          | 124 µs | 837 µs   | 1,174 µs    | 8.13 ms   | 80 ms    |
| CPU total           | 125 µs | 840 µs   | 1,176 µs    | 8.14 ms   | 80 ms    |
| Instructions        | 1,658 K| 11,000 K | 14,000 K    | 109,000 K | 1,096 M  |
| Malloc (total)      | 776    | 6,988    | 6,988       | 69,000    | 691 K    |
| Peak resident mem   | 12 MB  | 13 MB    | 13 MB       | 16–17 MB  | 41 MB    |

### Canonicalize

| Metric              | 1 KB   | 10 KB    | 100 KB    |
|:--------------------|-------:|---------:|----------:|
| Wall clock          | 104 µs | 951 µs   | 9.60 ms   |
| CPU total           | 106 µs | 953 µs   | 9.59 ms   |
| Instructions        | 1,355 K| 13,000 K | 131,000 K |
| Malloc (total)      | 758    | 7,293    | 73,000    |
| Peak resident mem   | 12 MB  | 13 MB    | 17 MB     |

---

## Comparative Analysis at 10 KB (60 items, 5 fields each)

| Operation         | Wall clock | Instructions | Mallocs | Mallocs/item |
|:------------------|----------:|-------------:|--------:|-------------:|
| Parse             | 239 µs    | 3,281 K      | 2,222   | 37           |
| Decode (total)    | 721 µs    | 9,282 K      | 5,387   | 90           |
| Decode overhead   | +482 µs   | +6,001 K     | +3,165  | +53          |
| Encode            | 837 µs    | 11,000 K     | 6,988   | 116          |
| Encode (snake)    | 1,174 µs  | 14,000 K     | 6,988   | 116 (same)   |
| Canonicalize      | 951 µs    | 13,000 K     | 7,293   | 122          |

> CPU time ≈ wall clock for all benchmarks → single-threaded, no lock contention, no I/O.

### Linearity check (10KB→100KB and 100KB→1MB ratios)

| Operation    | ×10 (10→100 KB) | ×10 (100 KB→1 MB) |
|:-------------|----------------:|------------------:|
| Parse        | 9.67×           | 9.97×             |
| Decode       | 9.87×           | 9.83×             |
| Encode       | 9.71×           | 9.84×             |
| Canonicalize | 10.09×          | —                 |

All four operations scale **linearly** with document size. The 1 KB point has proportionally
higher fixed overhead (benchmark harness, `XMLEncoder`/`XMLDecoder` init), visible as a
slightly non-linear step at the small end.

---

## Top-5 Hotspots

### Hotspot 1 — Encoder allocation cascade (priority: HIGH)

**Evidence:** Encode/10KB uses 6,988 mallocs for 60 items = **116 mallocs/item**.
Each `BenchmarkItem` maps to 6 XML elements (1 container + 5 fields). That's ~19 allocations
per XML element — far above the ~6 for the parse phase.

**Likely causes (in order):**
- `_XMLTreeElementBox` allocates a new `[_XMLTreeContentBox]` array per element and appends
  children one by one, triggering multiple reallocations.
- Each field value creates a `String` from the Swift `Encodable` value + a separate
  `_XMLTreeContentBox.text(String)` enum case + an `XMLTreeNode.text` in `makeElement()`.
- The keyed encoding container boxes `self` as a class each time it recurses into a child.

**Optimization target:** `Sources/SwiftXMLCoder/Encoder/_XMLTreeEncoder.swift` —
`_XMLTreeElementBox`, `makeElement()`, and the keyed container child-push path.

---

### Hotspot 2 — Decoder extra mallocs over parse (priority: HIGH)

**Evidence:** Decode adds 3,165 mallocs and 6,001K instructions over parse at 10KB.
With 60 items × (5 fields + element + container) = ~420 logical decode operations,
that is **~7.5 extra mallocs per decode operation** on top of the already-allocated tree.

**Likely causes:**
- `keysForElement(_:)` builds a `[String]` array from the element's children on every
  `KeyedDecodingContainer` init — one allocation per nesting level, even if keys are unused.
- Each `XMLKeyedDecodingContainer` init likely copies or retains the current `XMLTreeElement`.
- String value extraction calls `String(xmlNode.content)` creating a new `String` per field
  even when the value is a scalar that could be parsed in-place.

**Optimization target:** `Sources/SwiftXMLCoder/Decoder/_XMLTreeDecoder.swift` —
`XMLKeyedDecodingContainer.init`, `keysForElement`, and scalar decoding paths.

---

### Hotspot 3 — Snake case key transform CPU cost (priority: MEDIUM)

**Evidence:** Encode/10KB/snakeCase: +337 µs (+40% wall clock), +3M instructions (+27%),
**zero extra mallocs**. The overhead is purely computational.

With 60 items × 5 fields = 300 encode calls per iteration, each calls
`XMLKeyTransformStrategy.convertToSnakeCase` on every key name string.
The function processes every character with no result caching.

**Optimization target:** `Sources/SwiftXMLCoder/XMLKeyTransformStrategy.swift` —
add a small LRU or `NSCache`-backed result cache keyed by `String`.
Since field names are bounded and repeat across items, cache hit rate would be ~100%
after the first item. Would reduce the extra cost to near-zero.

---

### Hotspot 4 — Canonicalize allocates more than Encode (priority: MEDIUM)

**Evidence:** Canonicalize/10KB: 7,293 mallocs vs Encode/10KB: 6,988 — 305 extra mallocs
despite receiving a **pre-parsed** `XMLTreeDocument` (no data→DOM cost).

**Likely causes:**
- Namespace prefix resolution creates temporary `String` objects for each prefix/URI pair
  per element during the canonicalize walk.
- Attribute sorting creates a temporary `[XMLTreeAttribute]` sorted array per element.
- `XMLNormalizationOptions` or transform pipeline state may be heap-allocated per node.

**Optimization target:** `Sources/SwiftXMLCoder/Canonicalization/` —
attribute sorting (use in-place sort on a borrowed slice), namespace tracking (use a stack
of `(prefix, uri)` value types rather than heap-allocated dictionaries).

---

### Hotspot 5 — libxml2 tree materialization (parse phase) (priority: LOW/MEDIUM)

**Evidence:** Parse/10KB allocates 2,222 mallocs for 60 items = 37/item.
Each item has 1 container element + 5 field elements = 6 XML elements, so
**~6 Swift allocations per XML element** to materialize the `XMLTreeDocument`.

**Breakdown per element (estimated):**
1. `XMLTreeElement` struct (box)
2. `[XMLTreeNode]` children array
3. `[XMLTreeAttribute]` attributes array
4. Element name `String` (from libxml2 UTF-8 pointer)
5. `[XMLNamespaceDeclaration]` array (even when empty)
6. Text node `String` for scalar values

**Optimization target:** `Sources/SwiftXMLCoder/Tree/XMLTreeParser.swift` and
`XMLTreeElement` model — use `Substring`/`UnsafeBufferPointer` for element names
and text content when the libxml2 data is still in scope; pre-size children arrays
using `xmlChildElementCount`.

---

## Scaling / Memory Notes

- Peak resident memory scales ~linearly: ~12 MB base + ~29 MB/MB of XML (parse),
  ~31 MB/MB (decode), ~29 MB/MB (encode).
- At 1 MB, encode and decode both peak at ~40–43 MB — within acceptable range for
  server-side use but will need attention for embedded / memory-constrained targets.
- All p0→p99 latency bands are tight (< 15% spread for the large fixtures), indicating
  consistent behavior without GC pressure spikes.

---

## Recommended Optimization Sequence (Pillar I.3)

1. **Hotspot 3 first** (key transform cache) — smallest change, measurable win, zero risk.
2. **Hotspot 1** (encoder allocations) — highest absolute allocation count, biggest encode gain.
3. **Hotspot 2** (decoder extra mallocs) — highest impact on end-to-end decode throughput.
4. **Hotspot 4** (canonicalize sort/namespace) — important for XMLDSig work later.
5. **Hotspot 5** (parse materialization) — requires tree model changes, higher risk.

Each change must show measurable improvement against the `i2-baseline` before being merged.
