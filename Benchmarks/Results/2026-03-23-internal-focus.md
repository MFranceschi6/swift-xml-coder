# Internal Benchmark Focus - 2026-03-23

Source run:
- `Benchmarks/internal-benchmark-result.md`

Reference baseline for the pre-redesign canonicalizer:
- `Benchmarks/Results/internal-benchmarks.md`

## Executive Summary

- The new canonicalizer redesign is in a good place.
- The new streaming canonicalizer paths beat the tree path consistently.
- The tree canonicalizer baseline stayed effectively flat versus the old benchmark suite.
- `XMLDecoder` on the SAX path is not yet a universal win over the tree path.
- Against `XMLCoder`, SwiftXMLCoder remains clearly ahead on encode and ahead on decode with either the tree path or, for very large payloads, the SAX path.
- Some large-input streaming benchmarks failed with `internal error: Huge input lookup`. Those failures should be treated as real anomalies and not ignored when reading the results.

## Benchmark Anomalies

The following benchmarks failed in the run log:

- `StreamDecode/ItemDecoder/100MB`
- `StreamDecode/ItemDecoder/10MB`
- `StreamDecode/ItemDecoder/Rich/100MB`
- `StreamParse/Cursor/100MB`
- `StreamParse/Cursor/10MB`

All of them failed with:

```text
SwiftXMLCoder.XMLParsingError.parseFailed(message: Optional("internal error: Huge input lookup"))
```

Relevant log lines:
- `Benchmarks/internal-benchmark-result.md:1415`
- `Benchmarks/internal-benchmark-result.md:1431`
- `Benchmarks/internal-benchmark-result.md:1469`
- `Benchmarks/internal-benchmark-result.md:1530`
- `Benchmarks/internal-benchmark-result.md:1548`

Probable origin, but not yet proven:

- `XMLStreamParser` is implemented on top of libxml2 SAX push parsing.
- On parse failure it reads the backend error message from `xmlGetLastError()` and rethrows it as `XMLParsingError.parseFailed`.
- `XMLEventCursor` wraps `XMLStreamParser`, so cursor and item-decoder failures inherit that same backend error surface.

Code references:
- `Sources/SwiftXMLCoder/XMLStreamParser.swift:4`
- `Sources/SwiftXMLCoder/XMLStreamParser+SAX.swift:285`
- `Sources/SwiftXMLCoder/XMLStreamParser+SAX.swift:304`
- `Sources/SwiftXMLCoder/XMLEventCursor.swift:32`
- `Sources/SwiftXMLCoder/XMLEventCursor.swift:61`

Interpretation:

- The error text itself likely comes from libxml2 or from the libxml2-backed SAX layer, not from a custom SwiftXMLCoder diagnostic.
- The current run is therefore incomplete for some large streaming workloads.
- This does not invalidate all large-input results, because `StreamParse/SAX/10MB` and `StreamParse/SAX/100MB` completed successfully in the same run.
- Because the failures are selective, the issue may depend on fixture shape, buffering path, or a backend interaction in the cursor/item-decoder stack rather than on input size alone.

## Canonicalizer

The canonicalizer suite now covers:

- `Canonicalize/Tree/*`
- `Canonicalize/StreamData/*`
- `Canonicalize/StreamEvents/*`
- `Canonicalize/StreamData/NoOpTransform/*`
- `Canonicalize/StreamData/NormalizeTextTransform/*`

Source sections:
- `Benchmarks/internal-benchmark-result.md:1972`
- `Benchmarks/internal-benchmark-result.md:2126`

### p50 Wall Clock

| Benchmark | 1KB | 10KB | 100KB |
| --- | ---: | ---: | ---: |
| `Tree` | 106 us | 982 us | 9576 us |
| `StreamData` | 86 us | 663 us | 7021 us |
| `StreamEvents` | 77 us | 611 us | 6095 us |
| `StreamData + NoOpTransform` | 106 us | 878 us | 9200 us |
| `StreamData + NormalizeTextTransform` | 129 us | 1149 us | 11 ms |

### Takeaways

- `StreamData` beats `Tree` by about `19%` at 1KB, `32%` at 10KB, and `27%` at 100KB.
- `StreamEvents` is the fastest path and beats `Tree` by about `27%`, `38%`, and `36%`.
- Transform overhead is visible and material.
- The `NoOpTransform` path is still competitive with `Tree`.
- A real transform such as `NormalizeTextTransform` can erase the streaming gain and become slower than `Tree`.

### Tree Baseline vs Legacy Canonicalize Benchmark

The old suite only measured the tree-style canonicalizer. Comparing old p50 wall-clock values with the new `Canonicalize/Tree/*` values:

| Size | Old `Canonicalize/*` | New `Canonicalize/Tree/*` | Delta |
| --- | ---: | ---: | ---: |
| 1KB | 107 us | 106 us | about `-1%` |
| 10KB | 981 us | 982 us | flat |
| 100KB | 9470 us | 9576 us | about `+1%` |

Source sections:
- Old baseline: `Benchmarks/Results/internal-benchmarks.md:901`
- New tree results: `Benchmarks/internal-benchmark-result.md:2104`

Conclusion:

- The redesign did not regress the tree baseline in a meaningful way.
- The performance upside of the redesign comes from the new streaming canonicalization entry points.

## Decode: SAX vs Tree

Source sections:
- `Benchmarks/internal-benchmark-result.md:2599`
- `Benchmarks/internal-benchmark-result.md:2676`

### p50 Wall Clock

| Benchmark | 10KB | 100KB | 1MB | 10MB |
| --- | ---: | ---: | ---: | ---: |
| `Decode/SAX` | 650 us | 6259 us | 62 ms | 209 ms |
| `Decode/Tree` | 641 us | 5947 us | 59 ms | 578 ms |

### Takeaways

- At `10KB`, `100KB`, and `1MB`, the SAX path is still slightly slower than the tree path.
- At `10MB`, the SAX path is dramatically better, about `64%` faster than the tree path.
- The current state is therefore mixed: the SAX decoder pays off strongly on large payloads, but it is not yet the best default performer across medium sizes.

## Rich Decode: SAX vs Tree

Source sections:
- `Benchmarks/internal-benchmark-result.md:2511`
- `Benchmarks/internal-benchmark-result.md:2588`

### p50 Wall Clock

| Benchmark | 10KB | 100KB | 1MB | 10MB |
| --- | ---: | ---: | ---: | ---: |
| `Decode/Rich/SAX` | 546 us | 4944 us | 51 ms | 528 ms |
| `Decode/Rich/Tree` | 513 us | 5149 us | 48 ms | 494 ms |

### Takeaways

- `Rich/SAX` wins at `100KB`.
- `Rich/Tree` still wins at `10KB`, `1MB`, and `10MB`.
- The rich model path shows the same overall story as the plain decode path: not a broad SAX win yet.

## SwiftXMLCoder vs XMLCoder

Source sections:
- `Benchmarks/internal-benchmark-result.md:1750`
- `Benchmarks/internal-benchmark-result.md:1959`

### Decode p50 Wall Clock

| Size | SwiftXMLCoder SAX | SwiftXMLCoder Tree | XMLCoder | Best |
| --- | ---: | ---: | ---: | --- |
| 10KB | 649 us | 577 us | 698 us | SwiftXMLCoder Tree |
| 100KB | 6148 us | 5599 us | 6971 us | SwiftXMLCoder Tree |
| 1MB | 63 ms | 57 ms | 70 ms | SwiftXMLCoder Tree |
| 10MB | 188 ms | 599 ms | 757 ms | SwiftXMLCoder SAX |

### Encode p50 Wall Clock

| Size | SwiftXMLCoder | XMLCoder |
| --- | ---: | ---: |
| 10KB | 876 us | 1280 us |
| 100KB | 8204 us | 12 ms |
| 1MB | 84 ms | 131 ms |
| 10MB | 812 ms | 1350 ms |

### Takeaways

- SwiftXMLCoder decode beats XMLCoder at all measured sizes.
- Up to `1MB`, the fastest SwiftXMLCoder decode path is still the tree path.
- At `10MB`, the SAX path becomes the clear winner overall.
- SwiftXMLCoder encode remains clearly faster than XMLCoder across the whole tested range.

## SwiftXMLCoder vs Foundation Parse

Source sections:
- `Benchmarks/internal-benchmark-result.md:2137`
- `Benchmarks/internal-benchmark-result.md:2412`

### SAX Parse p50 Wall Clock

| Size | Foundation `XMLParser` | SwiftXMLCoder `XMLStreamParser` |
| --- | ---: | ---: |
| 10KB | 100 us | 154 us |
| 100KB | 926 us | 1341 us |
| 1MB | 9011 us | 13 ms |
| 10MB | 96 ms | 130 ms |

### Tree Parse p50 Wall Clock

| Size | Foundation Tree Parse | SwiftXMLCoder Tree Parse |
| --- | ---: | ---: |
| 10KB | 290 us | 231 us |
| 100KB | 2789 us | 2198 us |
| 1MB | 28 ms | 23 ms |
| 10MB | 281 ms | 229 ms |

### Takeaways

- Foundation still leads raw SAX event parsing.
- SwiftXMLCoder now leads the tree parse path at every measured size in this run.
- That split is coherent with the rest of the data: our DOM/tree construction path is strong, while the streaming path still has headroom.

## Overall Assessment

What looks ready:

- Canonicalizer redesign performance
- XMLCoder competitiveness
- Encode path performance
- Tree parse and tree decode performance

What is not yet fully where we want it:

- SAX decode on `10KB` to `1MB`
- Rich SAX decode on most tested sizes
- Stability of the large streaming cursor and item-decoder benchmarks

## Suggested Follow-Ups

1. Reproduce the `Huge input lookup` failures outside the benchmark harness with a focused test or stress utility around `XMLEventCursor(data:)` and `XMLItemDecoder`.
2. Compare parser configuration and fixture shape between successful `StreamParse/SAX/*` runs and failing cursor/item-decoder runs.
3. Profile `Decode/SAX/100KB` and `Decode/SAX/1MB` to identify where the remaining overhead sits relative to the tree path.

## Investigation Addendum

Follow-up investigation performed after the initial benchmark readout:

- Local environment reports `libxml2 2.9.13` via `xmllint --version`.
- SwiftXMLCoder's SAX path uses libxml2 push parsing (`xmlCreatePushParserCtxt` + `xmlParseChunk`).
- A focused local stress reproduction outside the benchmark harness reproduced the same failure on a flat fixture around the 10 MB scale:
  - `XMLStreamParser`
  - `XMLEventCursor`
  - `XMLItemDecoder`

Implementation references:

- `Sources/SwiftXMLCoder/XMLStreamParser+SAX.swift`
- `Tests/SwiftXMLCoderTests/XMLStreamingLargeInputStressTests.swift`

Strong working diagnosis:

- The benchmark anomaly is real.
- The failure is consistent with an old libxml2 push-parser large-input issue, surfaced as `internal error: Huge input lookup`.
- The text of the error is especially plausible as a libxml2-originated diagnostic because SwiftXMLCoder rethrows the backend error string from `xmlGetLastError()`.

Workaround implemented in SwiftXMLCoder:

- reset libxml2's last error before SAX parsing
- apply the same libxml2 parse options used by the tree parser to the push parser context
- feed large inputs to `xmlParseChunk` incrementally in 1 MiB chunks instead of a single monolithic chunk

Observed result after the workaround:

- the focused 10 MB stress reproduction now passes for `XMLStreamParser`
- it also passes for `XMLEventCursor`
- it also passes for `XMLItemDecoder`
- the regular test suite still passes (`574` tests, `0` failures, `3` skipped)

Interpretation:

- This makes the original benchmark failures much more likely to be an interaction between SwiftXMLCoder's previous one-shot push-parser feeding strategy and the older system libxml2 version, rather than a logic bug in cursor or item decoding themselves.
