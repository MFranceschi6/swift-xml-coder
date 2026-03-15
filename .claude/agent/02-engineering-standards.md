# 02 - Engineering Standards

## API and Design Principles

- Public APIs must be explicit, stable, and documented.
- Prefer clarity over cleverness.
- Keep functions small and responsibilities narrow.
- Avoid hidden side effects.
- Apply minimum access control (`internal` by default, `public` only when intentional).

## File Structure and Naming

- Type declarations should live in `Type.swift`.
- Extended logic should live in separate extension files (`Type+Logic.swift`, `Type+Codable.swift`, etc.).
- Respect one-type-per-file convention unless explicitly exempted.

## Module Layout

| Module | Purpose |
|--------|---------|
| `SwiftXMLCoder` | Core encoder/decoder, tree model, parser, writer, canonicalization |
| `SwiftXMLCoderCShim` | C interop shim for libxml2 |
| `CLibXML2` | System library wrapper for libxml2 |
| `XMLCoderCompatibility` | Cross-version compatibility shims |
| `SwiftXMLCoderOwnership6` | Swift 6.0+ ownership semantics for libxml2 pointers |
| `SwiftXMLCoderMacros` | Public macro facade (`@XMLCodable`, `@XMLAttribute`, `@XMLElement`) |
| `SwiftXMLCoderMacroImplementation` | Macro compiler plugin (swift-syntax) |
| `SwiftXMLCoderTestSupport` | Spy encoders/decoders, contract harness, canonicalizer probes |

## Multi-Version Swift Rules

- Use explicit conditional compilation (`#if swift(>=x.y)`) for syntax/features not available in all active lanes.
- Lane-specific syntax differences must not alter public observable behavior.
- If public behavior can differ due to version-specific syntax, implement explicit cross-version variants and test parity.

## Error Model

- Prefer typed errors (`enum` + `Error`).
- Keep error contracts stable.
- For extensible/public error sets, include a generic fallback case to avoid forced breaking changes.
- Primary error type: `XMLParsingError`.

## Concurrency

- All public types must be `Sendable`.
- Prefer immutable value types (structs) throughout the tree model.
- Avoid unprotected shared mutable state.

## Documentation Language

All source comments and repository documentation must be in English.
