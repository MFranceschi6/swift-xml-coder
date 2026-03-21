Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [01-current-state.md](./01-current-state.md), [02-target-roadmap.md](./02-target-roadmap.md), [03-ecosystem-topology.md](./03-ecosystem-topology.md), [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md)

# Capability Matrix E Gap Analysis

## Scopo

Confrontare il set di capability attuale con la stop line finale desiderata, mettendo in evidenza dove esistono gap concreti e quale package dovrebbe assorbirli.

## Contesto

Uno stack XML maturo non si misura solo sull'encode/decode di oggetti Swift. Contano anche streaming, fidelity strutturale, integrazione con framework, schema validation, transform e tooling.

## Matrice

| Capability | Current | Target | Home | Priority | Why It Matters |
| --- | --- | --- | --- | --- | --- |
| `Codable` encode/decode | forte e gia' centrale nel core | mantenere e consolidare | `core` | alta | resta il punto di ingresso principale per l'adozione |
| tree model | presente e utile | estendere la fedelta' strutturale | `core` | alta | serve per round-trip, inspectability e tooling |
| XPath | presente | mantenere | `core` | media | utile per ispezione e query locali |
| push streaming | presente nel lavoro locale recente | stabilizzare e chiarire il confine API | `core` | alta | necessario per documenti grandi e pipeline |
| pull/cursor streaming | non ancora first-class nel core | introdurre API pubblica dedicata | `core` | alta | e' una capability standard nei runtime XML maturi |
| item-by-item streaming decode | non ancora first-class | aggiungere decode incrementale | `core` | alta | evita buffering eccessivo in server-side e batch |
| namespace ergonomics | buona ma non esaustiva | rendere il mapping per-field e schema-friendly | `core` | alta | i modelli reali XML vivono di namespace e QNames |
| diagnostics/location | buona ma migliorabile | aggiungere line, column, offset e path dove sensato | `core` | media | migliora debug, validation e DX |
| PI/doctype fidelity | incompleta nel modello pubblico | completare il round-trip | `core` | media | necessaria per credibilita' come libreria XML completa |
| schema validation | assente come prodotto ufficiale | aggiungere XSD parse e validation | `satellite` | alta | requisito classico per casi enterprise e schema-first |
| XSLT | assente | aggiungere modulo ufficiale separato | `satellite` | media | utile per workload XML tradizionali e interoperabilita' |
| DSig/C14N | assente come modulo completo | aggiungere package dedicato | `satellite` | media | necessario per interoperabilita' e use case firmati |
| framework adapters | assenti come prodotti ufficiali | fornire adapter first-party | `satellite` | alta | aiuta l'adozione con Vapor e Hummingbird |
| codegen | assente come prodotto ufficiale | aggiungere pipeline `XSD -> Swift models` | `satellite` | alta | sblocca l'uso schema-first su larga scala |

## Gap Più Importanti Da Colmare

- gap di runtime: pull/cursor API, decode incrementale, maggiore chiarezza sullo streaming reale
- gap di fedelta': PI, doctype e diagnostica piu' ricca
- gap di ecosistema: framework interop, XSD, codegen, XSLT e DSig

## Confronto Pragmatico Con Ecosistemi Di Riferimento

### Java StAX

Riferimento forte per il modello pull/cursor. Il gap principale e' l'assenza di una story equivalente e first-class nel core Swift.

### .NET XmlReader E XmlSchemaSet

Riferimento forte per parsing forward-only e validazione schema. Il gap principale e' la mancanza di un modulo ufficiale schema/validation.

### Go `encoding/xml`

Riferimento utile per ergonomia standard-library e token stream. Il gap principale e' la mancanza di un decoding incrementale percepito come semplice e naturale.

### Rust `quick-xml`

Riferimento utile per performance, streaming e approccio low-level pragmatico. Il gap principale e' offrire primitive altrettanto chiare senza sacrificare la DX Swift.

### Python `lxml`

Riferimento utile per ampiezza di capability, specialmente su XPath, XSLT e validazione. Il gap principale e' la larghezza dell'ecosistema ufficiale, non il solo core runtime.

### Swift `XMLCoder`

Riferimento diretto in ecosistema Swift sul fronte `Codable`. Il differenziale desiderato e' posizionarsi non solo come encoder/decoder, ma come stack XML piu' completo e integrabile.

## Decisioni O Implicazioni

- Le priorita' piu' alte combinano completamento del core e apertura dell'ecosistema, non un semplice accumulo di feature isolate.
- Se una capability ha peso soprattutto di integrazione o standard avanzato, la home corretta tende a essere un satellite.

## Riferimenti

- [README.md](./README.md)
- [01-current-state.md](./01-current-state.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [03-ecosystem-topology.md](./03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](./05-milestones-and-exit-criteria.md)
