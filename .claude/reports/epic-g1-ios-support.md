# Step Report — Epic G.1: iOS Support (Track 1)

## Scope

- **Task:** Add iOS, tvOS, and watchOS platform support via Track 1 (libxml2 system library via Xcode SDK sysroot)
- **Boundaries:** Manifest declarations, CI workflow, README, DocC Compatibility article. No changes to source code, C headers, or module maps.

## Public API Changes

- **Added:** None — no public API surface changed.
- **Changed:** None.
- **Deprecated/Removed:** None.

## Implementation Notes

### Core logic

libxml2 is a system library embedded in every Apple platform SDK (iOS, tvOS, watchOS, macOS). The Xcode toolchain passes `-isysroot <sdk-path>` when cross-compiling, which causes Clang to resolve `#include <libxml/parser.h>` (and the other five libxml2 includes in `CLibXML2.h`) through the sysroot's `usr/include/libxml/` directory automatically.

The `link "xml2"` directive in `Sources/CLibXML2/module.modulemap` is the correct linker flag for all Apple platforms including iOS.

The `pkgConfig: "libxml-2.0"` declaration on the `CLibXML2` target silently no-ops on iOS cross-compile builds (SPM 5.6+ emits a warning but does not fail). On macOS and Linux, pkgConfig continues to add the necessary `-I` include paths for Homebrew and apt-installed libxml2 respectively.

### Edge cases handled

- `Package.swift` (swift-tools-version: 5.4, runtime stub) intentionally left unchanged — the `platforms` API is not available in tools version 5.4.
- `Sources/CLibXML2/module.modulemap` and `Sources/CLibXML2/include/CLibXML2.h` left unchanged — `__has_include` dual-path guarding was considered but is unnecessary because both macOS and iOS SDKs expose `<libxml/parser.h>` via standard sysroot search.
- tvOS and watchOS included (fall out for free via same sysroot mechanism; verified locally).

### Internal trade-offs

- Track 2 (Foundation.XMLParser backend) skipped entirely — Track 1 compiles cleanly and is simpler.
- No `#if os(iOS)` guards added to Swift source — the library is platform-agnostic at the source level.

## Validation Evidence

- **iOS Simulator build:** `swift build --triple arm64-apple-ios15.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"` → `Build complete! (4.41s)` — 61 compilation units, zero errors, zero warnings.
- **macOS debug build:** `swift build -c debug` → `Build complete! (1.22s)`
- **Tests:** 371 tests, 0 failures
- **Lint:** 187 warnings (all pre-existing nesting/trailing-comma violations in test files; zero new violations from this epic's changes)

## Risks and Follow-ups

- **Residual risks:** None identified. CI will be the authoritative gate once the `ios-simulator` job runs on a PR.
- **Non-blocking follow-ups:**
  - tvOS/watchOS CI jobs (build-only) could be added in the future if needed for badges; currently only iOS Simulator is gated.
  - `@available` annotations are not yet needed on any public API (all libxml2 APIs used are available on iOS 8+).
  - swift-soap's manifests should declare iOS after SwiftXMLCoder 1.0 ships (out-of-scope, flagged to Matteo per plan).