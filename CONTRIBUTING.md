# Contributing to SwiftXMLCoder

Thank you for considering a contribution. This document explains how to
get started, what the standards are, and how to submit your work.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Commit Style](#commit-style)
- [Pull Requests](#pull-requests)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)

---

## Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md).
By participating you agree to abide by its terms.

---

## Getting Started

**Requirements**

- Swift 5.9 or later (Swift 5.4+ for non-macro targets)
- macOS 13+ or Linux (Ubuntu 22.04+)
- `libxml2-dev` on Linux (`apt install libxml2-dev`)

**Clone and build**

```sh
git clone https://github.com/MFranceschi6/swift-xml-coder.git
cd swift-xml-coder
swift build
swift test
```

**SwiftLint (optional but required before PR)**

```sh
brew install swiftlint
swiftlint lint
```

---

## Development Workflow

1. Fork the repository and create a branch from `main`.
2. Branch naming: use `feature/<short-slug>` for new features (e.g. `feature/add-date-decoding`)
   or `fix/<short-slug>` for bug fixes (e.g. `fix/namespace-roundtrip`).
3. Make your changes with tests covering new behaviour and regressions.
4. Run the full validation suite before opening a PR (see [Testing](#testing)).
5. Open a pull request against `main`.

---

## Coding Standards

- **`internal` by default** — use `public` only when intentional.
- **Typed errors** — use `enum` conforming to `Error`; include a generic `.unknown` fallback
  on public error enums.
- **No raw strings** for namespace URIs, element names, or coding keys — use typed enums
  or `static let` constants.
- **No new dependencies** without a documented rationale (problem, alternatives considered,
  license/security review, rollback plan). Open an issue first to discuss.
- **Bug fixes must include regression tests.**
- **Features must cover core behaviour and edge cases.**
- Tests must be deterministic and isolated (no real network, real time, or real filesystem).

---

## Testing

Run the full suite before submitting:

```sh
swift build -c debug
swift test --enable-code-coverage
swiftlint lint
```

All three commands must complete without errors. Warnings in existing files
unrelated to your change are acceptable; do not introduce new ones.

---

## Commit Style

This project uses [Gitmoji](https://gitmoji.dev/) prefixes:

| Prefix | When to use |
|--------|-------------|
| ✨ `feat:` | New user-visible feature |
| 🐛 `fix:` | Bug fix |
| ⚡ `perf:` | Performance improvement |
| ♻️ `refactor:` | Refactor without behaviour change |
| 🧪 `test:` | Adding or fixing tests only |
| 📝 `docs:` | Documentation only |
| 🔧 `chore:` | Build, CI, tooling |
| 🚀 `release:` | Version bump / release commit |

Commit message format:

```
<emoji> <type>: <imperative summary under 72 chars>

<optional body explaining why, not what>
```

---

## Pull Requests

- Fill in the PR template completely.
- Link the related issue if one exists.
- Keep PRs focused — one logical change per PR.
- All CI checks must pass before review.
- A maintainer will review and may request changes before merging.
- PRs are merged via **squash merge** — keep individual commits descriptive but the PR title
  becomes the canonical history entry on `main`.

---

## Reporting Bugs

Open an issue using the **Bug Report** template.
Please include:

- Swift version (`swift --version`)
- OS and version
- A minimal reproducible example
- Expected vs actual behaviour

We aim to respond within **7 days**. Response time may vary during holidays or
high-activity periods.

For security vulnerabilities, see [SECURITY.md](SECURITY.md) instead.

---

## Requesting Features

Open an issue using the **Feature Request** template.
Describe the use case, not just the desired API — this helps us evaluate
the best design before implementation begins.
