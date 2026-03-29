## Status
- Draft decision log

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)

# Enterprise XML Roadmap — Decision Log

## Scopo

Registrare le decisioni gia' prese in modo che sessioni future e agenti diversi non
riaprano continuamente le stesse discussioni.

## Contesto

Questo log non sostituisce la roadmap. Serve a congelare decisioni architetturali o di
scope che influenzano piu' milestone.

## Decisioni

| ID | Decisione | Rationale | Impatto | Data | Stato |
|---|---|---|---|---|---|
| `XML-D1` | La topologia target e' `core + satellites` | Riduce il rischio di monolite e mantiene il core stabile | Influenza packaging, scope e ownership delle capability | 2026-03-21 | locked |
| `XML-D2` | WSDL e SOAP non fanno parte della stop line XML | Sono domini sopra l'XML, non parte del core XML generalista | Evita scope creep nel core e nella roadmap enterprise XML | 2026-03-21 | locked |
| `XML-D3` | `swift-xml-coder` resta framework-neutral | Il core deve essere riusabile con piu' stack server | Le integrazioni framework vanno in package satellite | 2026-03-21 | locked |
| `XML-D4` | L'obiettivo finale e' un enterprise XML stack, non solo un miglior encoder/decoder Swift | Serve una stop line piu' alta per poter dire "ora si mantiene" | Introduce validation, codegen, XSLT e DSig nell'ecosistema ufficiale | 2026-03-21 | locked |
| `XML-D5` | La canonicalization del core e la DSig canonicalization standard-grade sono due cose diverse | Evita posizionamento ambiguo del canonicalizer di default | `XMLDefaultCanonicalizer` resta nel core; C14N/DSig vanno in satellite | 2026-03-21 | locked |
| `XML-D6` | La documentazione strategica condivisa vive in `.claude/plans/` ma resta agent-neutral | Si evita duplicazione con una `.Codex/` parallela | Un solo pacchetto documentale condiviso per Codex e Claude | 2026-03-21 | locked |
| `XML-D7` | Il baseline pubblico verificato e' `1.1.0` | E' la release pubblica online verificata alla data del documento | Tutta la roadmap successiva parte da `1.1.0`, non da release locali non pubblicate | 2026-03-21 | locked |

## Decisioni da non riaprire senza nuovo fatto concreto

- Spostare framework interop nel core
- Spostare XSD/codegen nel core runtime
- Trattare il canonicalizer default come DSig-grade
- Usare WSDL/SOAP come criterio per la stop line XML
- Duplicare la documentazione strategica in una seconda cartella agent-specifica

## Revisit policy

Una decisione `locked` puo' essere riaperta solo se emerge almeno uno di questi fattori:

- nuovo vincolo tecnico concreto
- cambiamento di posizionamento prodotto deciso esplicitamente
- costo operativo non sostenibile della topologia attuale
- evidenza ripetuta che la decisione produce attrito significativo

## Decisioni o implicazioni

- Ogni nuovo piano tecnico che contraddice una decisione `locked` dovrebbe citarla
  esplicitamente e spiegare il motivo del cambio.
- Se una decisione va riaperta, il log va aggiornato prima o insieme al nuovo piano.

## Riferimenti

- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)
