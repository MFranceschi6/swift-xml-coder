# Streaming Layer — Roadmap

Traccia l'evoluzione del layer streaming di SwiftXMLCoder dopo il rilascio 1.2.0.
Ogni voce punta al piano dettagliato; qui si tiene solo stato, dipendenze e priorità.

---

## Panoramica

```
XMLStreamParser ──parse──► [XMLStreamEvent] ──decode──► T: Decodable
                                  ▲
                             XMLStreamEncoder
                          encode(T: Encodable)
                          encodeEach(S: AsyncSeq)   ← (pianificato)
                                  │
                               [XMLStreamEvent]
                                  │
                           XMLStreamWriter ──write──► Data / OutputStream / chunks
```

---

## Step completati

### Step 1 — Streaming Codable + Real IO
**Piano:** `replicated-gliding-pudding.md` (archivio)
**Branch:** `claude/epic-ii1-ii3-streaming`
**Stato:** ✅ Completo (502 test, build + lint verdi)

| Componente | Descrizione |
|---|---|
| `XMLStreamEncoder` | `Encodable → [XMLStreamEvent]` via tree-walk |
| `XMLStreamDecoder` | `[XMLStreamEvent] → Decodable` via stack + `XMLDecoder` |
| `XMLStreamParser+IO` | `InputStream` push parser + `AsyncSequence<UInt8>` |
| `XMLStreamWriter+IO` | `OutputStream` delta-tracking + `AsyncThrowingStream<Data>` chunked |

**Limite noto (corretto negli step successivi):**
- `XMLStreamDecoder`: costruisce `XMLTreeDocument` completo prima di decodificare
  → O(n) allocazioni aggiuntive; non sfrutta l'ordine definito dell'XML
- `XMLStreamEncoder.encodeAsync`: materializza l'intero array di eventi prima di yieldarli
  → non utile per sorgenti dati che arrivano in streaming

---

## Step pianificati

### Step 2 — Event-Cursor Decoder
**Piano:** [`event-cursor-decoder.md`](event-cursor-decoder.md)
**Dipendenze:** Step 1 completato ✅
**Priorità:** Alta

Sostituisce il pipeline `buildDocument → XMLTreeDocument → XMLDecoder` con un `Decoder`
custom che opera direttamente su `[XMLStreamEvent]` tramite indice.

| Problema risolto | Come |
|---|---|
| Allocazione albero intermedio O(n) | Nessun `XMLTreeNode` allocato — solo indice `[String: [EventRange]]` |
| Accesso sequenziale inefficiente | Index build con una sola passata forward; per XML ordinato l'index è consultato in ordine → zero backtracking nella pratica |
| Attributi vs elementi | Estratti dal `.startElement` in dict `[String: String]`; rispetta `nodeDecodingStrategy` |

**File nuovi:**
- `Sources/SwiftXMLCoder/XMLStreamEventDecoder.swift`
- `Tests/SwiftXMLCoderTests/XMLStreamEventDecoderTests.swift`

**File modificati:**
- `Sources/SwiftXMLCoder/XMLStreamDecoder.swift` — `decodeImpl` usa il nuovo decoder; rimosse `buildDocument` e `popElement`

---

### Step 3 — encodeEach per AsyncSequence
**Piano:** [`encode-each-async.md`](encode-each-async.md)
**Dipendenze:** Step 1 completato ✅ (Step 2 indipendente — parallelizzabile)
**Priorità:** Alta

Aggiunge a `XMLStreamEncoder` la capacità di codificare una sorgente asincrona di
elementi `Encodable` emettendo eventi man mano che arrivano.

| Caso d'uso | API |
|---|---|
| Solo item, nessun wrapper | `encodeEach(cursor)` |
| Wrapper automatico | `encodeEach(cursor, wrappedIn: "Items")` |
| Struttura custom | `encodeEach(cursor, preamble:, postamble:)` |
| Encoding custom per item | `encodeEach(cursor, ..., encodeItem: { ... })` |

**File nuovi:**
- `Sources/SwiftXMLCoder/XMLStreamEncoder+Sequence.swift`
- `Tests/SwiftXMLCoderTests/XMLStreamEncoderSequenceTests.swift`

---

## Sequenza consigliata

```
Step 1 ✅
    ├── Step 2 (event-cursor decoder)   → migliora decode memory + allocazioni
    └── Step 3 (encodeEach)             → aggiunge encode streaming
             ↓
        (commit, CHANGELOG, release)
```

Step 2 e Step 3 sono **indipendenti** — possono essere sviluppati in parallelo o in
qualsiasi ordine. Step 2 cambia internals del decoder (nessun cambio API pubblica).
Step 3 aggiunge API nuova (nessun breaking).

---

## Step futuri (backlog, non pianificati)

| ID | Titolo | Note |
|---|---|---|
| POST-XML-2 | XML Signature canonicalization | C14N via libxml2 |
| POST-XML-3 | Structural fidelity (PI, DTD, doctype) | Richiede estensione `XMLTreeNode` |
| POST-XML-4 | Security hardening phase 2 | Limiti aggiuntivi, fuzzing |
| POST-XML-5 | `XMLStreamEncodable` protocol | Encoding async di tipi con sotto-parti async; solo dopo raccolta use case reali |