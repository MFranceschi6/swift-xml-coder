# Test Support

Use SwiftXMLCoderTestSupport to verify your XML codec integration without depending on concrete encoder or decoder implementations.

## Overview

The `SwiftXMLCoderTestSupport` product provides spy objects and contract probes for testing code that depends on `XMLEncoder`, `XMLDecoder`, or `XMLCanonicalizer`. All types are designed for deterministic, isolated tests — no network, filesystem, or time dependencies.

## Installation

Add `SwiftXMLCoderTestSupport` to your **test** target only:

```swift
.testTarget(
    name: "MyTargetTests",
    dependencies: [
        "MyTarget",
        .product(name: "SwiftXMLCoderTestSupport", package: "swift-xml-coder")
    ]
)
```

## Spy Encoder

`XMLTestEncoderSpy` wraps a real `XMLEncoder` and records every `encodeTree` and `encode` call. Use it to verify that your code calls the encoder with the expected arguments and to inject failures:

```swift
import SwiftXMLCoderTestSupport
import XCTest

func testEncodesPayload() throws {
    let spy = XMLTestEncoderSpy()
    let codec = MyXMLCodec(encoder: spy)

    try codec.encode(MyPayload(id: 1))

    XCTAssertEqual(spy.calls.count, 1)
    XCTAssertEqual(spy.calls.first?.method, .encode)
}

func testPropagatesEncoderError() {
    let spy = XMLTestEncoderSpy()
    spy.forcedError = XMLParsingError.encodeFailed(reason: "test")
    let codec = MyXMLCodec(encoder: spy)

    XCTAssertThrowsError(try codec.encode(MyPayload(id: 1)))
}
```

## Spy Decoder

`XMLTestDecoderSpy` mirrors the encoder spy for decoding:

```swift
let spy = XMLTestDecoderSpy()
spy.decodeDataStub = { type, data in
    MyPayload(id: 42)
}

let result = try spy.decode(MyPayload.self, from: Data())
XCTAssertEqual(result.id, 42)
```

## Canonicalizer Contract Probe

`XMLCanonicalizerContractProbe` validates that a custom `XMLCanonicalizer` implementation honours the transform ordering and failure contracts:

```swift
let orderResult = try XMLCanonicalizerContractProbe.probeTransformOrder(
    canonicalize: XMLCanonicalizerContractProbe.makeDefaultCanonicalizeClosure()
)
XCTAssertEqual(orderResult.recordedTokens, ["A", "B"])
XCTAssertEqual(orderResult.traceValue, "AB")

let failureResult = try XMLCanonicalizerContractProbe.probeTransformFailure(
    canonicalize: XMLCanonicalizerContractProbe.makeDefaultCanonicalizeClosure()
)
XCTAssertTrue(failureResult.message?.contains("XML6_9_CANONICAL_TRANSFORM_FAILED") == true)
```

Pass your own `canonicalize` closure to test a custom `XMLCanonicalizer` implementation against the same contract.

## Transform Stubs

`XMLTestRecordingTransform` records every document it receives, and `XMLTestFailingTransform` throws a configurable error — both are useful for injecting controlled behavior into the canonicalization pipeline.
