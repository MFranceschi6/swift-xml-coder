# Enterprise XML Roadmap

Last updated: 2026-03-27. Baseline: release `1.3.0`.

## Vision

Transform `swift-xml-coder` into a full enterprise XML stack for Swift: core runtime + satellite packages.

## Ecosystem Topology

| Package | Type | Purpose |
| --- | --- | --- |
| `swift-xml-coder` | core | parsing, writing, tree model, Codable, namespace, XPath, macro, canonicalization |
| `swift-xml-nio` | satellite | NIO ByteBuffer bridge |
| `swift-xml-vapor` | satellite | Vapor request/response adapter |
| `swift-xml-hummingbird` | satellite | Hummingbird adapter |
| `swift-xml-schema` | satellite | XSD parsing, validation, resource resolution |
| `swift-xml-codegen` | satellite | XSD → Swift models CLI/plugin |
| `swift-xml-xslt` | future | XSLT transform engine |
| `swift-xml-dsig` | future | XML Digital Signature, C14N standard-grade |

## Phases

| Phase | Status | Summary |
| --- | --- | --- |
| 1 — Core Completeness | done | tree model, Codable, namespace, XPath, macro, streaming, diagnostics |
| 2 — Pull Cursor + Item Streaming | done | `XMLEventCursor`, `XMLItemDecoder`, backpressure, cancellation |
| 2b — SAX-to-Codable (XML-PERF-1) | done | SAX decoder, parser optimizations, canonicalizer redesign. Post-1.4.0 SAX decode hot-path tightening remains tracked in `active-plan.md`. |
| 2c — SAX Encoder + Pipeline Composition | planned | `_XMLSAXEncoder`, callback/AsyncSequence composition, NIO bridge primitive |
| 3 — Framework Interop | planned | `swift-xml-nio`, `swift-xml-vapor`, `swift-xml-hummingbird` |
| 4 — Schema + Validation | planned | `swift-xml-schema`: XSD parser, `XMLSchemaSet`, validation |
| 5 — Codegen | planned | `swift-xml-codegen`: XSD → Swift models |
| 6 — XSLT | planned | `swift-xml-xslt` |
| 7 — DSig + C14N | planned | `swift-xml-dsig`: exclusive C14N, digest/signature helpers |

## Locked Decisions

- **core + satellites** topology — core stays small and framework-neutral
- **WSDL/SOAP out of scope** — transport/protocol concerns, not XML runtime
- **canonicalizer is standalone** — not wired into encoder/decoder; DSig orchestrates externally
- **`XMLCanonicalizer` stays protocol** — DSig can provide custom conformers (exclusive C14N)
- **streaming primitive is sync callback** `(Data) throws -> Void` — AsyncSequence/NIO built on top
- **two transform protocols**: `XMLTransform` (tree) + `XMLEventTransform` (streaming)
- **SAX encoder (E3) in Phase 2c** before Framework Interop (Phase 3)
- **baseline is `1.3.0`** — `1.4.0+` treated as local/planned until published

## Open Questions

- Final naming of satellite packages (branding/availability)
- Minimum feature set for first release of `swift-xml-xslt` and `swift-xml-dsig`
- Monorepo vs multi-repo for ecosystem

## Performance Notes

- SAX decode hot-path tightening complete (2026-03-28): `_LazyLineTable`, `startToEnd` side
  table, sequential cursor (`childCursor`). `Decode/SAX/100KB` now beats `Decode/Tree/100KB`.
  Results: `Benchmarks/Results/2026-03-28-cursor-optimization.txt`.
- Next performance gate: evaluate pure-Swift parser core after Phase 2c SAX encoder lands,
  using `SAXParseOnly/*` microbenchmarks to isolate parser-vs-decoder cost.
