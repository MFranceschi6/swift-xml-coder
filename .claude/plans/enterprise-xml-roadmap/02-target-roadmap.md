## Status
- Draft strategic roadmap

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [01-current-state.md](01-current-state.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)

# Enterprise XML Roadmap — Target State

## Scopo

Definire la roadmap master per portare SwiftXMLCoder da libreria XML gia' molto capace a
ecosistema XML enterprise completo abbastanza da entrare poi in una fase di sola
manutenzione.

## Contesto

L'obiettivo finale non e' solo avere un ottimo encoder/decoder XML per Swift.

La soglia voluta e':

- core XML forte
- streaming serio
- interop con framework server Swift
- schema validation e code generation ufficiali
- transform e signature stack ufficiali nell'ecosistema

## Definizione esplicita di "enterprise XML stack"

Per questo progetto, "enterprise XML stack" significa:

- un core runtime stabile e framework-neutral
- primitive tree, streaming push e streaming pull
- supporto namespace e diagnostics robusti
- fidelity strutturale sufficiente per casi XML reali
- validazione schema ufficiale
- code generation ufficiale da XSD
- trasformazioni XML ufficiali via XSLT
- canonicalization e signature stack standard-grade in package ufficiali dedicati
- adapter ufficiali per i framework server Swift principali

Non significa invece:

- inglobare WSDL o SOAP dentro il core
- inglobare i transport layer dentro il core
- trasformare `swift-xml-coder` in un monolite

## Fase 1 — Core Completeness

### Obiettivo

Chiudere il gap tra "ottimo core XML Swift" e "core XML completo abbastanza da non
richiedere altre rifondazioni architetturali".

### Output attesi

- baseline streaming locale pubblicata in modo coerente
- distinzione chiara tra stato pubblico e stato locale nei documenti
- diagnostica sorgente piu' ricca
- structural fidelity estesa per PI e doctype nel modello pubblico
- chiarimento esplicito della boundary del canonicalizer di default

### Cosa resta nel core

- tree model
- document model
- parser e writer
- namespace support
- diagnostics e metadata
- canonicalization boundary

### Cosa va in satellite

- nessuna capability satellite obbligatoria in questa fase

### Dipendenze

- nessuna oltre al lavoro gia' presente nella repository

### Criterio di completamento

Il core espone un modello XML piu' fedele e una diagnostica abbastanza ricca da diventare
base stabile per schema, transform e signature stack futuri.

## Fase 2 — Pull/Cursor API e Item Streaming

### Obiettivo

Aggiungere le primitive low-level che negli stack XML maturi rendono possibile la lettura
selettiva, efficiente e controllata di documenti grandi.

### Output attesi

- `XMLStreamReader` o equivalente cursor API pubblica
- helper di navigation tipo `read()`, `skipSubtree()`, `readElementText()`
- supporto item-by-item decode realmente streaming
- posizione corrente con `line`, `column`, `byteOffset` e metadata utili

### Cosa resta nel core

- cursor API
- item streaming decode
- metadata di location

### Cosa va in satellite

- nessuna capability satellite obbligatoria in questa fase

### Dipendenze

- Fase 1 completata

### Criterio di completamento

Il core copre sia il paradigma push/eventi sia il paradigma pull/cursor, con un percorso
pratico per leggere feed XML grandi senza materializzare tutto.

## Fase 3 — Framework Interop

### Obiettivo

Rendere l'ecosistema XML integrabile in modo naturale con i framework server Swift
principali, senza contaminare il core con dipendenze di framework.

### Output attesi

- package `swift-xml-nio`
- package `swift-xml-vapor`
- package `swift-xml-hummingbird`
- esempi end-to-end request/response
- test e benchmark con body grandi e backpressure

### Cosa resta nel core

- primitive framework-neutral
- nessuna dipendenza su NIO o framework

### Cosa va in satellite

- tutto cio' che dipende da NIO
- bridge request/response framework-specifici

### Dipendenze

- Fase 2 completata

### Criterio di completamento

Esistono adapter ufficiali sottili e testati, ma il core resta indipendente dai framework.

## Fase 4 — Schema / Validation

### Obiettivo

Aggiungere la parte di validazione XML assente oggi: parsing schema, compilazione di schema
set, validazione documento e risoluzione risorse controllata.

### Output attesi

- package `swift-xml-schema`
- `XMLSchemaSet`
- `XMLSchemaValidator`
- model XSD ufficiale
- resource resolver ufficiale con policy sicure e offline-first

### Cosa resta nel core

- al massimo i protocolli o boundary minimi riusabili

### Cosa va in satellite

- parser XSD
- schema compiler
- document validation
- import/include resolution

### Dipendenze

- Fase 1 completata
- consigliata la Fase 2 per una migliore story di diagnostica e streaming

### Criterio di completamento

L'ecosistema supporta validazione XSD reale senza introdurre nel core un carico non
necessario.

## Fase 5 — Codegen

### Obiettivo

Costruire il percorso ufficiale `XSD -> Swift models` orientato a SwiftXMLCoder.

### Output attesi

- package `swift-xml-codegen`
- CLI ufficiale
- plugin SPM ufficiale
- naming policies
- type mapping policies
- field ordering, namespace mapping e validation hooks

### Cosa resta nel core

- niente code generation nel core runtime

### Cosa va in satellite

- IR di codegen
- emitter
- plugin e CLI
- snapshot tests dedicati

### Dipendenze

- Fase 4 completata

### Criterio di completamento

Esiste un percorso ufficiale e mantenibile per generare modelli Swift da XSD senza
trasformare il core in un toolchain package.

## Fase 6 — XSLT

### Obiettivo

Aggiungere un layer ufficiale di trasformazione XML, separato dal core ma parte
dell'ecosistema supportato.

### Output attesi

- package `swift-xml-xslt`
- wrapper chiaro sopra libxslt
- gestione sicura di import/include e resource resolution
- fixture di interoperabilita'

### Cosa resta nel core

- solo i tipi base XML riusabili

### Cosa va in satellite

- tutte le API XSLT
- caching stylesheet
- parameter binding
- transform result handling

### Dipendenze

- Fase 4 consigliata per allineare il resolver delle risorse

### Criterio di completamento

L'ecosistema ufficiale copre il caso d'uso transform senza caricare il core di dipendenze e
concetti non essenziali.

## Fase 7 — DSig / C14N

### Obiettivo

Fornire un percorso ufficiale per canonicalization standard-grade e firma XML senza
confondere il normalizer di default del core con un engine di compliance completa.

### Output attesi

- package `swift-xml-dsig`
- `C14NCanonicalizer`
- `ExclusiveC14NCanonicalizer`
- digest/signature helpers
- fixture standard e test di interoperabilita'

### Cosa resta nel core

- `XMLCanonicalizer` come boundary pubblico
- `XMLDefaultCanonicalizer` come deterministic normalizer

### Cosa va in satellite

- C14N 1.0
- Exclusive C14N
- XML Signature helpers
- policy e test di interoperabilita'

### Dipendenze

- Fase 1 completata
- consigliata la Fase 4 per una migliore story di resolver e diagnostics

### Criterio di completamento

L'ecosistema ha una story ufficiale per XML Signature e canonicalization standard-grade,
senza compromettere la semplicità del core.

## Decisioni o implicazioni

- La roadmap non implica che tutto debba finire nello stesso repository.
- Il core deve restare il foundation runtime dell'ecosistema, non il contenitore di ogni
  capability XML possibile.
- WSDL e SOAP restano deliberatamente fuori da questa roadmap come obiettivi del core XML.

## Riferimenti

- [01-current-state.md](01-current-state.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)
