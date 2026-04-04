## Status
- Draft topology

## Last Updated
- 2026-03-21

## Owner
- Matteo Franceschi
- Shared planning artifact for Codex and Claude

## Related
- [README.md](README.md)
- [02-target-roadmap.md](02-target-roadmap.md)
- [06-decision-log.md](06-decision-log.md)

# Enterprise XML Roadmap — Ecosystem Topology

## Scopo

Definire in modo esplicito la topologia target dell'ecosistema XML, cosi' da evitare che la
stessa decisione venga riaperta ad ogni nuova capability.

## Contesto

L'obiettivo e' un ecosistema XML serio, ma non monolitico. Il principio guida e':

- tenere il core piccolo, stabile e framework-neutral
- spostare nei satelliti le capability specialistiche o dipendenti da tool/framework

## Topologia target

| Nome | Tipo | Responsabilita' | Dipendenze | Non-goals |
|---|---|---|---|---|
| `swift-xml-coder` | core | Runtime XML generale: tree model, `Codable`, namespace, XPath, diagnostics, streaming push/pull, canonicalization boundary | `libxml2`, dipendenze minime di runtime | WSDL, SOAP, transport, schema compiler, XSLT, DSig engine |
| `swift-xml-nio` | satellite | Bridge NIO / `ByteBuffer`, adapter low-level per server-side streaming | `swift-xml-coder`, SwiftNIO | API applicative Vapor/Hummingbird, runtime XML core |
| `swift-xml-vapor` | satellite | Integrazione Vapor: request/response helpers, body parsing/writing, examples | `swift-xml-coder`, `swift-xml-nio`, Vapor | Primitive NIO generiche, logica runtime XML |
| `swift-xml-hummingbird` | satellite | Integrazione Hummingbird: parsing e writing XML per request/response | `swift-xml-coder`, `swift-xml-nio`, Hummingbird | Primitive NIO generiche, logica runtime XML |
| `swift-xml-schema` | satellite | Model XSD, `XMLSchemaSet`, validation, resource resolution controllata | `swift-xml-coder` | Codegen, WSDL, transport |
| `swift-xml-codegen` | satellite | CLI/plugin per generare modelli Swift da XSD orientati a SwiftXMLCoder | `swift-xml-coder`, `swift-xml-schema` | Runtime XML, WSDL client/server generation |
| `swift-xml-xslt` | satellite | Wrapper XSLT ufficiale sopra libxslt con policy sicure e test di interoperabilita' | `swift-xml-coder` | Runtime XML, schema validation, DSig |
| `swift-xml-dsig` | satellite | Canonicalization standard-grade e helper per XML Signature | `swift-xml-coder` | Sostituire il canonicalizer default del core, WSDL/SOAP |

## Confini del core

### Il core deve contenere

- primitive XML generiche
- API tree/document
- API streaming low-level
- diagnostics e metadata
- namespace handling
- `Codable` mapping
- macro DX strettamente XML-oriented

### Il core non deve contenere

- integrazione con framework server
- schema compiler o validation stack completo
- tool CLI di code generation
- transform engine XSLT
- XML Digital Signature engine
- WSDL o SOAP concerns

## Decisioni bloccate

### WSDL / SOAP fuori dal core XML

WSDL, service description e SOAP-specific runtime non fanno parte del core XML ne' della
stop line dell'ecosistema XML generale.

### Transport fuori dal core XML

HTTP transport, NIO glue e framework integration devono restare in package satellite.

### Il canonicalizer default del core non e' DSig-grade

`XMLDefaultCanonicalizer` resta un deterministic normalizer. Le implementazioni
standard-grade di C14N e XML Signature appartengono a un satellite dedicato.

## Implicazioni pratiche

- Una capability va nel core solo se e' una primitiva XML generale.
- Una capability va in satellite se dipende da:
  - framework
  - CLI/plugin
  - standard secondari o specialistici
  - librerie complementari come libxslt
- Se una capability e' dubbia, il default e' non espanderla nel core finche' non emerge una
  motivazione forte e cross-cutting.

## Decisioni o implicazioni

- Questa topologia e' parte della fonte di verita' strategica del progetto.
- Le decisioni di implementazione future dovrebbero citare questo documento prima di
  proporre di allargare il core.

## Riferimenti

- [02-target-roadmap.md](02-target-roadmap.md)
- [04-capability-matrix.md](04-capability-matrix.md)
- [06-decision-log.md](06-decision-log.md)
