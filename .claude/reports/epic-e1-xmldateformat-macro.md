# Step Report — Epic E.1: `@XMLDateFormat` Macro

**Date:** 2026-03-15
**Branch:** `claude/epic-d-quality-hardening` (continues epic-e work on same branch)
**Status:** ✅ Complete

---

## Scope

- **Task:** E.1 — Macro ergonomics phase 2: `@XMLDateFormat` per-property date strategy override
- **Boundaries:** SwiftXMLCoder module only. No changes to Package manifests, CI, or external dependencies.

---

## Public API Changes

### Added

- **`XMLDateFormatHint`** (`Sources/SwiftXMLCoder/XMLDateFormatHint.swift`)
  - `public enum XMLDateFormatHint: Sendable, Hashable, Codable`
  - Cases: `.xsdDateTime`, `.xsdDate`, `.xsdDateWithTimezone(identifier:)`, `.xsdTime`, `.xsdTimeWithTimezone(identifier:)`, `.xsdGYear`, `.xsdGYearMonth`, `.xsdGMonth`, `.xsdGDay`, `.xsdGMonthDay`, `.secondsSince1970`, `.millisecondsSince1970`
  - Computed properties: `var encodingStrategy: XMLEncoder.DateEncodingStrategy`, `var decodingStrategy: XMLDecoder.DateDecodingStrategy`

- **`XMLDateCodingOverrideProvider`** (`Sources/SwiftXMLCoder/XMLDateFormatHint.swift`)
  - `public protocol XMLDateCodingOverrideProvider`
  - Requirement: `static var xmlPropertyDateHints: [String: XMLDateFormatHint] { get }`
  - Synthesised by `@XMLCodable` when `@XMLDateFormat` annotations are present; not intended for manual conformance.

- **`@XMLDateFormat(_ hint: XMLDateFormatHint)`** (`Sources/SwiftXMLCoderMacros/XMLCodableMacros.swift`)
  - `@attached(peer)` macro, Swift 5.9+ only
  - Pure syntax marker; generates no peers
  - Detected by `@XMLCodable` at compile time to synthesise `xmlPropertyDateHints`

### Changed

- **`@XMLCodable` macro** (`Sources/SwiftXMLCoderMacroImplementation/XMLCodableMacro.swift`)
  - Now scans for `@XMLDateFormat(...)` annotations in addition to `@XMLAttribute`/`@XMLChild`
  - When ≥1 `@XMLDateFormat` annotation is found, synthesises a second extension conforming to `XMLDateCodingOverrideProvider` with `xmlPropertyDateHints` dictionary
  - Hint argument is emitted verbatim into the synthesised source (e.g. `.xsdDateWithTimezone(identifier: "Europe/Rome")`)
  - When no `@XMLDateFormat` annotations are present, behaviour is identical to before (only `XMLFieldCodingOverrideProvider` extension emitted)

- **`_XMLEncoderOptions`** (`Sources/SwiftXMLCoder/XMLEncoder+Codable.swift`)
  - Added `var perPropertyDateHints: [String: XMLDateFormatHint] = [:]`
  - Populated at encode-root time via `_xmlPropertyDateHints(for: T.self)` and propagated into nested encoders

- **`_XMLDecoderOptions`** (`Sources/SwiftXMLCoder/XMLDecoder+Codable.swift`)
  - Added `var perPropertyDateHints: [String: XMLDateFormatHint] = [:]`
  - Populated at decode-root time and propagated into nested decoders

### Deprecated/Removed

- None.

---

## Implementation Notes

### Core logic

**Macro synthesis:** `XMLCodableMacro.expansion` scans `AttributeListSyntax` for `@XMLDateFormat(...)`. The helper `AttributeListSyntax.xmlDateFormatHint` extracts the first argument's `trimmedDescription` as a raw string (e.g. `".xsdDate"`) and emits it verbatim into the generated `xmlPropertyDateHints` dictionary. This means any valid `XMLDateFormatHint` expression — including parameterised cases — is preserved exactly as written.

**Encoder override:** `_XMLTreeEncoder.boxedDate(_:codingPath:localName:isAttribute:)` resolves an `effectiveStrategy` by checking `options.perPropertyDateHints[localName]` before falling back to `options.dateEncodingStrategy`. The `localName` parameter already carries the field name (coding key string value) at the call site.

**Decoder override:** `_XMLTreeDecoder.parseDate(_:codingPath:localName:isAttribute:)` mirrors the encoder: checks `options.perPropertyDateHints[localName]` before using `options.dateDecodingStrategy`.

**Propagation:** `perPropertyDateHints` is populated from `_xmlPropertyDateHints(for: T.self)` — a free module-internal function that casts `T.self` to `XMLDateCodingOverrideProvider.Type`. It is set on `_XMLEncoderOptions` / `_XMLDecoderOptions` at:
1. Top-level encode/decode (for the root type `T`)
2. Each nested `encodeEncodable` / `decode<T>(_:forKey:)` call when creating a child encoder/decoder

### Edge cases handled

- **No conformance:** Types not conforming to `XMLDateCodingOverrideProvider` return `[:]` from `_xmlPropertyDateHints`, leaving `perPropertyDateHints` empty → global strategy applies unchanged.
- **Unknown timezone identifier** in `.xsdDateWithTimezone(identifier:)`: falls back to `.utc` (documented in `XMLDateFormatHint`).
- **`@XMLDateFormat` without `@XMLCodable`:** Compiles successfully; the annotation has no runtime effect (same pattern as `@XMLAttribute` without `@XMLCodable`).
- **Mixed annotations:** `@XMLCodable` synthesises both `XMLFieldCodingOverrideProvider` and `XMLDateCodingOverrideProvider` extensions independently when both `@XMLAttribute`/`@XMLChild` and `@XMLDateFormat` are present.

### Internal trade-offs

**Why `XMLDateFormatHint` instead of passing `DateEncodingStrategy` directly?**
`DateEncodingStrategy` has a `.custom(closure)` case that is not `Codable` and cannot be represented as a literal in synthesised source. `XMLDateFormatHint` is a closed enum covering only the XSD-declarable strategies, which can be emitted verbatim into generated code. Users needing `custom` or `formatter` strategies still use the global encoder/decoder configuration.

**Why emit the hint argument verbatim rather than resolving to a canonical form?**
Allows parameterised cases like `.xsdDateWithTimezone(identifier: "Europe/Rome")` to pass through without re-parsing or normalising. The generated code is valid Swift as long as the original argument expression is valid.

**Why not use a `@attached(accessor)` macro instead of per-property peer + `@XMLCodable` extension?**
Accessor macros wrap the property in getter/setter boilerplate that conflicts with `Codable` synthesis and stored-property semantics. The existing peer-marker + parent-extension pattern (established by `@XMLAttribute`/`@XMLChild`) is consistent and well-tested.

---

## Validation Evidence

- **Build:** `swift build -c debug` → `Build complete! (1.12s)` ✅
- **Tests:** `swift test --enable-code-coverage` → `351 tests, 0 failures` ✅
  - 14 new integration tests in `XMLDateFormatMacroIntegrationTests`
  - 4 new macro expansion tests in `XMLMacroDiagnosticsTests`
- **Lint:** `swiftlint lint` → `182 violations, 0 serious` ✅ (all warnings; no new serious violations; preexisting `line_length`/`cyclomatic_complexity` in `XMLDecoder+Codable.swift` and `XMLEncoder+Codable.swift` are unchanged from before)

---

## Risks and Follow-ups

### Residual risks

- `localName` used as the lookup key in `boxedDate`/`parseDate` is the coding key's `stringValue`. If a type uses a custom `CodingKeys` enum with `rawValue != propertyName`, the hint lookup will miss. This is consistent with how `xmlFieldNodeKinds` works in `@XMLCodable` — both use `stringValue`. **Impact:** low; `@XMLCodable` is the canonical way to configure these types and synthesises `xmlPropertyDateHints` keyed by property name, so custom `CodingKeys` users would need to also customise their `xmlPropertyDateHints` manually.

### Non-blocking follow-ups

- E.2 (structured logging) is next: Logger injection via `XMLEncoder.Configuration`, `XMLDecoder.Configuration`, `XMLDocument` init.
- Consider extending `@XMLAttribute("custom-name")` and `@XMLChild("custom-name")` name-override macros (also part of E.1 plan spec) as a follow-on before E.2 if Matteo wants to keep E.1 fully complete per the plan.