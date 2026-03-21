Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [01-current-state.md](./01-current-state.md), [02-target-roadmap.md](./02-target-roadmap.md), [03-ecosystem-topology.md](./03-ecosystem-topology.md), [04-capability-matrix.md](./04-capability-matrix.md), [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md), [06-decision-log.md](./06-decision-log.md), [../post-release-roadmap.md](../post-release-roadmap.md)

# Enterprise XML Roadmap

## Scopo

Questo pacchetto documentale descrive lo stato attuale, la destinazione architetturale e la sequenza di lavoro necessaria per trasformare `swift-xml-coder` in un ecosistema XML Swift di riferimento. I file sono scritti in Markdown puro e in forma agent-neutral, in modo che possano essere letti, aggiornati e utilizzati sia da Codex sia da Claude.

## Contesto

Il baseline documentale corretto e' il seguente:

- l'ultima release pubblica verificata e' `1.1.0`, pubblicata il `2026-03-21`
- il lavoro `1.2.0+` esiste come stato locale, backlog o roadmap, ma non deve essere trattato come release pubblicata finche' non esistono tag e release note reali
- la roadmap qui descritta copre sia il core runtime sia i futuri package satellite che compongono uno stack XML piu' ampio

## Ordine Di Lettura Consigliato

1. [01-current-state.md](./01-current-state.md) per riallinearsi ai fatti verificati oggi
2. [02-target-roadmap.md](./02-target-roadmap.md) per capire la sequenza completa del lavoro
3. [03-ecosystem-topology.md](./03-ecosystem-topology.md) per sapere dove deve vivere ogni responsabilita'
4. [04-capability-matrix.md](./04-capability-matrix.md) per valutare gap, priorita' e differenze rispetto ad altri stack XML
5. [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md) per trasformare la roadmap in milestone eseguibili
6. [06-decision-log.md](./06-decision-log.md) per evitare di riaprire decisioni gia' prese

## File Del Pacchetto

| File | Uso Principale | Quando Consultarlo |
| --- | --- | --- |
| [01-current-state.md](./01-current-state.md) | fotografia del presente | quando serve confermare cosa esiste davvero oggi |
| [02-target-roadmap.md](./02-target-roadmap.md) | roadmap master | quando si pianifica la sequenza futura |
| [03-ecosystem-topology.md](./03-ecosystem-topology.md) | confini core vs satellite | quando si decide dove implementare una capability |
| [04-capability-matrix.md](./04-capability-matrix.md) | gap analysis | quando si prioritizzano le prossime iniziative |
| [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md) | milestone e stop condition | quando si converte la roadmap in lavoro operativo |
| [06-decision-log.md](./06-decision-log.md) | decisioni bloccate o aperte | quando un agente deve verificare se una scelta e' gia' stata presa |
| [../post-release-roadmap.md](../post-release-roadmap.md) | ponte con la roadmap post-release gia' esistente | quando si parte dal piano storico e si vuole entrare nella roadmap enterprise |

## Glossario

- `core`: il package principale `swift-xml-coder`, focalizzato su parsing, tree model, `Codable`, namespace, XPath, security presets, macro XML e primitive streaming
- `satellite`: un package separato che dipende dal core e aggiunge una capability specialistica o un adattatore di integrazione
- `maintenance-only`: stato in cui il perimetro definito e' considerato completo e il lavoro diventa prevalentemente manutenzione, hardening e compatibilita'
- `stop condition`: insieme di criteri misurabili che stabiliscono quando il core o l'ecosistema hanno raggiunto la soglia maintenance-only

## Decisioni O Implicazioni

- Questo pacchetto e' la fonte primaria per la visione di medio-lungo termine.
- Il file `post-release-roadmap.md` resta utile come ponte storico e operativo, ma non sostituisce questa roadmap enterprise.
- Le decisioni su release pubblicate, topologia dell'ecosistema e stop condition devono essere mantenute coerenti in tutti i file collegati.

## Riferimenti

- [01-current-state.md](./01-current-state.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [03-ecosystem-topology.md](./03-ecosystem-topology.md)
- [04-capability-matrix.md](./04-capability-matrix.md)
- [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md)
- [06-decision-log.md](./06-decision-log.md)
- [../post-release-roadmap.md](../post-release-roadmap.md)
