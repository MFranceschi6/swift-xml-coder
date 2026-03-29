# SwiftXMLCoder — Post-Release Roadmap

Piano generale per il ciclo di sviluppo post-1.0. Organizzato per **Pillar** tematici.
Ogni Pillar ha voce nel CHANGELOG e nei branch `claude/pillar-*` / `claude/epic-*`.

> Nota baseline del `2026-03-21`: l'ultima release pubblica verificata online e' `1.1.0`.
> I riferimenti a `1.2.0+` in questo documento vanno letti come stato locale o pianificato
> finche' non esistono tag e release pubbliche corrispondenti.
>
> Per la roadmap strategica completa e agent-neutral, vedi
> [`enterprise-xml-roadmap/README.md`](enterprise-xml-roadmap/README.md).

Questo documento aggrega:
- il piano Pillar originale (sessioni del 20-21 marzo 2026)
- i nuovi step di streaming concordati il 21 marzo 2026

---

## Stato milestones

| Milestone | Versione | Contenuto | Stato |
|---|---|---|---|
| Fase 1 | 1.1.0 | Benchmark I.1-I.3, community IV.4, macro VII.1-3+VII.5, fuzz III.1, stress III.2, streaming II.1+II.3, bench CI I.5 | ✅ Rilasciato |
| Fase 2 | 1.2.0 | Streaming Codable + Real IO (II.2, II.4, II.5) | 🧭 Locale / non pubblicata |
| Fase 3 | prossima | Streaming ottimizzazioni (II.6, II.7) | ⏳ Locale / in corso |
| Fase 4 | futura | Pillar V, VI, completamento I.4, I.6+ | ⏳ Pianificato |

---

## Pillar I — Performance & Benchmarking

| Item | Descrizione | Stato |
|---|---|---|
| I.1 | Benchmark infrastructure — `Benchmarks/` SPM target (ordo-one/package-benchmark), 4 suite (Parse, Encode, Decode, Canonicalize), fixture 1 KB–1 MB | ✅ Done |
| I.2 | Baseline profiling — metriche documentate in `.claude/benchmarks/baseline-i2.md`, top-5 hotspot identificati | ✅ Done |
| I.3 | Allocation optimizations — cache key-name transform, direct scans, accumulate-in-place; misurato 21–28% miglioramento | ✅ Done |
| I.4 | _(Pianificato — dettagli da definire)_ | ⏳ Pending |
| I.5 | Benchmark regression CI — `benchmarks.yml`: esegue `baseline check i2-baseline` su ogni PR, posta markdown comparison, warning non-bloccanti, artifact 30gg | ✅ Done |

---

## Pillar II — Streaming Layer

| Item | Descrizione | Stato |
|---|---|---|
| II.1 | **XMLStreamParser** — SAX parser sync/async, reusa `XMLTreeParser.Configuration`, tutti i security limits | ✅ Done |
| II.2 | **XMLStreamEncoder** — `Encodable → [XMLStreamEvent]` (sync) + `AsyncThrowingStream` (macOS 12+), thin bridge su `XMLEncoder.encodeTree()` | ✅ Done |
| II.3 | **XMLStreamWriter** — `Sequence/AsyncSequence<XMLStreamEvent> → Data`, pretty-print, `expandEmptyElements`, output limits | ✅ Done |
| II.4 | **XMLStreamDecoder** — `[XMLStreamEvent] → Decodable` via stack `_XMLTreeElementBox` + `XMLDecoder.decodeTree()` | ✅ Done |
| II.5 | **Real IO** — `XMLStreamParser+IO.swift` (InputStream push parser + `AsyncSequence<UInt8>`), `XMLStreamWriter+IO.swift` (OutputStream delta-tracking + chunked async) | ✅ Done |
| II.6 | **Event-Cursor Decoder** — sostituisce `buildDocument → XMLTreeDocument` con decoder diretto su `[XMLStreamEvent]`; zero allocazioni nodi intermedi; forward-cursor per XML ordinato | ✅ Done |
| II.7 | **encodeEach** — `XMLStreamEncoder.encodeEach(AsyncSequence)` per DB cursor / feed; 3 overload: core + default + `wrappedIn` convenience | ⏳ Pending — piano: `encode-each-async.md` |

### Streaming layer: roadmap dettagliata

→ Vedi [streaming-layer-roadmap.md](streaming-layer-roadmap.md) per dipendenze e sequenza.

---

## Pillar III — Quality & Testing

| Item | Descrizione | Stato |
|---|---|---|
| III.1 | **Fuzz testing** — `FuzzTests/` SPM package con `FuzzXMLParser` + `FuzzXMLDecoder` (libFuzzer), seed corpus 5 XML, `run_fuzzer.sh`, CI nightly `fuzz.yml` (120s, Ubuntu 22.04, Swift 6.1, ASan) | ✅ Done |
| III.2 | **Concurrency stress tests** — 11 test GCD + structured concurrency; job TSan in CI (`-sanitize=thread`) | ✅ Done |
| III.3 | **Fuzz corpus expansion** — ampliare il corpus con documenti che esercitino namespace, CDATA annidato, DTD, PI, documenti al limite dei security limits | ⏳ Pending |
| III.4 | **Fuzz harness per streaming** — aggiungere harness `FuzzXMLStreamParser` per il push parser e `FuzzXMLStreamDecoder` per il nuovo event-cursor decoder (II.6) | ⏳ Pending (dipende da II.6) |

---

## Pillar IV — Community & Governance

| Item | Descrizione | Stato |
|---|---|---|
| IV.4 | Community infrastructure — `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue templates, PR template | ✅ Done |

---

## Pillar V — _(da definire)_

Non ancora pianificato. Candidati:
- XML Signature canonicalization engines (C14N, EXC-C14N) — POST-XML-2
- Full structural fidelity (PI, doctype in `XMLTreeNode`) — POST-XML-3

---

## Pillar VI — _(da definire)_

Non ancora pianificato. Candidati:
- Security hardening fase 2 (limiti aggiuntivi, preset `untrustedInput`) — POST-XML-4
- Pre-serialization output budgeting (fail early prima di buffer grandi) — POST-XML-5

---

## Pillar VII — Macros & Developer Experience

| Item | Descrizione | Stato |
|---|---|---|
| VII.1 | **`@XMLRootNamespace`** — dichiara namespace default sul root element | ✅ Done |
| VII.2 | **`@XMLIgnore`** — esclude un campo dalla serializzazione XML | ✅ Done |
| VII.3 | **`@XMLText`** — mappa un campo al text content dell'elemento parent | ✅ Done |
| VII.4 | _(Pianificato — dettagli da definire)_ | ⏳ Pending |
| VII.5 | **Source position diagnostics** — `XMLNodeStructuralMetadata.sourceLine: Int?`, errori decode includono `(line N)` | ✅ Done |

---

## Backlog POST-XML (non ancora schedulati)

| ID | Titolo | Note |
|---|---|---|
| POST-XML-2 | XML Signature canonicalization engines | C14N, EXC-C14N via libxml2; candidato Pillar V |
| POST-XML-3 | Full structural fidelity | PI + doctype in `XMLTreeNode`; candidato Pillar V |
| POST-XML-4 | Security hardening fase 2 | Limiti aggiuntivi, fuzzing avanzato; candidato Pillar VI |
| POST-XML-5 | Pre-serialization output budgeting | Candidato Pillar VI |
| POST-XML-8 | MTOM/XOP + SwA multipart | Major feature, transport concern |
| POST-XML-13 | XMLDSig library | Repo separata, dipende da POST-XML-2 |

---

## Sequenza consigliata (Fase 3+)

```
II.6 (event-cursor decoder)  ──┐
                                ├──► commit + CHANGELOG + release 1.3.0
II.7 (encodeEach)            ──┘

III.3 (fuzz corpus expansion)  ──┐
III.4 (fuzz streaming harness) ──┤  (III.4 dipende da II.6)
                                  └──► Fase 4

Pillar V/VI ─────────────────────► definire scope poi pianificare
```
