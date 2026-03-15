# 03 - Validation and Quality Gates

## Required Commands (Before Task Closure)

- Build: `swift build -c debug`
- Tests with coverage: `swift test --enable-code-coverage`
- Lint: `swiftlint lint`

## Coverage and Tests

- Bug fixes must include regression tests.
- Features must include meaningful coverage for core behavior and edge cases.
- Tests must be deterministic and isolated from unstable external dependencies.
- Coverage target is pragmatic but high (trend toward ~90% on critical paths).

## Test Structure

Tests live in `Tests/SwiftXMLCoderTests/` and cover:
- `XMLDecoderTests` / `XMLEncoderTests` — encode/decode roundtrips
- `XMLFieldMappingTests` — three-tier field mapping
- `XMLCanonicalizerTests` — canonicalization correctness
- `XMLTreeModelTests` / `XMLTreeParserWriterTests` — tree model and parse/serialize
- `XMLTreeHardeningTests` — security edge cases
- `XMLDocumentCoverageTests` / `XMLDocumentXPathTests` — high-level document API
- `XMLScalarCoverageTests` / `XMLContainerCoverageTests` — scalar and collection encoding
- `XMLNamespaceResolverTests` — namespace resolution
- `XMLTestingToolkitIntegrationTests` — test support library API

## Validation Policy During Iteration

- Iterative development can run partial checks (single test target, single file).
- Final closure must run all three required commands and capture outcomes.
