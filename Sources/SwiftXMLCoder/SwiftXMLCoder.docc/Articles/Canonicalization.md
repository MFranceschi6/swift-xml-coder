# Canonicalization

Produce deterministic XML output suitable for digest and signature workflows.

## Overview

``XMLCanonicalizer`` defines two canonicalization styles:

- Tree-based canonicalization from ``XMLTreeDocument`` using ``XMLTransform``.
- Streaming canonicalization from raw `Data` or ``XMLStreamEvent`` using ``XMLEventTransform``.

`SwiftXMLCoder` ships ``XMLDefaultCanonicalizer`` as the default implementation.

## Tree-Based Usage

```swift
import SwiftXMLCoder

let parser = XMLTreeParser()
let tree = try parser.parse(data: xmlData)

let canonicalizer = XMLDefaultCanonicalizer()
let canonical = try canonicalizer.canonicalize(tree)
```

Customize behavior with ``XMLCanonicalizationOptions`` and transforms:

```swift
let data = try canonicalizer.canonicalize(
    tree,
    options: XMLCanonicalizationOptions(includeComments: true),
    transforms: [MyTreeTransform()]
)
```

## Streaming Usage

Canonicalize directly from input bytes:

```swift
let canonical = try canonicalizer.canonicalize(
    data: xmlData,
    options: XMLCanonicalizationOptions(),
    eventTransforms: [MyEventTransform()]
)
```

Or emit through a callback sink:

```swift
try canonicalizer.canonicalize(
    data: xmlData,
    options: XMLCanonicalizationOptions(),
    eventTransforms: []
) { chunk in
    sink.write(chunk)
}
```

## Error Handling

Canonicalization APIs throw ``XMLParsingError``.
