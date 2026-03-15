# Canonicalization

Produce deterministic, canonical XML output suitable for signature and digest workflows.

## Overview

``XMLCanonicalizer`` is a protocol that transforms an ``XMLTreeDocument`` into a canonical byte sequence. The default implementation, ``XMLDefaultCanonicalizer``, produces deterministic output by sorting attributes alphabetically, normalising whitespace, and applying configurable namespace stripping.

Canonicalization is a prerequisite for XML Digital Signature (XML-DSig) and other integrity workflows where identical documents must produce identical byte sequences regardless of authoring order.

## Basic Usage

```swift
import SwiftXMLCoder

let parser = XMLTreeParser()
let tree = try parser.parse(data: xmlData)

let canonicalizer = XMLDefaultCanonicalizer()
let canonical: Data = try canonicalizer.canonicalize(tree)
```

`canonical` is deterministic: parsing the same logical document twice and canonicalizing both results produces identical `Data`.

## Transform Pipeline

Apply one or more ``XMLTransform`` steps before canonicalization to filter or rewrite the tree:

```swift
struct StripCommentsTransform: XMLTransform {
    func apply(to document: XMLTreeDocument) throws -> XMLTreeDocument {
        // Return a new tree with comment nodes removed
    }
}

let canonicalizer = XMLDefaultCanonicalizer(transforms: [StripCommentsTransform()])
let canonical = try canonicalizer.canonicalize(tree)
```

Transforms run in declaration order. Each receives the output of the previous transform.

## Custom Canonicalizer

Conform to ``XMLCanonicalizer`` to provide a custom implementation — for example, to implement Exclusive C14N (C14N 1.0 with exclusive namespace rendering):

```swift
struct ExclusiveC14NCanonicalizer: XMLCanonicalizer {
    func canonicalize(_ document: XMLTreeDocument) throws -> Data {
        // Custom implementation
    }
}
```

## Error Handling

Canonicalization errors are reported through ``XMLCanonicalizationError``. Each error case carries a stable ``XMLCanonicalizationError/code`` and an underlying cause:

```swift
do {
    let canonical = try canonicalizer.canonicalize(tree)
} catch let error as XMLCanonicalizationError {
    print(error.code, error.underlyingError ?? "")
}
```
