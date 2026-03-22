Status: Active
Last Updated: 2026-03-22
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

Nota operativa: il lavoro XML-R2 e XML-R3 esiste come commit locali su `main` (non ancora taggato). La prossima release pubblica sara' `1.3.0` o superiore quando verranno creati tag e release notes reali.

## Milestone Locali Completate (Non Ancora Rilasciate)

| Milestone | Commit | Contenuto |
| --- | --- | --- |
| XML-R2 — PI/Doctype/Comment fidelity | `e9bdb6d` | `XMLProcessingInstruction`, `XMLDoctype`, `XMLComment` in tree model |
| XML-R2 — Namespace ergonomics per field | `3f26da8` | `XMLFieldNamespaceProvider` + `@XMLFieldNamespace` macro |
| XML-R2 — Diagnostics | `9c3505c` | `XMLParsingError.decodeFailed` + `XMLSourceLocation` |
| XML-R2 — Streaming DocC | `8cc331e` | Streaming.md aggiornato con push/pull boundary, selective extraction |
| XML-R3 — Pull cursor + item decode | `980eab0` | `XMLEventCursor`, `XMLItemDecoder`, 14 nuovi test |

## Stato Core: Maintenance-Only

Il core soddisfa tutti i criteri della stop condition enterprise:

- ✅ runtime XML generale credibile (tree model, namespace, XPath, Codable, macro)
- ✅ story streaming di base (push callback + AsyncSequence)
- ✅ pull/cursor API (`XMLEventCursor`) e item streaming (`XMLItemDecoder`)
- ✅ fidelity strutturale (PI, doctype, comment)
- ✅ diagnostica (source location, coding path)
- ✅ integrazione con framework esterni non richiede cambiare il core

## Stato Dei Quality Gates Locali (2026-03-22)

- `swift build -c debug`: verde
- `swift test --enable-code-coverage`: verde, 535 test, 0 fallimenti
- `swiftlint lint`: verde, 0 errori

## Debiti Minori Residui

- `column` e `byteOffset` di `XMLSourceLocation` sono sempre `nil` (richiede SAX-level instrumentation futura)
- warning SwiftLint pre-esistenti nella repo (non critici, 0 errori)

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
