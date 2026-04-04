# Piano: XMLStreamDecoder — Event-Cursor Decoder (Proposta B)

## Obiettivo

Eliminare il passaggio intermedio `buildDocument → XMLTreeDocument → XMLDecoder`.
Decodificare direttamente da `[XMLStreamEvent]` tramite un `Decoder` custom che opera
su un indice degli eventi, senza allocare nodi albero.

Motivazione chiave: XML ha ordine degli elementi definito per schema; il `init(from:)`
sintetizzato da Swift accede ai campi nello stesso ordine in cui sono dichiarati nello
struct. Nella pratica, l'accesso è quasi sempre sequenziale → indice consultato in ordine
→ cache di lookahead vuota nel caso comune.

## Pipeline attuale vs nuova

```
Attuale:  [XMLStreamEvent] → XMLTreeDocument (nodi allocati) → XMLDecoder → T
Nuova:    [XMLStreamEvent] → XMLStreamEventDecoder (cursore/indice) → T
```

---

## Strutture dati chiave

### `EventRange`

```swift
/// Range chiuso di indici nell'array di eventi: events[start] è startElement,
/// events[end] è il corrispondente endElement.
struct EventRange {
    let start: Int   // indice del .startElement
    let end: Int     // indice del .endElement corrispondente
}
```

### `ChildIndex`

```swift
/// Indice dei figli diretti di un elemento, costruito con una singola
/// scansione forward. Gestisce chiavi ripetute (array di elementi omogenei).
typealias ChildIndex = [String: [EventRange]]
```

---

## Componenti da implementare

Tutti interni (`internal` / `private`). File nuovo:
`Sources/SwiftXMLCoder/XMLStreamEventDecoder.swift`

### 1. `XMLStreamEventDecoder: Decoder`

Top-level bridge tra il sistema `Decodable` e l'array di eventi.

```swift
final class XMLStreamEventDecoder: Decoder {
    let events: [XMLStreamEvent]
    let scope: EventRange          // range del root element
    let configuration: XMLDecoder.Configuration
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    func container<K: CodingKey>(keyedBy type: K.Type) throws
        -> KeyedDecodingContainer<K>

    func unkeyedContainer() throws -> UnkeyedDecodingContainer

    func singleValueContainer() throws -> SingleValueDecodingContainer
}
```

### 2. `XMLStreamKeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol`

```swift
struct XMLStreamKeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    let events: [XMLStreamEvent]
    let scope: EventRange
    let configuration: XMLDecoder.Configuration
    var codingPath: [CodingKey]

    // Costruito lazily al primo accesso
    private let childIndex: ChildIndex        // child elements per chiave
    private let attributes: [String: String]  // attributi dell'elemento scope.start
}
```

**Costruzione** (in `init`):
1. Estrai attributi da `events[scope.start]` (il `.startElement`) → dict `[String: String]`
2. Chiama `buildChildIndex(events:scope:)` → `ChildIndex`

Lookup di una chiave `k`:
1. Controlla `attributes[k.stringValue]` (rispettando `nodeDecodingStrategy`)
2. Altrimenti cerca `childIndex[k.stringValue]` → prende il primo `EventRange` non ancora
   consumato

### 3. `XMLStreamUnkeyedContainer: UnkeyedDecodingContainerProtocol`

Usato per array (`[T]`) — itera sui figli dell'elemento corrente in ordine.

```swift
struct XMLStreamUnkeyedContainer: UnkeyedDecodingContainerProtocol {
    let events: [XMLStreamEvent]
    let scope: EventRange
    var currentIndex: Int             // indice nella lista figli ordinata
    private let children: [EventRange] // tutti i figli diretti in ordine
}
```

`children` si costruisce da `buildChildIndex` appiattendo i range in ordine di `start`.

### 4. `XMLStreamSingleValueContainer: SingleValueDecodingContainerProtocol`

Estrae il contenuto testuale dall'interno di un `EventRange`.

```swift
struct XMLStreamSingleValueContainer: SingleValueDecodingContainerProtocol {
    let events: [XMLStreamEvent]
    let scope: EventRange         // il .startElement/.endElement dell'elemento
    let configuration: XMLDecoder.Configuration
    var codingPath: [CodingKey]
}
```

Implementa `decode(String.self)`, `decode(Int.self)`, ecc. estraendo il testo/CDATA
concatenato dagli eventi `.text` e `.cdata` interni alla `scope`.

---

## Algoritmo: `buildChildIndex`

Scansione forward degli eventi INTERNI alla scope (escludendo `events[scope.start]` e
`events[scope.end]`). Traccia la profondità relativa: raccoglie solo i figli a
`depth == 1`.

```
func buildChildIndex(events: [XMLStreamEvent], scope: EventRange) -> ChildIndex {
    var index: ChildIndex = [:]
    var depth = 0
    var childStart = -1
    var childName = ""

    for i in (scope.start + 1)..<scope.end {
        switch events[i] {
        case .startElement(let name, _, _):
            depth += 1
            if depth == 1 {
                childStart = i
                childName = name.localName  // oppure qualifiedName a seconda della config
            }
        case .endElement:
            if depth == 1 {
                index[childName, default: []].append(EventRange(start: childStart, end: i))
            }
            depth -= 1
        default:
            break
        }
    }
    return index
}
```

**Complessità**: O(eventi dell'elemento corrente) — una sola passata, eseguita una volta
per container.

---

## Algoritmo: `extractText`

Concatena tutto il contenuto `.text` e `.cdata` DIRETTAMENTE interno a un `EventRange`
(profondità == 1, ossia non dentro child elements).

```
func extractText(events: [XMLStreamEvent], scope: EventRange) -> String {
    var result = ""
    var depth = 0
    for i in (scope.start + 1)..<scope.end {
        switch events[i] {
        case .startElement: depth += 1
        case .endElement:   depth -= 1
        case .text(let s) where depth == 0:  result += s
        case .cdata(let s) where depth == 0: result += s
        default: break
        }
    }
    return result
}
```

---

## Gestione attributi vs elementi (nodeDecodingStrategy)

`XMLDecoder.Configuration` ha `nodeDecodingStrategy`. Il container deve rispettarla:

- `.auto`: prova attributi prima per scalari, elementi per tipi complessi
- `.attribute`: solo attributi
- `.element`: solo elementi figli
- `.elementOrAttribute`: entrambi, preferisce elemento

Replicare la stessa logica di `_XMLKeyedDecodingContainer` nel codebase esistente.

---

## Handling della root

`XMLStreamDecoder.decodeImpl` trova il root element:

```
1. Salta .startDocument
2. Trova il primo .startElement → questo è scope.start
3. Trova il corrispondente .endElement (tracciando depth) → scope.end
4. Crea XMLStreamEventDecoder(events:scope:configuration:)
5. Chiama try T(from: eventDecoder)
```

La ricerca del matching `endElement` è O(n) una volta sola.

---

## Gestione casi edge

| Caso | Comportamento |
|---|---|
| Chiave non trovata (campo obbligatorio) | `DecodingError.keyNotFound` |
| Chiave non trovata (campo opzionale) | `nil` via `decodeIfPresent` |
| Chiavi ripetute (array) | `childIndex[k]` restituisce `[EventRange]`; si consumano in ordine |
| Elemento con solo attributi (nessun testo) | `extractText` restituisce `""` |
| Elemento con solo testo (nessun figlio) | `buildChildIndex` restituisce `[:]` |
| CDATA misto a testo | `extractText` concatena entrambi |
| Namespace | `localName` usato di default; `namespaceURI` disponibile per lookup avanzato |
| Documenti senza `.startDocument` | Tollerato: la ricerca del root parte comunque |

---

## Integrazione con `XMLStreamDecoder`

### Modifiche a `XMLStreamDecoder.swift`

- `decodeImpl` → usa `XMLStreamEventDecoder` invece di `buildDocument + XMLDecoder.decodeTree`
- Rimuovere `buildDocument` e `popElement` (non più necessari)
- Il costruttore pubblico e l'API pubblica restano invariati

### Modifiche a `XMLStreamDecoder.swift` (async overload)

L'overload async continua a collezionare tutti gli eventi prima — questo è inevitabile
per il protocollo `Decodable` sincrono. Ma ora il costo post-raccolta è O(0) allocazioni
aggiuntive (nessun tree building).

---

## File da creare / modificare

| Operazione | File |
|---|---|
| **Crea** | `Sources/SwiftXMLCoder/XMLStreamEventDecoder.swift` |
| **Modifica** | `Sources/SwiftXMLCoder/XMLStreamDecoder.swift` |
| **Crea** | `Tests/SwiftXMLCoderTests/XMLStreamEventDecoderTests.swift` |
| **Modifica** (eventuale) | `Tests/SwiftXMLCoderTests/XMLStreamDecoderTests.swift` — verifica invarianza |

---

## Test da scrivere (`XMLStreamEventDecoderTests.swift`)

1. `test_decode_simpleStruct_fromEvents` — struct con campi scalari
2. `test_decode_nestedStruct` — struct annidato (accesso ricorsivo)
3. `test_decode_arrayField` — array di elementi omogenei
4. `test_decode_optionalAbsent` — campo opzionale non presente → `nil`
5. `test_decode_optionalPresent` — campo opzionale presente → valore
6. `test_decode_attributes` — decodifica da attributi XML
7. `test_decode_outOfOrderFields` — proprietà dichiarate in ordine diverso dall'XML
8. `test_decode_cdataContent` — contenuto CDATA come valore scalare
9. `test_decode_mixedTextAndCdata` — concatenazione testo + CDATA
10. `test_decode_roundTrip_viaEncoder` — `XMLStreamEncoder → XMLStreamDecoder` → uguale
11. `test_decode_roundTrip_matchesXMLDecoder` — stesso risultato di `XMLDecoder` su XML classico
12. `test_decode_invalidEvents_throws` — stream malformato → `XMLParsingError`

---

## Criteri di completamento (Definition of Done)

- [ ] `XMLStreamEventDecoder` implementato e integrato in `XMLStreamDecoder.decodeImpl`
- [ ] Tutti i test di cui sopra passano
- [ ] I test esistenti in `XMLStreamDecoderTests.swift` continuano a passare invariati
- [ ] `swift build -c debug` — zero errori
- [ ] `swift test --enable-code-coverage` — zero regressioni, nuovi test coperti
- [ ] `swiftlint lint` — zero nuove violazioni serious
- [ ] CHANGELOG aggiornato