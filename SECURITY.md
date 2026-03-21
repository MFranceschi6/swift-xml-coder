# Security Policy

## Supported Versions

Security fixes are applied to the **latest released minor version** on the
`main` branch. Older minor versions do not receive backported patches.

| Version | Supported |
|---------|-----------|
| 1.x (latest) | Yes |
| < 1.0 | No |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report security issues by emailing:

**matteo.franceschi6@gmail.com**

Include in your report:

- A description of the vulnerability and its potential impact.
- Steps to reproduce or a minimal proof-of-concept.
- The affected version(s).
- Any suggested mitigations you may have identified.

You will receive an acknowledgement within **72 hours**.
We aim to release a patch within **14 days** for critical vulnerabilities
and **30 days** for lower-severity issues, depending on complexity.

We will credit reporters in the release notes unless you prefer to remain
anonymous.

## Scope

Issues in scope include, but are not limited to:

- XML parser denial-of-service (billion laughs, deep nesting, large payloads)
  bypassing the hardening limits in `XMLTreeParser`.
- Memory safety violations (use-after-free, buffer overflows) in the
  libxml2 bridging layer.
- Information disclosure through error messages or log output.
- Behaviour differences between the documented security limits and their
  actual enforcement.

Out of scope: issues in libxml2 itself should be reported to the
[libxml2 project](https://gitlab.gnome.org/GNOME/libxml2/-/issues).
