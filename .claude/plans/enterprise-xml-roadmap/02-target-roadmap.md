Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [03-ecosystem-topology.md](./03-ecosystem-topology.md), [04-capability-matrix.md](./04-capability-matrix.md), [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md), [06-decision-log.md](./06-decision-log.md)

# Roadmap Target

## Scopo

Definire la sequenza primaria di lavoro che porta `swift-xml-coder` e i suoi futuri package satellite alla soglia di un vero stack XML enterprise per Swift.

## Contesto

Il core attuale e' gia' capace sul piano `Codable` e XML runtime, ma il target finale non e' soltanto una buona libreria di encode/decode: e' un ecosistema XML completo, integrabile con framework esterni e credibile anche nei casi enterprise e schema-first.

## Definizione Di Enterprise XML Stack

Per questo progetto, `enterprise XML stack` significa:

- core runtime affidabile per parsing, serializzazione, tree model, namespace e `Codable`
- API low-level e streaming sufficienti per documenti grandi e pipeline server-side
- integrazione semplice con runtime esterni come Vapor e Hummingbird senza contaminare il core
- supporto ufficiale a schema, validazione e code generation in package dedicati
- supporto ufficiale a transform e digital signature in package dedicati, con boundary chiaro rispetto al core

## Fase 1 - Core Completeness

### Obiettivo

Completare il core XML fino a una soglia in cui il package principale sia percepito come solido e coerente anche senza i package satellite.

### Output Attesi

- chiarimento netto del confine tra API streaming reali e API convenience
- maggiore fedelta' strutturale del modello XML
- migliore ergonomia per namespace, mapping e diagnostica
- documentazione aggiornata sul baseline pubblico e sulle capability reali

### Resta Nel Core

- tree model
- `Codable` XML
- namespace
- XPath
- canonicalization del core
- parser e writer streaming di base
- macro e property wrappers XML

### Va In Satellite

- nessun package nuovo obbligatorio in questa fase

### Dipendenze

- allineamento con lo stato attuale documentato in [01-current-state.md](./01-current-state.md)
- chiarimento delle decisioni bloccate in [06-decision-log.md](./06-decision-log.md)

### Criterio Di Completamento

Il core offre un set coerente di capability XML senza gap macroscopici nel runtime di base e senza ambiguita' sul significato delle API pubbliche.

## Fase 2 - Pull Cursor API E Item Streaming

### Obiettivo

Rendere il runtime competitivo anche per workload grandi o selettivi, affiancando alle API push una storia pull/cursor e item-by-item piu' completa.

### Output Attesi

- `XMLStreamReader` o equivalente API pull/cursor pubblica
- decode item-by-item da stream grandi
- migliore story di cancellation, backpressure e selective decoding

### Resta Nel Core

- primitive parsing e writer streaming
- `XMLStreamReader`
- decode item-by-item del runtime

### Va In Satellite

- niente in questa fase, salvo benchmark o harness separati se diventano troppo specialistici

### Dipendenze

- fase 1 consolidata
- capability matrix aggiornata

### Criterio Di Completamento

Il core supporta in modo chiaro sia parsing push sia parsing pull/cursor, oltre al consumo incrementale di payload grandi.

## Fase 3 - Framework Interop

### Obiettivo

Offrire integrazione ufficiale con stack server-side diffusi senza caricare il core di dipendenze framework-specifiche.

### Output Attesi

- package `swift-xml-nio`
- adapter `swift-xml-vapor`
- adapter `swift-xml-hummingbird`
- esempi e test end-to-end request/response

### Resta Nel Core

- API framework-neutral
- tipi base e primitive di serializzazione/parsing

### Va In Satellite

- bridge NIO
- integration helpers per Vapor
- integration helpers per Hummingbird

### Dipendenze

- fase 2 disponibile
- topologia package bloccata in [03-ecosystem-topology.md](./03-ecosystem-topology.md)

### Criterio Di Completamento

Un utente puo' integrare XML request/response in Vapor o Hummingbird tramite adapter first-party senza introdurre dipendenze framework-specifiche nel core.

## Fase 4 - Schema E Validation

### Obiettivo

Portare lo stack oltre il solo encode/decode e coprire la validazione schema-first.

### Output Attesi

- parser XSD
- `XMLSchemaSet`
- validazione documento contro XSD
- resource resolution controllata

### Resta Nel Core

- nessuna logica schema complessa

### Va In Satellite

- `swift-xml-schema`

### Dipendenze

- modello di topologia ecosistema stabile
- diagnostica e namespace del core sufficientemente mature

### Criterio Di Completamento

Esiste un package schema dedicato che consente parsing XSD e validazione documentale con diagnostica credibile.

## Fase 5 - Codegen

### Obiettivo

Offrire il percorso ufficiale `XSD -> Swift models` orientato a `swift-xml-coder`.

### Output Attesi

- CLI o plugin SPM per code generation
- naming policy
- namespace mapping coerente
- validazione di output tramite golden tests e compile tests

### Resta Nel Core

- nessun engine di generazione codice

### Va In Satellite

- `swift-xml-codegen`

### Dipendenze

- `swift-xml-schema`
- capability namespace e diagnostica consolidate

### Criterio Di Completamento

L'ecosistema fornisce un percorso ufficiale e ripetibile per generare modelli Swift a partire da XSD.

## Fase 6 - XSLT

### Obiettivo

Aggiungere trasformazioni XML standard dove ha senso farlo senza snaturare il core.

### Output Attesi

- package `swift-xml-xslt`
- wrapping o integrazione controllata con motore XSLT affidabile
- story chiara per include, import e resource resolution

### Resta Nel Core

- trasformazioni XML semplici gia' pertinenti al core, se presenti

### Va In Satellite

- motore XSLT e relativa integrazione

### Dipendenze

- schema e resource resolution gia' pensati in ottica shared concerns

### Criterio Di Completamento

Esiste un modulo ufficiale per eseguire trasformazioni XSLT senza espandere il perimetro del core runtime.

## Fase 7 - DSig E C14N

### Obiettivo

Separare in modo esplicito la normalizzazione del core dalle esigenze di interoperabilita' XML Digital Signature.

### Output Attesi

- package `swift-xml-dsig`
- supporto a C14N standard-grade
- exclusive canonicalization e helper digest/signature
- fixture di interoperabilita' esterna

### Resta Nel Core

- canonicalizer interno come normalizzatore del modello corrente

### Va In Satellite

- XML Digital Signature
- canonicalization standard-grade per DSig

### Dipendenze

- topologia ecosistema bloccata
- decisione esplicita su canonicalization vs DSig registrata in [06-decision-log.md](./06-decision-log.md)

### Criterio Di Completamento

La differenza tra canonicalization del core e DSig-grade canonicalization e' resa esplicita sia nel design sia nell'implementazione.

## Decisioni O Implicazioni

- Il core non deve assorbire automaticamente schema, codegen, XSLT o DSig.
- Gli adapter framework devono vivere fuori dal package principale.
- La roadmap ha una forma intenzionalmente incrementale: prima si completa il runtime XML, poi si apre l'ecosistema.

## Riferimenti

- [README.md](./README.md)
- [03-ecosystem-topology.md](./03-ecosystem-topology.md)
- [04-capability-matrix.md](./04-capability-matrix.md)
- [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md)
- [06-decision-log.md](./06-decision-log.md)
