# Release Plan — SwiftXMLCoder 1.0

**Created:** 2026-03-15
**Target:** First stable, publicly-releasable version
**Current state:** 0.1.0 tagged (functional extraction from swift-soap, not yet public-ready)

---

## Overview

The 0.1.0 tag exists only to allow swift-soap to import the library. The code is solid (243 tests, multi-manifest, full API) but the repo lacks CI, documentation, and a pre-release API review pass. This plan takes it to a real 1.0.

**Key constraint:** All breaking API changes MUST land before 1.0. After 1.0, semver binds.

**Epic sequence:**

```
Epic A (CI) → Epic B (Docs) → Epic C (API Review — breaking) → Epic D (Quality) → Epic E (Ergonomics) → Epic F (Release 1.0)
```

---

## Epic A — CI/CD Infrastructure

**Goal:** Green, multi-platform, multi-version CI on every PR and push to main.

**Steps:**

### A.1 — Matrix build workflow
File: `.github/workflows/ci.yml`

Matrix:
- OS: `ubuntu-latest`, `macos-15`
- Swift: `5.6`, `5.9`, `5.10`, `6.0`, `6.1`
- Exclusions: macros (`Package@swift-5.9.swift`) only on Swift 5.9+; ownership (`SwiftXMLCoderOwnership6`) only on 6.0+

Jobs:
- `swift build -c debug`
- `swift test --enable-code-coverage`

### A.2 — SwiftLint workflow
File: `.github/workflows/lint.yml`

- Run `swiftlint lint` on Ubuntu (latest SwiftLint via `mint` or direct download)
- Trigger on PR and push to main

### A.3 — DocC build check
File: `.github/workflows/docc.yml`

- Build DocC for `SwiftXMLCoder` target (macOS only, latest Swift)
- Fail if documentation build has warnings (after Epic B)
- Can be stub/no-op until Epic B completes

### A.4 — Code coverage badge/report
- Use `llvm-cov` to generate coverage report in CI
- Upload artifact (HTML report) for main branch builds

**Done when:** Every PR shows green CI across all matrix entries; SwiftLint passes; coverage report is available.

**Status:** ⏳ Pending

---

## Epic B — Documentation

**Goal:** Publishable DocC documentation + usable README.

**Steps:**

### B.1 — DocC catalog
Create: `Sources/SwiftXMLCoder/SwiftXMLCoder.docc/`

Contents:
- `SwiftXMLCoder.md` — top-level catalog doc (intro, guides index)
- `Articles/GettingStarted.md` — quick start: encode/decode roundtrip example
- `Articles/FieldMapping.md` — three-tier field mapping: runtime overrides, @XMLCodable macro, property wrappers
- `Articles/Namespaces.md` — XMLNamespaceResolver, namespace-aware encode/decode
- `Articles/Canonicalization.md` — XMLCanonicalizer usage, XMLTransform pipeline
- `Articles/XPath.md` — XMLDocument XPath queries
- `Articles/TestSupport.md` — SwiftXMLCoderTestSupport module usage
- `Articles/Compatibility.md` — Swift version matrix and what each lane provides
- `Articles/Security.md` — Parser hardening, threat model, configuration

### B.2 — README.md
At repo root:

- Badge row: CI status, Swift version, license, SPM
- One-paragraph description
- Installation via SPM (Package.swift snippet for 5.6+, note macros need 5.9+)
- Quick start: encode + decode in 10 lines
- Feature summary (tree model, XPath, namespaces, canonicalization, macros)
- Links to DocC articles
- License section

### B.3 — API doc completeness pass
- Audit all `public` types for missing `///` doc comments
- Ensure `XMLEncoder`, `XMLDecoder`, `XMLDocument`, `XMLCanonicalizer`, `@XMLCodable`, `@XMLAttribute`, `@XMLElement` have examples in their doc comments
- Cross-check with DocC: all symbols referenced in articles must exist

**Done when:** `swift package generate-documentation` succeeds with zero warnings; README renders correctly on GitHub.

**Status:** ⏳ Pending

---

## Epic C — API Review & Breaking Changes

**Goal:** Identify and ship all breaking changes before 1.0 locks the API. This is the most critical epic — nothing after this can break public API.

**Steps:**

### C.1 — Optional-nil semantics clarification (POST-XML-7)
**Why before 1.0:** Current behavior is implicit — `encodeIfPresent` path means `nilEncodingStrategy` only fires when `encodeNil` is called explicitly. This may surprise users.

Tasks:
- Document clearly what happens when an `Optional` field is `nil` under each `NilEncodingStrategy`
- Write focused tests that assert the documented behavior
- If behavior should change (e.g., add `.omitAttribute` strategy or explicit nil behavior on `@XMLAttribute`), do it here
- Update `XMLEncoder` doc comment to match

### C.2 — `@XMLElement` rename (POST-XML-10) **[DECISION: rename]**
**Why before 1.0:** Foundation's `XMLElement` class exists on Apple platforms; `import Foundation; @XMLElement var foo: String` causes ambiguous symbol errors.

**Decision:** Rename. Before 1.0 there are no external users, so a breaking rename has zero migration cost.

Candidate names (pick one before implementing):
- `@XMLChild` — clear, no Foundation conflict, mirrors `@XMLAttribute` symmetry
- `@XMLNode` — concise, but `XMLNode` is also a Foundation class on Apple platforms (same problem)
- `@XMLField` — generic, no conflict

**Recommendation:** `@XMLChild` (no Foundation conflict, intuitive for an element child node).

Tasks:
- Rename `XMLElement<Value>` property wrapper → `XMLChild<Value>`
- Rename `@XMLElement` macro → `@XMLChild`
- Rename `XMLFieldNodeKind.element` case → `.child` (or keep `.element` as the internal discriminator)
- Update all usages in tests, fixtures, doc comments
- Reproduce the original conflict in a compile-fixture test to prove it is resolved
- Update swift-soap's generated code references (out-of-scope here — flag to Matteo after merge)

### C.3 — Full public API naming review
**Why before 1.0:** The library was extracted from swift-soap where naming was driven by SOAP context. Standalone, some names may be worth reconsidering.

Tasks:
- Enumerate all `public` symbols (types, protocols, methods, properties)
- Check for: abbreviation inconsistencies, overly SOAP-specific names, confusing module prefix duplication
- Document findings; propose renames; implement accepted ones
- No renames purely for aesthetics — only rename if there is a real clarity issue

### C.4 — Dual typed-throws audit
**Why before 1.0:** All throw-capable public methods must have `#if swift(>=6.0)` typed-throws branches per design rules.

Tasks:
- Grep for `throws` in public API surface
- Verify each has both the legacy `throws` branch and the `#if swift(>=6.0) throws(XxxError)` branch
- Add missing branches

**Done when:** No further breaking changes are expected; all items in C.1–C.4 are resolved with tests and docs.

**Status:** ⏳ Pending

---

## Epic D — Quality & Hardening

**Goal:** Close known quality gaps and add hardening identified during swift-soap extraction.

**Steps:**

### D.1 — Encoder XML name validation/diagnostics (POST-XML-6)
- Validate `rootElementName`, `itemElementName`, and coding-key-derived element names at encode time
- Invalid XML names (e.g., names starting with digits, containing spaces) must fail early with a stable diagnostic code in `XMLParsingError`
- Tests: matrix of valid/invalid names with expected outcomes

### D.2 — Macro diagnostics compile-fixture coverage (POST-XML-11)
- Add `swift-testing` compile-failure fixtures (or `#expect(throws:)` macro tests) for:
  - `@XMLCodable` applied to invalid target (e.g., non-struct)
  - `@XMLAttribute` with unsupported type
  - `@XMLElement` duplicate on same property
- Ensure diagnostic IDs and messages are deterministic
- Only run on Swift 5.9+ lanes

### D.3 — Advanced temporal support — full XSD family (POST-XML-9) **[DECISION: full coverage in 1.0]**

All XSD temporal shapes must be covered before 1.0.

Types to add (as `Codable`-compatible value types with `XMLDateCodingContext` strategy support):
- `xs:date` (`xsd:date`) — date without time
- `xs:time` (`xsd:time`) — time without date
- `xs:gYear` — year only (e.g. `2024`)
- `xs:gYearMonth` — year + month (e.g. `2024-03`)
- `xs:gMonth` — month only (e.g. `--03`)
- `xs:gDay` — day only (e.g. `---15`)
- `xs:gMonthDay` — month + day (e.g. `--03-15`)
- `xs:duration` — ISO 8601 duration (e.g. `P1Y2M3DT4H5M6S`)

Each type must:
- have a dedicated Swift value type (struct, `Sendable`, `Equatable`, `Hashable`, `Codable`)
- have a corresponding `XMLDecoder.DateDecodingStrategy` case and `XMLEncoder.DateEncodingStrategy` case
- round-trip losslessly (no precision loss on re-encode)
- have dedicated parse/encode tests covering valid values, edge cases, and invalid input rejection

### D.4 — Security hardening documentation
- Document the parser security profile: what each limit does, recommended values for trusted vs untrusted input
- Add a `XMLDocument.Configuration.untrusted()` static factory with conservative defaults
- Test: verify `untrusted()` rejects a deeply nested bomb and a large text node

**Done when:** All D.x items pass tests; `baseline-validation` gates are green.

**Status:** ⏳ Pending

---

## Epic E — Ergonomics

**Goal:** Address developer experience issues that don't break API but improve adoption.

**Steps:**

### E.1 — Macro ergonomics phase 2 (POST-XML-12) **[DECISION: implement in 1.0]**

Implement property-level name override and date format macros. Currently name overrides and date strategies require verbose `@XMLCodable` + `XMLFieldCodingOverrideProvider` conformance.

**Macros to add (all additive, Swift 5.9+ only):**

`@XMLChild("custom-element-name")` — override element name at property level
`@XMLAttribute("custom-attribute-name")` — override attribute name at property level (extend existing macro)
`@XMLDateFormat(.xsdDate)` — declare the XSD date strategy for a specific `Date` property, instead of setting it globally on `XMLEncoder`/`XMLDecoder`

**`@XMLDateFormat` scope:**

- Accepts a `XMLEncoder.DateEncodingStrategy`-compatible value
- Works on properties of type `Date`, `Date?`, and the new XSD temporal types from D.3
- At encode time the per-property strategy overrides the encoder-level strategy
- Parity: `XMLDecoder` must honour the same per-property annotation for decoding

**Done when:** all three macros are implemented with parity tests; `@XMLDateFormat` covers all types introduced in D.3.

### E.2 — Logging integration
**Background:** swift-soap needed request/response debug logging and this was cut short (see insights). swift-xml-coder already depends on `swift-log`.

Tasks:
- Add structured logging to `XMLTreeParser` and `XMLTreeWriter` at `.debug` level:
  - Parser: element open/close events, attribute counts, namespace declarations
  - Writer: element flush events, output byte count
- Add logging to `XMLEncoder`/`XMLDecoder` at `.trace` level for key encode/decode steps
- Logger is injected via `XMLDocument.Configuration` and `XMLEncoder`/`XMLDecoder` configuration (not global)
- Default logger is `SwiftLog.Logger(label: "SwiftXMLCoder")` with `.critical` threshold (silent by default)
- Tests: inject a capturing `LogHandler`, assert messages appear at correct levels

### E.3 — SPM plugin: DocC hosting (optional)
- Evaluate adding a `swift package` command plugin to generate and serve docs locally
- Only if it can be done without adding dependencies
- If not trivial, defer

**Done when:** E.1 decision is made and documented (or implemented); E.2 logging is shipped with tests.

**Status:** ⏳ Pending

---

## Epic G — iOS Support

**Goal:** Make `SwiftXMLCoder` importable on iOS without requiring external dependencies or a separate parser backend, if technically feasible.

**Background:**

libxml2 is a system library on all Apple platforms, including iOS — it ships in every iOS SDK and has no App Store restrictions. The current blocker is purely at the SPM manifest level: `pkgConfig: "libxml-2.0"` fails on iOS SDKs because `.pc` files are not present. The `module.modulemap` already contains `link "xml2"`, which is the correct linker flag on iOS.

All libxml2 API calls used in this library (`xmlReadMemory`, `xmlDocDumpFormatMemoryEnc`, DOM tree, XPath) are present and unrestricted on iOS.

**Approach — two tracks:**

### G.1 — Track 1: iOS-compatible module map (preferred)

**Goal:** Enable iOS without pkgConfig, without changing any parser code.

Tasks:
- Add `iOS(.v15)` to the `platforms` array in all manifests (`Package@swift-5.6.swift` and later)
- Modify `Sources/CLibXML2/module.modulemap` to support both the pkgConfig-resolved path (macOS/Linux) and the iOS SDK path:
  - macOS/Linux: headers at `<libxml2/libxml/...>` via pkgConfig include dirs
  - iOS: headers at `/usr/include/libxml2/libxml/...` (embedded in Xcode iOS SDK)
  - Option: use a conditional include via `#if __APPLE__` in `CLibXML2.h` or a separate `module.modulemap` per platform using SPM's `path` parameter
- Verify `swift build -destination "generic/platform=iOS"` succeeds on a macOS host
- Add iOS to the CI matrix (A.1): single job `swift build` for iOS (`generic/platform=iOS Simulator`), no test run required (Simulator boot is too slow for CI matrix)
- Tests: all existing tests must pass unchanged on the Simulator

**Done when:** `swift build -destination "generic/platform=iOS Simulator"` succeeds with zero errors; iOS job is green in CI.

### G.2 — Track 2: Foundation.XMLParser fallback backend (only if Track 1 fails)

**Activate only if:** Track 1 is not viable (e.g., Apple removes libxml2 headers from a future iOS SDK, or App Store review rejects the private framework link).

**Goal:** Provide a pure-Swift XML parser/writer backend for iOS using `Foundation.XMLParser` (SAX-style) and `Foundation.XMLDocument` (macOS/iOS 15+).

Scope:
- Introduce `XMLBackend` internal protocol with two conformances:
  - `LibXML2Backend` — current implementation, used on macOS/Linux
  - `FoundationBackend` — new implementation using `Foundation.XMLParser` + `XMLDocument`
- Switch via `#if os(iOS) || os(watchOS) || os(tvOS)` conditional compilation
- Public API surface (`XMLTreeParser`, `XMLTreeWriter`, `XMLDocument`, `XMLEncoder`, `XMLDecoder`) remains identical — the backend swap is entirely internal
- XPath: `Foundation.XMLDocument.nodes(forXPath:)` covers the current XPath API surface
- Canonicalization: `XMLDefaultCanonicalizer` must produce identical output regardless of backend — verify with existing contract tests
- Tests: all 243 existing tests must pass on both backends

**Constraints:**
- `Foundation.XMLDocument` is only available on macOS 10.13+ and iOS 15+ — enforce via `@available` checks
- Do not introduce a new public API; the backend choice is an implementation detail
- `SwiftXMLCoderTestSupport` must remain usable on iOS

**Done when:** All 243 tests pass on iOS Simulator via Foundation backend; canonicalization fixtures are identical between backends; Track 2 is activated only if Track 1 is explicitly rejected.

### G.3 — Platform declaration and manifest audit

Regardless of which track lands:
- Add `iOS(.v15)` (Track 1) or `iOS(.v15)` with Foundation conditional (Track 2) to all manifests
- Add `tvOS(.v15)` and `watchOS(.v8)` if they fall out for free from whichever track is used
- Update README compatibility table
- Update DocC `Articles/Compatibility.md`

**Sequencing:**

Epic G is **independent** of C/D/E and can run in parallel with them. It must complete before F.
Start with Track 1. If Track 1 succeeds within one session, Track 2 is skipped entirely.

**Status:** ⏳ Pending — Track 1 not yet attempted

---

## Epic F — Release 1.0

**Goal:** Tag and publish 1.0.0.

**Steps:**

### F.1 — Pre-release checklist
- [ ] All epics A–E are ✅ Done
- [ ] `swift build -c debug` green on all platforms
- [ ] `swift test --enable-code-coverage` green, coverage ≥ 85% on core module
- [ ] `swiftlint lint` zero warnings
- [ ] DocC builds with zero warnings
- [ ] README renders correctly
- [ ] CHANGELOG `[Unreleased]` section is complete and accurate

### F.2 — Version bump
- Update all Package manifests if they have explicit version references
- Set `[Unreleased]` → `[1.0.0] — YYYY-MM-DD` in CHANGELOG.md

### F.3 — GitHub Release
- Tag: `1.0.0`
- Title: `SwiftXMLCoder 1.0.0`
- Body: content from CHANGELOG `[1.0.0]` section

### F.4 — swift-soap dependency update
- After 1.0 tag is published, update swift-soap's `Package@swift-5.6.swift` (and other manifests) to `from: "1.0.0"`
- This is in the swift-soap repo, out of scope for this plan — flag to Matteo

**Done when:** `1.0.0` tag is visible on GitHub; DocC is hosted; swift-soap can import.

**Status:** ⏳ Pending

---

## Post-1.0 Backlog (from swift-soap epic-6b)

These are deferred — do NOT include in 1.0 scope.

| ID | Title | Why deferred |
|----|-------|-------------|
| POST-XML-1 | Streaming parser/writer | Major API addition, needs design |
| POST-XML-2 | XML Signature-grade canonicalization | Architecture ready, engines TBD |
| POST-XML-3 | Full structural fidelity (PI/doctype) | Non-blocking for 1.0 use cases |
| POST-XML-4 | Security hardening phase 2 | Phase 1 already ships; fuzz needs time |
| POST-XML-5 | Pre-serialization output budgeting | Optimization, not a correctness issue |
| POST-XML-8 | MTOM/XOP + SwA multipart | Major feature, transport concern |
| POST-XML-13 | XMLDSig library | Separate library, depends on POST-XML-2 |

---

## Dependencies Between Epics

```
A (CI) must be done before F (can't release without CI)
B (Docs) must be done before F
C (API Review) must be done before D, E, F — breaking changes first
D, E can run in parallel after C
G (iOS) is independent of C/D/E — can run in parallel; must complete before F
F is last
```

Recommended execution order: **A → B → C → D+E+G (parallel) → F**

---

## Branch Naming

Each epic uses: `claude/epic-<letter>-<slug>`

Examples:
- `claude/epic-a-ci-infrastructure`
- `claude/epic-b-documentation`
- `claude/epic-c-api-review`
- `claude/epic-d-quality-hardening`
- `claude/epic-e-ergonomics`
- `claude/epic-g-ios-support`
- `claude/epic-f-release-1.0`

---

## Status Tracking

| Epic | Title | Status | Notes |
|------|-------|--------|-------|
| A | CI/CD Infrastructure | ✅ Done | commit 06f6909 — CI matrix, SwiftLint, DocC stub, coverage |
| B | Documentation | ⏳ Pending | No DocC catalog, no README |
| C | API Review & Breaking Changes | ⏳ Pending | Must complete before D, E, G, F |
| D | Quality & Hardening | ⏳ Pending | Depends on C |
| E | Ergonomics | ⏳ Pending | Depends on C |
| G | iOS Support | ⏳ Pending | Independent of C/D/E; Track 1 (module map) first, Track 2 (Foundation backend) only if Track 1 fails |
| F | Release 1.0 | ⏳ Pending | Last; depends on all epics |
