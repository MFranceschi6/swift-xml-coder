## Status
- Draft snapshot

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)
- [../streaming-layer-roadmap.md](../streaming-layer-roadmap.md)

# Enterprise XML Roadmap — Current State

## Scopo

Fornire una fotografia esplicita del progetto alla data di questo snapshot, separando:

- stato pubblicato realmente
- stato locale della worktree
- capability attualmente presenti
- quality gates osservati
- debiti strutturali gia' noti

## Contesto

Il repository contiene gia' piani avanzati per streaming, performance e quality, ma alcune
di quelle note descrivono uno stato locale piu' avanzato del baseline pubblico.

Questo documento serve a evitare che i piani futuri partano da un presupposto errato.

## Stato pubblicato verificato

### Release pubbliche

Release pubbliche verificate alla data del documento:

| Versione | Stato | Data |
|---|---|---|
| `1.1.0` | latest pubblica | `2026-03-21` |
| `1.0.0` | pubblica | `2026-03-15` |
| `0.1.0` | tag iniziale | `2026-03-15` |

### Implicazione

Il baseline pubblico da cui partire e' `1.1.0`.

Qualsiasi riferimento locale a `1.2.0+` deve essere trattato come:

- lavoro in corso
- milestone pianificata
- stato locale non ancora pubblicato

Non va trattato come fatto storico gia' rilasciato.

## Stato locale della repository

### Branch locale osservata

Snapshot della worktree al momento dell'analisi:

- branch: `claude/epic-ii1-ii3-streaming`
- sono presenti modifiche locali e file non tracciati legati al layer streaming
- esistono piani locali per `II.6`, `II.7` e per una roadmap enterprise piu' ampia

### Mismatch gia' emerso

Il file [../post-release-roadmap.md](../post-release-roadmap.md), prima dell'allineamento
minimo, trattava `1.2.0` come se fosse gia' rilasciata. Questo non corrispondeva ai tag e
alle release pubbliche realmente disponibili.

## Capability presenti oggi nel core

### Capability solide e gia' pubblicate

- `XMLEncoder` / `XMLDecoder` per mapping `Codable`
- tree model immutabile
- namespace support con `XMLQualifiedName` e `XMLNamespaceResolver`
- XPath su `XMLDocument`
- canonicalization deterministica tramite `XMLCanonicalizer` e `XMLDefaultCanonicalizer`
- macro DX principali su Swift 5.9+
- parser security profile con limiti configurabili
- supporto multi-lane Swift e multi-platform
- test support dedicato

### Capability gia' presenti in workspace locale

Nella worktree locale risultano gia' presenti o in avanzato stato di lavoro:

- `XMLStreamParser`
- `XMLStreamWriter`
- `XMLStreamEncoder`
- `XMLStreamDecoder`
- `XMLStreamParser+IO`
- `XMLStreamWriter+IO`
- `XMLStreamEventDecoder`

Questa parte rende il progetto localmente piu' avanzato del solo baseline pubblico
`1.1.0`, ma non cambia il fatto che la release pubblica verificata resti `1.1.0`.

### Capability mancanti o solo parziali rispetto alla stop line enterprise

- pull/cursor API pubblica stile `XMLStreamReader`
- decode item-by-item realmente streaming
- structural fidelity completa per PI e doctype nel tree model pubblico
- location diagnostica completa con colonna e offset
- namespace/name mapping per-field piu' ricco
- schema validation ufficiale
- code generation ufficiale per XSD
- XSLT ufficiale
- C14N / Exclusive C14N standard-grade e DSig stack ufficiale
- adapter ufficiali per NIO, Vapor e Hummingbird

## Quality gates osservati localmente

### Build

- `swift build -c debug` osservato verde

### Test

- `swift test --enable-code-coverage` osservato verde
- suite eseguita: `514` test
- risultato osservato: `0` failure

### Lint

- `swiftlint lint` osservato senza errori bloccanti
- risultato osservato: `257` warning, `0` serious

### Coverage

Misura locale osservata con `llvm-cov report`:

- total line coverage: `84.85%`
- total region coverage: `78.06%`

### Implicazione sul quality gate

Esiste un workflow quality che dichiara un gate `>= 90%`, ma lo snapshot locale osservato
qui e' inferiore a quel valore. Prima di promuovere il prossimo baseline pubblico, questa
divergenza va chiarita in modo esplicito.

## Debiti principali gia' emersi

### Debito di baseline documentale

- stato locale e stato pubblico non erano allineati nei piani
- mancava una fonte unica di verita' per la roadmap enterprise

### Debito di posizionamento

- il canonicalizer di default del core e' un deterministic normalizer
- non va descritto come equivalente a un engine DSig/C14N standard-grade

### Debito di capability

- manca ancora una storia completa per cursor/pull parsing
- manca una storia completa per schema, transform e signature
- manca la family di package ufficiali per framework interop

### Debito di maintainability

- il core ha warning SwiftLint diffusi, soprattutto nei file grandi e nei container Codable
- esistono aree con coverage piu' bassa del target implicito di quality
- alcuni percorsi async/streaming richiedono ancora chiarezza tra API convenience e API
  realmente streaming

## Decisioni o implicazioni

- Tutta la roadmap futura deve partire dal baseline pubblico `1.1.0`.
- Lo stato locale avanzato e' utile per pianificare la prossima wave, ma non sostituisce
  la cronologia pubblica.
- Prima di dichiarare il progetto "maintenance-only" servono ancora capability aggiuntive
  oltre a quelle gia' presenti oggi.

## Riferimenti

- [README.md](README.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [04-capability-matrix.md](04-capability-matrix.md)
