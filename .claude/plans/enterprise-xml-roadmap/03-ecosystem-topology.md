Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [README.md](./README.md), [02-target-roadmap.md](./02-target-roadmap.md), [04-capability-matrix.md](./04-capability-matrix.md), [06-decision-log.md](./06-decision-log.md)

# Topologia Dell'Ecosistema

## Scopo

Stabilire una volta sola dove devono vivere le capability future, per evitare discussioni ripetute su cosa appartiene al core e cosa invece va estratto in package satellite.

## Contesto

`swift-xml-coder` nasce come runtime XML generico. Per diventare uno stack XML di riferimento senza degenerare in monolite, la crescita deve essere guidata da una topologia esplicita `core + satellites`.

## Package E Repository Previsti

| Nome | Tipo | Responsabilita' | Dipendenze | Non-Goals |
| --- | --- | --- | --- | --- |
| `swift-xml-coder` | `core` | parsing, writing, tree model, `Codable`, namespace, XPath, macro XML, security, canonicalization del core | Foundation, libxml2, toolchain Swift supportata | schema validation completa, framework adapters, DSig, XSLT, codegen |
| `swift-xml-nio` | `satellite` | bridge NIO e `ByteBuffer` per il core XML | `swift-xml-coder`, SwiftNIO | tree model alternativo, semantics applicative di framework |
| `swift-xml-vapor` | `satellite` | integrazione Vapor request/response e helpers HTTP | `swift-xml-nio`, Vapor | nuove primitive XML di basso livello |
| `swift-xml-hummingbird` | `satellite` | integrazione Hummingbird request/response e helpers server-side | `swift-xml-nio`, Hummingbird | nuove primitive XML di basso livello |
| `swift-xml-schema` | `satellite` | parser XSD, `XMLSchemaSet`, validation, resource resolution per schema | `swift-xml-coder` | code generation, SOAP transport, stub generation |
| `swift-xml-codegen` | `satellite` | CLI o plugin SPM per `XSD -> Swift models` | `swift-xml-schema`, `swift-xml-coder` | validation runtime completa, framework adapters |
| `swift-xml-xslt` | `future` | supporto XSLT ufficiale con boundary chiaro | `swift-xml-coder` | sostituire il core runtime o inglobare ogni altra transform concern |
| `swift-xml-dsig` | `future` | XML Digital Signature, C14N standard-grade, digest/signature helpers | `swift-xml-coder` | canonicalization generica del core, SOAP transport |
| `swift-soap` o equivalente | `out-of-scope` | WSDL, SOAP envelopes, transport e service layer | puo' dipendere dai package XML ufficiali | diventare parte del core XML |

## Decisioni Bloccate

- WSDL e SOAP sono fuori dal core XML.
- I transport concern sono fuori dal core XML.
- Il canonicalizer default del core non equivale a DSig-grade canonicalization.
- Gli adapter framework devono dipendere dal core, non il contrario.
- Il percorso standard per schema e codegen deve passare da package dedicati.

## Implicazioni Operative

- Una feature nuova entra nel core solo se serve al runtime XML generale.
- Se una capability introduce dipendenze applicative, server-side o standard di livello superiore, va valutata prima come satellite.
- Le decisioni di naming e packaging vanno confrontate con questo file prima di aprire un nuovo epic.

## Riferimenti

- [README.md](./README.md)
- [02-target-roadmap.md](./02-target-roadmap.md)
- [04-capability-matrix.md](./04-capability-matrix.md)
- [06-decision-log.md](./06-decision-log.md)
