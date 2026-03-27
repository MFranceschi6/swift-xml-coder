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

## Breaking Changes (vs 1.3.0)

- `XMLCanonicalizer` protocol: new `canonicalize(...)` methods replace `canonicalView`
- `XMLNormalizationOptions` → `XMLCanonicalizationOptions`
- Removed: `XMLCanonicalView`, `XMLCanonicalizationContract`, `XMLCanonicalizationError*`,
  `XMLCanonicalizationStage`, `XMLIdentityTransform`
- New: `XMLEventTransform` protocol
