## Status
- Draft milestone plan

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [04-capability-matrix.md](04-capability-matrix.md)
- [06-decision-log.md](06-decision-log.md)

# Enterprise XML Roadmap — Milestones and Exit Criteria

## Scopo

Tradurre la roadmap strategica in milestone ordinate e con criteri di completamento
misurabili.

## Contesto

Le milestone qui sotto non sono task atomici di implementazione. Sono tranche di lavoro
coerenti che possono poi essere spezzate in piani tecnici piu' dettagliati.

## XML-R1 — Baseline Alignment and Core Publishability

### Scope

- riallineare stato pubblico, piani locali e packaging documentale
- stabilizzare la prossima wave del core streaming da stato locale a stato pubblicabile
- chiarire la boundary del canonicalizer default

### Deliverable attesi

- baseline documentale coerente
- roadmap enterprise agganciata ai piani esistenti
- release successiva del core pubblicata in modo coerente

### Prerequisiti

- nessuno oltre allo stato corrente della repository

### Rischi

- confondere ancora stato locale e stato pubblico
- promuovere come "release" capability solo locali

### Segnali "non pronta"

- i piani continuano a parlare di release non pubblicate come se fossero gia' online
- non c'e' una storia chiara per lo stato del layer streaming

### Exit criteria

- una sola fonte di verita' per baseline pubblico
- milestone streaming locale almeno documentata come pubblicata o come ancora locale
- documentation package enterprise presente e coerente

## XML-R2 — Core XML Completeness

### Scope

- chiudere i principali gap del core non coperti dal solo `Codable`
- aumentare fidelity e diagnostics

### Deliverable attesi

- PI e doctype nel modello pubblico
- location diagnostica completa
- metadata piu' ricchi

### Prerequisiti

- XML-R1 completata

### Rischi

- introdurre complessita' senza un modello pubblico pulito
- rompere la distinzione tra metadata e content model

### Segnali "non pronta"

- impossibilita' di round-trip su PI/doctype
- errori ancora identificabili solo con `line` o con messaggi generici

### Exit criteria

- tree model abbastanza fedele per documenti XML reali
- diagnostics usabili per validation e tooling successivi

## XML-R3 — Pull/Cursor and Item Streaming

### Scope

- introdurre cursor API e item streaming decode

### Deliverable attesi

- `XMLStreamReader` o equivalente
- navigation helpers
- `decodeEach` o equivalente

### Prerequisiti

- XML-R2 completata

### Rischi

- creare una API low-level non ergonomica
- duplicare in modo incoerente il layer event-based esistente

### Segnali "non pronta"

- streaming presente solo come event stream push
- impossibilita' di consumare record grandi uno per volta

### Exit criteria

- il core copre sia push sia pull
- esiste un percorso ufficiale per leggere feed XML grandi record-by-record

## XML-R4 — Framework Interop

### Scope

- creare gli adapter ufficiali lato server Swift

### Deliverable attesi

- `swift-xml-nio`
- `swift-xml-vapor`
- `swift-xml-hummingbird`
- esempi e smoke test end-to-end

### Prerequisiti

- XML-R3 completata

### Rischi

- far entrare dipendenze framework nel core
- creare adapter troppo opinionated

### Segnali "non pronta"

- integrazione Vapor/Hummingbird possibile solo tramite codice ad hoc dell'utente

### Exit criteria

- esistono package ufficiali e testati
- il core resta framework-neutral

## XML-R5 — Schema and Validation

### Scope

- introdurre il validation stack ufficiale

### Deliverable attesi

- `swift-xml-schema`
- `XMLSchemaSet`
- `XMLSchemaValidator`
- resolver risorse controllato

### Prerequisiti

- XML-R2 completata

### Rischi

- allargare troppo il core
- introdurre resolver non sicuri

### Segnali "non pronta"

- manca una story ufficiale per XSD
- validation possibile solo tramite tool esterni o codice custom

### Exit criteria

- esiste un package ufficiale di validation con API e test chiari

## XML-R6 — Codegen

### Scope

- costruire la toolchain ufficiale da XSD a modelli Swift

### Deliverable attesi

- `swift-xml-codegen`
- CLI
- plugin SPM
- policy di naming e mapping ufficiali

### Prerequisiti

- XML-R5 completata

### Rischi

- mischiare codegen generico XML con WSDL/SOAP
- generare API troppo dipendenti da dettagli del momento

### Segnali "non pronta"

- i modelli XSD-first richiedono ancora tool custom o codice manuale pesante

### Exit criteria

- esiste un percorso ufficiale e mantenibile per generare modelli SwiftXMLCoder-first

## XML-R7 — Transform and Signature Ecosystem

### Scope

- completare lo story enterprise con transform e signature stack ufficiali

### Deliverable attesi

- `swift-xml-xslt`
- `swift-xml-dsig`
- canonicalizer standard-grade separati dal core
- fixture di interoperabilita'

### Prerequisiti

- XML-R2 completata
- idealmente XML-R5 completata per una story di resolver piu' robusta

### Rischi

- confondere il normalizer del core con un engine di compliance
- introdurre un satellite signature senza fixture esterne reali

### Segnali "non pronta"

- XSLT e DSig ancora possibili solo via integrazioni ad hoc
- manca una implementazione ufficiale di C14N / Exclusive C14N

### Exit criteria

- l'ecosistema ufficiale copre transform e signature in package dedicati e testati

## Maintenance-Only Stop Condition

### Quando il core si considera completo

Il core `swift-xml-coder` puo' dirsi "maintenance-only" quando:

- supporta tree, document, namespace, XPath e diagnostics mature
- supporta streaming push e pull
- supporta item streaming decode
- ha fidelity sufficiente per PI e doctype
- resta framework-neutral e con confini chiari

### Quando l'ecosistema ufficiale si considera completo

L'ecosistema ufficiale puo' dirsi "maintenance-only" quando, oltre al core, esistono e
sono stabili:

- `swift-xml-nio`
- `swift-xml-vapor`
- `swift-xml-hummingbird`
- `swift-xml-schema`
- `swift-xml-codegen`
- `swift-xml-xslt`
- `swift-xml-dsig`

### Backlog opzionale esplicitamente non bloccante

Le capability seguenti non bloccano la dichiarazione di "maintenance-only":

- WSDL-specific tooling
- SOAP-specific runtime
- transport layer SOAP
- MTOM/XOP
- SwA
- funzionalita' ultra-specialistiche non richieste dal core XML generalista

## Decisioni o implicazioni

- La stop condition e' ecosystem-wide, non solo core-wide.
- Una volta raggiunta, il lavoro principale dovrebbe spostarsi da espansione di scope a
  manutenzione, compatibilita' e bug fixing.

## Riferimenti

- [02-target-roadmap.md](02-target-roadmap.md)
- [04-capability-matrix.md](04-capability-matrix.md)
- [06-decision-log.md](06-decision-log.md)
