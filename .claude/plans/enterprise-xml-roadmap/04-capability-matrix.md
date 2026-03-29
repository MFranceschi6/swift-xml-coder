## Status
- Draft matrix

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [01-current-state.md](01-current-state.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)

# Enterprise XML Roadmap — Capability Matrix and Gap Analysis

## Scopo

Mappare in modo pragmatico cosa c'e' oggi, cosa deve esistere nella stop line finale e
dove quella capability deve vivere.

## Contesto

Questa matrice non e' una checklist di marketing. Serve a rispondere a una domanda molto
semplice:

"manca davvero qualcosa di strutturale prima di poter dire che il progetto entra in sola
manutenzione?"

## Matrice capability

| Capability | Current | Target | Home | Priority | Why it matters |
|---|---|---|---|---|---|
| Codable encode/decode | Forte, pubblica | Mantenuta e rifinita | core | Alta | E' la capability base del progetto |
| Tree model | Forte, pubblica | Structural fidelity piu' completa | core | Alta | Serve come foundation per parser, transform e tooling |
| XPath | Presente e pubblica | Mantenuta, senza rifondazioni | core | Media | Copre query pratiche e document inspection |
| Push streaming | Presente localmente in modo avanzato | Pubblicata e stabilizzata | core | Alta | Necessaria per documenti grandi e pipeline |
| Pull/cursor streaming | Mancante | API pubblica completa | core | Alta | Gli stack maturi offrono sia push sia pull |
| Item-by-item streaming decode | Mancante o solo parziale | Disponibile e robusto | core | Alta | Serve per feed grandi, record stream e server processing |
| Namespace ergonomics | Buona ma parziale | Mapping piu' ricco per-field e per generated models | core | Alta | I casi reali XSD e SOAP-like stressano qui |
| Diagnostics / location | Buona, ma centrata su `sourceLine` | `line + column + offset + path` | core | Alta | Fa la differenza su debugging e validation |
| PI / doctype fidelity | Parziale nel tree model pubblico | Completa | core | Alta | Serve per parlare di XML completo e non solo di subset |
| Security limits / hardening | Buona | Mantenuta e ampliata dove serve | core | Alta | Obbligatoria per input non trusted |
| Deterministic canonicalization | Presente | Chiaramente separata da DSig-grade | core | Media | Utile, ma non deve essere sovravenduta |
| Schema validation | Mancante | Ufficiale | satellite | Alta | E' una capability tipica degli stack enterprise |
| XSD model / schema set | Mancante | Ufficiale | satellite | Alta | Base per validation e codegen |
| XSLT | Mancante | Ufficiale | satellite | Media | Parte importante degli stack XML maturi |
| DSig / C14N | Mancante | Ufficiale | satellite | Media | Necessaria per completare lo story enterprise |
| Framework adapters | Mancanti ufficialmente | Ufficiali | satellite | Alta | Obiettivo esplicito per Vapor e Hummingbird |
| Codegen | Mancante nel mondo XML generale | Ufficiale | satellite | Alta | Serve per XSD-first workflows |

## Gap analysis sintetica

### Gia' forte oggi

- runtime `Codable`
- tree/document API
- namespace fundamentals
- XPath
- security posture
- macro DX di base

### Mancanze piu' importanti nel core

- cursor API pubblica
- item-by-item decode streaming
- fidelity completa di PI e doctype
- diagnostics di location complete
- namespace/name mapping piu' ergonomico

### Mancanze piu' importanti nell'ecosistema

- validation stack
- code generation stack
- XSLT stack
- DSig / C14N stack
- adapters framework ufficiali

## Confronto sintetico con ecosistemi di riferimento

### Java StAX

Riferimento importante perche' distingue in modo netto:

- cursor API
- event API
- factory / plugability

La roadmap target di SwiftXMLCoder dovrebbe convergere almeno sul principio "push + pull",
non solo su un event stream.

Riferimento: [Java StAX](https://docs.oracle.com/en/java/javase/25/docs/api/java.xml/javax/xml/stream/package-summary.html)

### .NET `XmlReader` / `XmlSchemaSet`

Il mondo .NET mostra bene due capability che qui mancano ancora:

- reader forward-only molto ricco
- schema set compilabile e riusabile

Questo e' un benchmark molto utile per definire la stop line enterprise.

Riferimenti:

- [.NET XmlReader](https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-xml-xmlreader)
- [.NET XmlSchemaSet](https://learn.microsoft.com/en-us/dotnet/standard/data/xml/xmlschemaset-for-schema-compilation)

### Go `encoding/xml`

Il package standard Go dimostra quanto sia importante avere:

- token/event API chiara
- encoder/decoder diretti
- escape hatch per custom marshal / unmarshal

SwiftXMLCoder oggi e' gia' piu' ricco di Go su alcune dimensioni, ma deve ancora chiudere
la storia low-level pubblica del reader/cursor.

Riferimento: [Go `encoding/xml`](https://pkg.go.dev/encoding/xml)

### Rust `quick-xml`

`quick-xml` e' utile come riferimento per:

- reader/writer ad alte performance
- streaming StAX-like
- layering con serde

La lesson qui e': il livello low-level efficiente e il livello high-level strutturato
devono convivere bene.

Riferimento: [Rust `quick-xml`](https://docs.rs/quick-xml/latest/quick_xml/)

### Python `lxml`

`lxml` e' un riferimento chiave per l'idea di stack XML "quasi completo":

- tree model
- XPath
- XSLT
- validation

Non e' un modello da copiare 1:1, ma spiega bene perche' XSLT e validation fanno parte
della stop line enterprise.

Riferimento: [Python `lxml`](https://lxml.de/2.1/xpathxslt.html)

### Swift `XMLCoder`

`XMLCoder` resta il riferimento naturale nel solo ecosistema Swift per la parte
`Codable`-centric. SwiftXMLCoder ha gia' differenziatori forti, ma per arrivare al livello
"si mantiene e basta" deve completare il lato ecosystem e low-level XML, non solo il lato
`Codable`.

Riferimento: [Swift `XMLCoder`](https://swiftpackageindex.com/CoreOffice/XMLCoder)

## Decisioni o implicazioni

- La stop line non va misurata solo sulle feature del core runtime.
- Lo scarto reale piu' importante non e' sull'encoder/decoder, ma sulle capability
  low-level e sull'ecosistema ufficiale.

## Riferimenti

- [01-current-state.md](01-current-state.md)
- [03-ecosystem-topology.md](03-ecosystem-topology.md)
- [05-milestones-and-exit-criteria.md](05-milestones-and-exit-criteria.md)
