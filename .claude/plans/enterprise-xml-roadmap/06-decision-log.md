Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [02-target-roadmap.md](./02-target-roadmap.md), [03-ecosystem-topology.md](./03-ecosystem-topology.md), [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md), [../post-release-roadmap.md](../post-release-roadmap.md)

# Decision Log

## Scopo

Registrare le decisioni gia' prese o intenzionalmente bloccate, cosi' da evitare che agenti diversi riaprano gli stessi temi a ogni nuova sessione.

## Contesto

Questa roadmap copre un arco lungo di evoluzione. Alcune scelte di perimetro e packaging devono quindi essere esplicite fin dall'inizio.

## Decisioni

| Data | Decisione | Rationale | Impatto | Stato |
| --- | --- | --- | --- | --- |
| `2026-03-21` | adottare topologia `core + satellites` | consente di mantenere il core piccolo, stabile e framework-neutral | guida ogni decisione futura su package e confini | `locked` |
| `2026-03-21` | WSDL e SOAP non fanno parte della stop line XML | sono concern di protocollo e transport, non del runtime XML generale | evita di gonfiare il core e la roadmap enterprise | `locked` |
| `2026-03-21` | `swift-xml-coder` resta framework-neutral | il core deve poter servire piu' stack senza dipendere da uno specifico framework | Vapor e Hummingbird vanno trattati via adapter satellite | `locked` |
| `2026-03-21` | l'obiettivo finale e' un `enterprise XML stack` | il posizionamento non e' solo encode/decode, ma un ecosistema XML completo | orienta roadmap, capability matrix e stop condition | `locked` |
| `2026-03-21` | canonicalization del core e DSig standard-grade non sono la stessa cosa | la normalizzazione interna del modello non basta a sostituire XML Digital Signature interoperabile | DSig e C14N avanzata vanno in un package dedicato | `locked` |
| `2026-03-21` | la documentazione condivisa vive sotto `.claude/plans/` ma resta agent-neutral | si evita una doppia fonte di verita' pur mantenendo compatibilita' con gli strumenti esistenti | Codex e Claude leggono gli stessi file | `locked` |
| `2026-03-21` | il baseline pubblico da usare nei piani e' `1.1.0` | alcuni piani locali possono menzionare release future non ancora pubblicate | impedisce di trattare `1.2.0+` come gia' online | `locked` |
| `2026-03-22` | il backend Swift puro copre solo lo strato streaming (SAX/`XMLStreamEvent`), non DOM né XPath | Foundation.XMLParser su Linux è già backed da libxml2 e non è puro Swift; un parser SAX Swift risolve solo WASM/embedded; rimpiazzare DOM+XPath sarebbe un progetto dell'ordine di grandezza di libxml2 | `swift-xml-pure` è un satellite streaming-only, il core resta su libxml2 per DOM/XPath | `locked` |

## Questioni Da Riaprire Solo Se Servono

- naming finale dei package satellite, se emergono vincoli di branding o disponibilita'
- livello minimo di supporto che `swift-xml-xslt` e `swift-xml-dsig` devono offrire nella loro prima release
- eventuale separazione tra repository multipli e monorepo logico di ecosistema

## Decisioni O Implicazioni

- Prima di creare un nuovo piano o un nuovo epic, conviene verificare qui se il perimetro e' gia' stato deciso.
- Se una decisione viene cambiata, va aggiornata qui e nei documenti collegati nella stessa sessione.

## Riferimenti

- [README.md](./README.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [03-ecosystem-topology.md](./03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)
