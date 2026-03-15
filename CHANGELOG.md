# Changelog

All notable changes to SwiftXMLCoder will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- DocC catalog (`Sources/SwiftXMLCoder/SwiftXMLCoder.docc/`): landing page + 8 articles (GettingStarted, FieldMapping, Namespaces, Canonicalization, XPath, Security, Compatibility, TestSupport).
- `README.md`: installation instructions (all 3 SPM product variants), quick-start code examples, feature matrix, and links to DocC articles.
- Inline `///` doc comments on all previously undocumented public types and members: `XMLNode`, `XMLNamespaceDeclaration`, `XMLNormalizationOptions`, `XMLTemporalCoding` types (`XMLDateFormatterDescriptor`, `XMLDateCodingContext`, `XMLDateEncodingClosure`, `XMLDateDecodingClosure`), `XMLCanonicalizationErrorCode` (all static constants), `XMLNamespace`, `XMLQualifiedName`, `XMLTreeNode` (all cases), `XMLTreeAttribute`, `XMLCanonicalizationError`, `XMLCanonicalizationStage`, `XMLCanonicalView`, `XMLIdentityTransform`, `XMLDefaultCanonicalizer`, `XMLNamespaceResolver`, `XMLNamespaceValidator`, `XMLDocument` (`createElement`, `appendChild`, `serializedData`, XPath methods).
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): matrix build and test across Linux (Swift 5.6, 5.9, 5.10, 6.0, 6.1) and macOS 15 (Swift 6.1 / Xcode 16.2). Coverage report generated via `llvm-cov` and uploaded as artifact on pushes to `main`.
- GitHub Actions SwiftLint workflow (`.github/workflows/lint.yml`): runs `realm/SwiftLint@v0.57.1` with PR review annotations on every push and pull request to `main`.
- GitHub Actions DocC workflow (`.github/workflows/docc.yml`): builds documentation for the `SwiftXMLCoder` target on macOS; will enforce `--warnings-as-errors` once the DocC catalog is added in Epic B.
- `Tests/.swiftlint.yml`: nested SwiftLint config relaxing `identifier_name` (min 1) and `type_name` (min 1) for test files, and demoting `force_unwrapping` from error to warning in tests. Source code remains at full strictness.

## [0.1.0] — 2026-03-15

### Added
- Initial extraction of `SwiftXMLCoder` from `swift-soap`.
- `XMLEncoder` / `XMLDecoder`: Codable-compatible XML codec backed by libxml2.
- `XMLTreeDocument`, `XMLTreeElement`, `XMLTreeNode`, `XMLTreeAttribute`: immutable value-semantic tree model.
- `XMLTreeParser` / `XMLTreeWriter`: low-level parse and serialization.
- `XMLDocument` with XPath query support.
- `XMLCanonicalizer` protocol + `XMLDefaultCanonicalizer`: deterministic XML canonicalization (XML-DSig ready).
- `XMLTransform` pipeline: pre-canonicalization transform hooks.
- Three-tier field mapping: `XMLFieldCodingOverrides` (runtime), `XMLFieldCodingOverrideProvider` (compile-time), `@XMLAttribute`/`@XMLElement` property wrappers.
- `@XMLCodable`, `@XMLAttribute`, `@XMLElement` compiler macros (Swift 5.9+).
- Full namespace support: `XMLNamespace`, `XMLQualifiedName`, `XMLNamespaceResolver`.
- Parser security hardening: configurable depth, node, and text-size limits.
- `SwiftXMLCoderTestSupport`: spy encoders/decoders and canonicalizer contract probe.
- 243 tests covering encoding, decoding, canonicalization, XPath, namespaces, and scalar types.
- Multi-manifest compatibility: Swift 5.4 through 6.1.
