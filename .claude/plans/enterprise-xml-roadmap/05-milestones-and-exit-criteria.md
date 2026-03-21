Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [02-target-roadmap.md](./02-target-roadmap.md), [03-ecosystem-topology.md](./03-ecosystem-topology.md), [04-capability-matrix.md](./04-capability-matrix.md), [06-decision-log.md](./06-decision-log.md)

# Milestone E Exit Criteria

## Scopo

Tradurre la roadmap target in una sequenza eseguibile di milestone con criteri di uscita abbastanza chiari da essere riutilizzabili da piu' agenti e sessioni.

## Contesto

La roadmap e' volutamente ampia. Senza milestone e stop condition, il lavoro rischia di trasformarsi in backlog aperto permanente. Questa sezione definisce invece cosa significa davvero completare il core e poi l'ecosistema.

## XML-R1 - Core Baseline Alignment

### Scope

Allineare documentazione, naming e confini del core al baseline pubblico `1.1.0`, chiarendo cosa e' gia' disponibile e cosa resta locale o pianificato.

### Deliverable Attesi

- baseline documentale coerente
- documentazione chiara su release pubblicata vs roadmap futura
- lista debiti core piu' urgenti

### Prerequisiti

- fotografia attuale consolidata

### Rischi

- partire da assunzioni sbagliate sulle release
- roadmap futura costruita su milestone non ancora pubblicate

### Segnali Non Pronta

- file di piano che trattano `1.2.0+` come pubblicata
- mancanza di un entrypoint unico per la roadmap enterprise

### Exit Criteria

- esiste una sola fonte di verita' per il baseline pubblico
- la roadmap enterprise e il piano post-release storico non sono in conflitto

## XML-R2 - Core Completeness

### Scope

Chiudere i gap piu' evidenti del core runtime.

### Deliverable Attesi

- maggiore fedelta' del modello XML
- migliore ergonomia namespace e mapping
- story documentata per canonicalization e diagnostica

### Prerequisiti

- `XML-R1`

### Rischi

- allargare troppo il perimetro del core
- rimandare problemi di fidelity che poi bloccano schema e codegen

### Segnali Non Pronta

- gap ancora aperti su PI/doctype o namespace ergonomics
- confusione persistente su cosa promette il core

### Exit Criteria

- il core copre in modo credibile il runtime XML generale
- i gap rimasti non impediscono l'apertura dell'ecosistema satellite

## XML-R3 - Pull Cursor E Incremental Processing

### Scope

Portare il core a una story streaming completa e chiara.

### Deliverable Attesi

- pull/cursor API pubblica
- decode item-by-item
- comportamento documentato per cancellation e backpressure

### Prerequisiti

- `XML-R2`

### Rischi

- API incompleta o ridondante con quella push
- implementazione percepita come convenience bufferizzata anziche' truly streaming

### Segnali Non Pronta

- assenza di una narrativa semplice per documenti grandi
- difficolta' nel collegare parsing selettivo e `Codable`

### Exit Criteria

- il core espone API push e pull/cursor coerenti
- esiste un percorso incrementale per consumare documenti grandi

## XML-R4 - Framework Interop

### Scope

Costruire l'integrazione ufficiale con stack server-side esterni.

### Deliverable Attesi

- `swift-xml-nio`
- `swift-xml-vapor`
- `swift-xml-hummingbird`
- esempi e test di integrazione

### Prerequisiti

- `XML-R3`
- topologia package bloccata

### Rischi

- contaminare il core con dipendenze framework-specifiche
- creare adapter troppo sottili o non opinionati quanto basta

### Segnali Non Pronta

- mancanza di un bridge NIO comune
- integrazioni duplicate e non allineate tra framework

### Exit Criteria

- esiste un percorso ufficiale e documentato per usare XML con Vapor e Hummingbird

## XML-R5 - Schema Ecosystem

### Scope

Aggiungere parsing XSD e validazione ufficiale tramite package satellite.

### Deliverable Attesi

- `swift-xml-schema`
- `XMLSchemaSet`
- validazione documentale
- resource resolution controllata

### Prerequisiti

- `XML-R2`
- `XML-R3`

### Rischi

- introdurre troppa complessita' troppo presto
- dipendere da un core non ancora abbastanza fedele

### Segnali Non Pronta

- namespace e diagnostica ancora troppo deboli
- confini poco chiari tra schema e codegen

### Exit Criteria

- schema parsing e validation funzionano come capability ufficiale dell'ecosistema

## XML-R6 - Codegen Ecosystem

### Scope

Trasformare il supporto schema-first in un workflow produttivo `XSD -> Swift models`.

### Deliverable Attesi

- `swift-xml-codegen`
- golden tests
- compile tests
- naming e namespace policy esplicite

### Prerequisiti

- `XML-R5`

### Rischi

- generazione codice accoppiata troppo al caso SOAP
- modelli generati difficili da mantenere o stabilizzare

### Segnali Non Pronta

- assenza di schema model abbastanza stabile
- output generato non sufficientemente deterministico

### Exit Criteria

- l'ecosistema offre codegen ufficiale credibile e ripetibile

## XML-R7 - Transform E Signature Ecosystem

### Scope

Completare l'ecosistema ufficiale con XSLT e DSig/C14N standard-grade.

### Deliverable Attesi

- `swift-xml-xslt`
- `swift-xml-dsig`
- fixture di interoperabilita'
- boundary espliciti tra core canonicalization e DSig

### Prerequisiti

- topologia package stabile
- `XML-R5`

### Rischi

- confondere i bisogni di interoperabilita' con il runtime base
- espandere troppo il perimetro del core

### Segnali Non Pronta

- aspettative ancora ambigue sul canonicalizer del core
- mancanza di package dedicati per gli standard avanzati

### Exit Criteria

- lo stack XML ufficiale copre transform e signature tramite package dedicati

## Maintenance-Only Stop Condition

### Quando Il Core Si Considera Completo

Il core `swift-xml-coder` puo' essere trattato come `maintenance-only` quando:

- offre runtime XML generale credibile
- copre tree model, namespace, XPath, `Codable`, macro XML e streaming di base
- espone anche una story pull/cursor e item streaming abbastanza matura
- la fidelity strutturale e la diagnostica non presentano gap bloccanti
- l'integrazione con framework esterni non richiede cambiare il core

### Quando L'Ecosistema Ufficiale Si Considera Completo

L'ecosistema puo' essere trattato come `maintenance-only` quando:

- esistono package ufficiali per interop server-side
- esiste un package schema/validation
- esiste un package codegen
- esistono package dedicati per XSLT e DSig/C14N
- i confini tra core e satellite sono stabili e documentati

### Backlog Opzionale Esplicito

Questi temi non bloccano la stop line maintenance-only:

- WSDL e SOAP transport
- MTOM, XOP o concern transport-specifici
- standard XML specialistici non necessari al posizionamento base dello stack

## Riferimenti

- [README.md](./README.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [03-ecosystem-topology.md](./03-ecosystem-topology.md)
- [04-capability-matrix.md](./04-capability-matrix.md)
- [06-decision-log.md](./06-decision-log.md)
