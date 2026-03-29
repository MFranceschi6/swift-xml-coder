# Piano: XMLStreamEncoder — encodeEach per AsyncSequence

## Obiettivo

Aggiungere a `XMLStreamEncoder` la capacità di codificare una sorgente asincrona di
elementi `Encodable` in un `AsyncThrowingStream<XMLStreamEvent, Error>`, emettendo gli
eventi di ogni elemento man mano che arriva — senza materializzare l'intera sequenza.

Caso d'uso principale: cursore DB, feed di dati, pagine di API. Ogni elemento è già
materializzato quando arriva; il ritmo di arrivo è asincrono.

Nessun nuovo protocollo pubblico. Funziona con `Encodable` standard.

---

## API

### Overload con `encodeItem` custom (massima flessibilità)

```swift
@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    preamble: [XMLStreamEvent] = [],
    postamble: [XMLStreamEvent] = [],
    encodeItem: @Sendable @escaping (T) throws -> [XMLStreamEvent]
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T
```

### Overload senza `encodeItem` (usa `self.encode` con la configurazione corrente)

```swift
@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    preamble: [XMLStreamEvent] = [],
    postamble: [XMLStreamEvent] = []
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T
```

### Convenience: `wrappedIn` (genera preamble/postamble automaticamente)

```swift
@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    wrappedIn elementName: String,
    attributes: [XMLTreeAttribute] = [],
    namespaceDeclarations: [XMLNamespaceDeclaration] = [],
    includeDocument: Bool = true
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T
```

Genera internamente preamble/postamble e delega al core overload:
- `includeDocument == true`:
  - preamble: `[.startDocument(version: "1.0", encoding: configuration.encoding, standalone: nil), .startElement(wrapperName, attributes, nsDecls)]`
  - postamble: `[.endElement(wrapperName), .endDocument]`
- `includeDocument == false`:
  - preamble: `[.startElement(wrapperName, attributes, nsDecls)]`
  - postamble: `[.endElement(wrapperName)]`

---

## Esempi d'uso

```swift
// 1. Solo item, nessun wrapper — da comporre con altri stream
let stream = encoder.encodeEach(dbCursor)

// 2. Wrapper semplice con document declaration
let stream = encoder.encodeEach(dbCursor, wrappedIn: "Items")

// 3. Wrapper con attributi
let stream = encoder.encodeEach(dbCursor,
    wrappedIn: "Items",
    attributes: [XMLTreeAttribute(name: XMLQualifiedName(localName: "source"), value: "db")])

// 4. Preamble generato via encode di un header Encodable
let preamble = try encoder.encode(reportHeader)     // [XMLStreamEvent]
    + [.startElement(XMLQualifiedName(localName: "Rows"), [], [])]
let postamble: [XMLStreamEvent] = [.endElement(XMLQualifiedName(localName: "Rows"))]
let stream = encoder.encodeEach(cursor, preamble: preamble, postamble: postamble)

// 5. Encoding custom per item (attributi dinamici, naming custom, ecc.)
let stream = encoder.encodeEach(cursor,
    preamble: preambleEvents,
    postamble: postambleEvents
) { record in
    [.startElement(XMLQualifiedName(localName: "Row"),
                   [XMLTreeAttribute(name: XMLQualifiedName(localName: "id"),
                                     value: String(record.id))], [])]
    + (try XMLStreamEncoder().encode(record))
    + [.endElement(XMLQualifiedName(localName: "Row"))]
}
```

---

## Implementazione interna

### Core (`encodeItem` overload)

```swift
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    preamble: [XMLStreamEvent],
    postamble: [XMLStreamEvent],
    encodeItem: @Sendable @escaping (T) throws -> [XMLStreamEvent]
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T {
    AsyncThrowingStream { continuation in
        Task {
            do {
                for event in preamble        { continuation.yield(event) }
                for try await item in items  {
                    if Task.isCancelled { break }
                    for event in try encodeItem(item) { continuation.yield(event) }
                }
                for event in postamble       { continuation.yield(event) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### Senza `encodeItem` (cattura solo `configuration`, non `self` — Sendable safe)

```swift
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    preamble: [XMLStreamEvent] = [],
    postamble: [XMLStreamEvent] = []
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T {
    let configuration = self.configuration
    return encodeEach(items, preamble: preamble, postamble: postamble) { item in
        try XMLStreamEncoder(configuration: configuration).encode(item)
    }
}
```

### `wrappedIn` convenience

```swift
public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
    _ items: S,
    wrappedIn elementName: String,
    attributes: [XMLTreeAttribute] = [],
    namespaceDeclarations: [XMLNamespaceDeclaration] = [],
    includeDocument: Bool = true
) -> AsyncThrowingStream<XMLStreamEvent, Error>
where S.Element == T {
    let wrapperName = XMLQualifiedName(localName: elementName)
    let enc: String = configuration.encoding
    var preamble: [XMLStreamEvent] = []
    if includeDocument {
        preamble.append(.startDocument(version: "1.0", encoding: enc, standalone: nil))
    }
    preamble.append(.startElement(wrapperName, attributes, namespaceDeclarations))

    var postamble: [XMLStreamEvent] = [.endElement(wrapperName)]
    if includeDocument {
        postamble.append(.endDocument)
    }

    return encodeEach(items, preamble: preamble, postamble: postamble)
}
```

---

## Limite by design (da documentare)

Il postamble **non può dipendere dai dati iterati** senza accumulare la sequenza intera
(es. `<count>N</count>` non è calcolabile a priori). Per questo pattern, il chiamante
raccoglie il valore in un attore/Sendable durante `encodeItem` e produce il postamble
come secondo stream separato da concatenare. Questo è un vincolo dello streaming in
generale, non di questa API.

---

## File da creare / modificare

| Operazione | File |
|---|---|
| **Crea** | `Sources/SwiftXMLCoder/XMLStreamEncoder+Sequence.swift` |
| **Crea** | `Tests/SwiftXMLCoderTests/XMLStreamEncoderSequenceTests.swift` |

`XMLStreamEncoder.swift` non va modificato — i nuovi metodi vivono nell'extension file.

---

## Test da scrivere

1. `test_encodeEach_emitsItemsInOrder` — 3 item, verifica che gli eventi appaiano in sequenza corretta
2. `test_encodeEach_emptySequence_onlyPreamblePostamble` — sequenza vuota, solo preamble+postamble
3. `test_encodeEach_preamblePostamble_positionedCorrectly` — preamble prima del primo item, postamble dopo l'ultimo
4. `test_encodeEach_wrappedIn_producesReparsableXML` — re-parsa con `XMLStreamParser`, verifica struttura
5. `test_encodeEach_wrappedIn_withAttributes_setsWrapperAttributes` — attributi sul wrapper presenti negli eventi
6. `test_encodeEach_wrappedIn_includeDocumentFalse_noDocumentEvents` — no `.startDocument`/`.endDocument`
7. `test_encodeEach_customEncodeItem_overridesDefault` — closure custom produce eventi diversi
8. `test_encodeEach_preambleFromEncodedHeader` — preamble generato via `encoder.encode(header)`, composizione funziona
9. `test_encodeEach_roundTrip_collect_decode` — `encodeEach` → `XMLStreamWriter.writeChunked` → `XMLDecoder.decode` per ogni item
10. `test_encodeEach_cancellation_terminatesStream` — `Task.cancel()` prima di esaurire la sequenza, nessun evento dopo
11. `test_encodeEach_errorInEncodeItem_propagates` — closure che lancia, stream termina con errore

---

## Criteri di completamento

- [ ] Tutti e 3 gli overload implementati in `XMLStreamEncoder+Sequence.swift`
- [ ] Tutti i test passano
- [ ] `swift build -c debug` — zero errori
- [ ] `swift test --enable-code-coverage` — zero regressioni
- [ ] `swiftlint lint` — zero nuove violazioni serious
- [ ] CHANGELOG aggiornato