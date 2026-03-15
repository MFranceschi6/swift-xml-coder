# Changelog

All notable changes to SwiftXMLCoder will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- `XMLValidationPolicy`: build-time and runtime configurable validation policy. Default is `.lenient` (no validation); `.strict` enables element-name and XSD temporal validation. Set at build time via `-DSWIFT_XML_CODER_STRICT_VALIDATION`; override per-instance via `XMLEncoder.Configuration.validationPolicy` / `XMLDecoder.Configuration.validationPolicy`.
- XSD temporal value types: `XMLGYear`, `XMLGYearMonth`, `XMLGMonth`, `XMLGDay`, `XMLGMonthDay`, `XMLTime`, `XMLDuration` — all `Sendable`, `Equatable`, `Hashable`, `Codable` (encode/decode as XSD lexical strings). Each type with a `Foundation.Date` bridge where meaningful.
- `XMLTimezoneOffset`: value type for XSD timezone offsets (`Z`, `±HH:MM`); `public static let utc`.
- `TimeZone.utc`: convenience public extension.
- `DateEncodingStrategy` new cases: `.xsdDate(timeZone:)`, `.xsdTime(timeZone:)`, `.xsdGYear(timeZone:)`, `.xsdGYearMonth(timeZone:)`, `.xsdGMonth(timeZone:)`, `.xsdGDay(timeZone:)`, `.xsdGMonthDay(timeZone:)` — encode `Foundation.Date` as each XSD partial-date form.
- `DateDecodingStrategy` new cases: `.xsdDate`, `.xsdTime`, `.xsdGYear`, `.xsdGYearMonth`, `.xsdGMonth`, `.xsdGDay`, `.xsdGMonthDay` — decode XSD partial-date lexical strings into `Foundation.Date`.
- `_XMLTemporalFoundationSupport.formatXSDDate(_:timeZone:)` and `parseXSDDate(_:)` helpers for `xs:date` ↔ `Foundation.Date` conversion.
- 61 new tests in `XMLTemporalTypesTests` covering parsing, roundtrip, invalid input, `Foundation.Date` bridges, and `XMLValidationPolicy` build-time/runtime behavior.
- `XMLDocument.ParsingConfiguration.untrusted()` static factory that explicitly enforces all libxml2 hardening flags (`.forbidNetwork`, DTD forbidden, entity references preserved, blank text nodes trimmed). Intended for use with `XMLTreeParser.Limits.untrustedInputDefault()` for full defence-in-depth against malicious XML input.
- 3 new tests in `XMLTreeHardeningTests` covering `untrusted()` policy assertions, rejection of a deeply-nested XML bomb, and rejection of an oversized text node.
- `XMLRootNameResolver.explicitRootElementName(from:validationPolicy:)` and `implicitRootElementName(for:validationPolicy:)` now accept a `validationPolicy` parameter. In `.strict` mode, a `rootElementName` or `XMLRootNode.xmlRootElementName` that requires sanitization fails with `[XML6_6_ROOT_NAME_INVALID]` instead of silently correcting.
- `_XMLEncoderOptions.init` now throws `[XML6_6_ITEM_NAME_INVALID]` in `.strict` mode when `itemElementName` requires sanitization. In `.lenient` mode (default) the name is still sanitized silently.
- 8 new tests in `XMLEncoderTests` (D.1 matrix): strict rejection of `rootElementName` with space, digit-prefix, invalid `XMLRootNode` name, and `itemElementName` with space; lenient sanitization pass for root and item names; valid-name no-throw assertions.
- `Tests/.swiftlint.yml`: raised `type_body_length` warning threshold to 600 lines for test files (test classes grow with coverage matrix).
- New test target `SwiftXMLCoderMacroTests` (Swift 5.9+ manifests): uses `SwiftSyntaxMacrosTestSupport.assertMacroExpansion` to verify macro diagnostic IDs and expansion output. Covers: `@XMLCodable` on `enum` → `XML8A_INVALID_DECL` error; `@XMLCodable` on `actor` → same error; `@XMLCodable` on struct/class → correct `xmlFieldNodeKinds` expansion; `@XMLAttribute`/`@XMLChild` as pure peer markers (no generated peers).
- `@XMLDateFormat(_ hint: XMLDateFormatHint)` macro (Swift 5.9+ only): per-property date format annotation for stored properties of type `Date` or `Date?`. Apply inside a type annotated with `@XMLCodable` to override the global `dateEncodingStrategy`/`dateDecodingStrategy` for that property.
- `XMLDateFormatHint` enum: `Sendable`, `Equatable`, `Hashable`, `Codable`. Covers all XSD date strategies: `.xsdDate`, `.xsdTime`, `.xsdDateTime`, `.xsdGYear`, `.xsdGYearMonth`, `.xsdGMonth`, `.xsdGDay`, `.xsdGMonthDay`, `.xsdDateWithTimezone(identifier:)`, `.xsdTimeWithTimezone(identifier:)`, `.secondsSince1970`, `.millisecondsSince1970`. Converts to `XMLEncoder.DateEncodingStrategy` and `XMLDecoder.DateDecodingStrategy` via `.encodingStrategy` and `.decodingStrategy` computed properties.
- `XMLDateCodingOverrideProvider` protocol: synthesised by `@XMLCodable` when any property is annotated with `@XMLDateFormat`. The static `xmlPropertyDateHints: [String: XMLDateFormatHint]` dictionary is consulted by encoder and decoder before the global strategy.
- `@XMLCodable` now synthesises a second extension (`XMLDateCodingOverrideProvider`) when at least one `@XMLDateFormat` annotation is present. The `xmlPropertyDateHints` dictionary maps property names to their hints verbatim.
- `XMLEncoder` and `XMLDecoder` now apply per-property date hints from `XMLDateCodingOverrideProvider` before the instance-level strategy, for both top-level types and all nested types.
- 14 new integration tests in `XMLDateFormatMacroIntegrationTests`: hint → strategy conversions, per-property encode override, per-property decode override, roundtrip, global fallback, Codable roundtrip for all `XMLDateFormatHint` cases.
- 4 new macro expansion tests in `XMLMacroDiagnosticsTests`: `@XMLDateFormat` as pure peer marker; `@XMLCodable` with `@XMLDateFormat` → `xmlPropertyDateHints` extension; mixed `@XMLAttribute`/`@XMLDateFormat`; complex parameterised hint passed verbatim.

### Changed
- XML field-name validation (error code `XML6_6_FIELD_NAME_INVALID`) is now gated by `XMLValidationPolicy.validateElementNames`. Existing tests updated to use `validationPolicy: .strict` to preserve their intent. In lenient mode (default) invalid field names are silently passed through to libxml2.

### Breaking Changes
- Renamed `XMLElement<Value>` property wrapper to ``XMLChild<Value>``. The old name is retained as a `@available(*, deprecated, renamed: "XMLChild")` typealias for source compatibility.
- Renamed `@XMLElement` macro to `@XMLChild`. The old macro name is kept as a deprecated alias pointing to the same implementation (`XMLChildMacro`).
- Removed `preserveWhitespaceTextNodes: Bool` parameter from `XMLTreeParser.Configuration.init` and `Configuration.untrustedInputProfile`. Use `whitespaceTextNodePolicy: .preserve` instead.
- `XMLCanonicalizationError.code` now returns `XMLCanonicalizationErrorCode` instead of `String`. Update callers that compare `.code` to raw string literals to use the typed constant (e.g. `.code == .transformFailed`).

### Added
- `XMLNamespace` conforms to `Equatable` and `Hashable`.
- `XMLParsingError` conforms to `Equatable`. Two `.other` values are never equal (existential payload cannot be compared structurally — documented in the case's doc comment).
- `makeXMLSafeName` now strips namespace prefixes from qualified names (e.g. `"soap:Envelope"` → `"Envelope"` instead of `"soap_Envelope"`). Regression test added.
- Regression test `test_encodeTree_itemElementName_namespacePrefixed_stripsPrefix`.
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
