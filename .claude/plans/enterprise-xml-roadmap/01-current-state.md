Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [02-target-roadmap.md](./02-target-roadmap.md), [04-capability-matrix.md](./04-capability-matrix.md), [06-decision-log.md](./06-decision-log.md), [../post-release-roadmap.md](../post-release-roadmap.md)

# Stato Attuale

## Scopo

Separare i fatti verificati oggi dalla roadmap futura, in modo che la pianificazione non parta da assunzioni errate sullo stato della repository o delle release pubbliche.

## Contesto

La repo contiene gia' un core XML solido, ma i materiali locali di roadmap e alcune iniziative future possono facilmente essere confusi con release gia' pubblicate. Questo file fissa il baseline di partenza.

## Release Pubbliche Verificate

| Versione | Data | Stato |
| --- | --- | --- |
| `1.1.0` | `2026-03-21` | ultima release pubblica verificata |
| `1.0.0` | precedente alla `1.1.0` | disponibile nella storia pubblica |

Nota operativa: ogni riferimento a `1.2.0+` va trattato come locale, pianificato o in sviluppo finche' non esiste un tag pubblico accompagnato da release notes reali.

## Stato Locale E Mismatch Da Tenere A Mente

- La branch locale puo' contenere lavoro oltre `1.1.0`, inclusi piani, changelog in avanzamento e funzionalita' non ancora pubblicate.
- I documenti di pianificazione possono menzionare `1.2.0` come obiettivo o milestone locale; questo non equivale a una release online.
- La fonte di verita' per la roadmap futura e' il pacchetto `enterprise-xml-roadmap`, mentre la fonte di verita' per lo stato pubblicato resta la release history reale.

## Capability Presenti Oggi Nel Core

- encode/decode XML basato su `Codable`
- tree model XML con metadata strutturali e supporto namespace
- query `XPath`
- canonicalization e trasformazioni XML di base
- macro e property-wrapper per mapping XML ergonomico
- parser e writer streaming/event-driven gia' presenti nel lavoro locale piu' recente
- security limits e configurazioni di parser hardening
- supporto multi-manifest e compatibilita' Linux del runtime

## Stato Dei Quality Gates Osservato Localmente

Ultimo riscontro locale noto su questa linea di lavoro:

- `swift build -c debug`: verde
- `swift test --enable-code-coverage`: verde
- `swiftlint lint`: verde come exit code, con warning repo-wide esistenti
- test osservati in verde: `514`

Osservazione sulla coverage:

- esiste una cultura di coverage e reporting forte nella repo, ma la copertura non e' ancora sintetizzata qui come singolo valore stabile di prodotto
- i futuri piani devono continuare a distinguere tra gate locale, report CI e obiettivo di copertura

## Debiti Principali Gia' Emersi

- il baseline documentale e' facile da fraintendere senza un richiamo esplicito a `1.1.0` come ultima release pubblicata
- serve una distinzione piu' netta tra API veramente streaming e API convenience che possono bufferizzare
- il core non espone ancora tutto il set di capability che uno stack XML enterprise normalmente copre
- alcune responsabilita' future devono essere tenute fuori dal core per evitare che `swift-xml-coder` diventi monolitico
- la canonicalization del core va comunicata come normalizzazione deterministica del modello corrente, non come sostituto implicito di XML-DSig grade canonicalization

## Decisioni O Implicazioni

- Ogni nuova roadmap deve partire da `1.1.0` come baseline pubblico.
- Le iniziative `1.2.0+` devono essere descritte come locali o pianificate finche' non vengono pubblicate.
- Le capability future vanno valutate rispetto a una topologia `core + satellites`, non assumendo un singolo repository monolitico.

## Riferimenti

- [README.md](./README.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [04-capability-matrix.md](./04-capability-matrix.md)
- [06-decision-log.md](./06-decision-log.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)
