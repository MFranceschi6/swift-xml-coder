## Status
- Draft

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [01-current-state.md](01-current-state.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [04-capability-matrix.md](04-capability-matrix.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)
- [06-decision-log.md](06-decision-log.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)

# Enterprise XML Roadmap — Entry Point

## Scopo

Questo pacchetto documentale raccoglie in un solo posto la pianificazione end-to-end di
SwiftXMLCoder come ecosistema XML di livello enterprise.

L'obiettivo non e' descrivere una singola release, ma fornire una base condivisa e
agent-neutral per:

- orientamento sullo stato reale del progetto
- allineamento tra roadmap del core e futuri progetti satelliti
- pianificazione incrementale di milestone successive
- riduzione delle fonti di verita' duplicate tra sessioni e tra agenti

## Contesto

La repository contiene gia' diversi piani tecnici focalizzati soprattutto sulla fase
post-1.0 e sul layer streaming. Questi documenti restano validi come piani di dettaglio,
ma non bastano da soli a descrivere:

- la differenza tra stato pubblicato e stato solo locale
- la topologia completa dell'ecosistema XML futuro
- la soglia finale per poter dire "ora il progetto si mantiene e basta"

Questo pacchetto colma quel vuoto senza sostituire i piani tecnici gia' utili.

## Baseline del progetto

- Ultima release pubblica verificata: `1.1.0`
- Data release pubblica verificata: `2026-03-21`
- I riferimenti a `1.2.0+` presenti in alcuni piani locali vanno letti come stato di
  pianificazione o lavoro locale, non come release gia' pubblicate
- La roadmap qui descritta assume una topologia `core + satellites`

## Ordine di lettura raccomandato

1. Leggere [01-current-state.md](01-current-state.md) per capire il baseline reale.
2. Leggere [02-target-roadmap.md](02-target-roadmap.md) per la sequenza strategica.
3. Leggere [03-ecosystem-topology.md](03-ecosystem-topology.md) per sapere dove vive cosa.
4. Leggere [04-capability-matrix.md](04-capability-matrix.md) per il gap analysis.
5. Leggere [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md) per
   la sequenza eseguibile.
6. Consultare [06-decision-log.md](06-decision-log.md) prima di riaprire decisioni gia'
   bloccate.

## Contenuto del pacchetto

| File | Ruolo | Quando usarlo |
|---|---|---|
| `README.md` | Entry point unico | All'inizio di ogni nuova sessione di roadmap |
| `01-current-state.md` | Fotografia del presente | Quando serve evitare assunzioni sbagliate sul baseline |
| `02-target-roadmap.md` | Documento master della roadmap | Quando si decide la direzione di medio-lungo termine |
| `03-ecosystem-topology.md` | Confini tra core e satelliti | Quando bisogna decidere dove implementare una capability |
| `04-capability-matrix.md` | Gap analysis per capability | Quando si valuta se una funzione manca davvero o no |
| `05-milestones-and-exit-criteria.md` | Sequenza operativa | Quando si deve trasformare la roadmap in tranche di lavoro |
| `06-decision-log.md` | Registro decisioni | Quando si vuole capire cosa e' gia' stato deciso e perche' |

## Glossario

### Core

`swift-xml-coder`, cioe' il package/runtime principale. Deve restare stabile, piccolo
quanto basta, framework-neutral e orientato alle primitive XML generali.

### Satellite

Un package o repository separato che estende il core per un dominio specifico, per esempio
schema validation, code generation, NIO interoperability, XSLT o XML Digital Signature.

### Maintenance-only

Stato obiettivo in cui il core e l'ecosistema ufficiale hanno completato il set di
capability considerate essenziali. Da quel momento il lavoro prevalente diventa:

- manutenzione ordinaria
- bug fix
- aggiornamenti compatibilita'
- miglioramenti incrementali non strutturali

### Stop condition

L'insieme esplicito delle condizioni che devono essere vere prima di dichiarare il progetto
"completo abbastanza" per entrare in una fase di sola manutenzione.

## Decisioni e implicazioni

- Questo pacchetto documentale e' la fonte primaria per il planning strategico XML.
- I piani tecnici preesistenti restano validi come approfondimenti di singole milestone.
- Non viene introdotta una cartella `.Codex/` parallela per evitare duplicazione.

## Riferimenti

- [01-current-state.md](01-current-state.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)
