# Security Policy

ASH takes security seriously.

This document describes:
- how to report security vulnerabilities
- what kinds of issues are in scope
- what reporters can expect
- the project’s security posture and limitations

ASH is an experimental, security-focused project.  
Transparency and responsible handling of vulnerabilities are core values.

---

## Reporting a Vulnerability

If you believe you have found a security vulnerability in ASH, please report it **privately**.

### How to report

- **Email:** security@ash.app (replace with actual address before release)
- **Subject:** `[ASH Security] Vulnerability report`
- **Include:**
  - a clear description of the issue
  - affected component(s)
  - steps to reproduce (if applicable)
  - potential impact
  - any proof-of-concept (optional)

Please do **not**:
- open a public GitHub issue for security vulnerabilities
- disclose the issue publicly before coordination
- attempt to exploit the issue beyond proof-of-concept

---

## Response Process

We aim to follow a responsible disclosure process:

1. **Acknowledgment**
   - We will acknowledge receipt within **72 hours**.

2. **Initial assessment**
   - We will assess severity, scope, and impact.

3. **Mitigation**
   - We will work on a fix or mitigation if the issue is valid.

4. **Disclosure**
   - We will coordinate disclosure timing with the reporter where possible.

ASH is a small project; response times may vary, but reports will be handled in good faith.

---

## Scope of Security Review

### In scope

The following components are considered **in scope** for vulnerability reporting:

- Shared Rust core (`ash-core`)
- Cryptographic logic (OTP handling, pad consumption, framing)
- Ceremony implementation
- iOS application logic
- Backend relay implementation
- Data lifecycle handling
- Incorrect security claims or misleading behavior

---

### Explicitly out of scope

The following are **out of scope** and generally will not be considered vulnerabilities:

- Compromised operating systems or jailbroken/rooted devices
- Physical device seizure or forensic analysis
- Malicious conversation participants
- Screenshots, screen recording, or user recording behavior
- Social engineering of users
- Denial-of-service attacks without clear security impact
- Traffic analysis and metadata leakage
- Platform or OS-level vulnerabilities
- Third-party service outages (APNS, hosting providers)

These limitations are documented in `docs/threat-model.md`.

---

## Security Guarantees (What ASH Claims)

ASH makes **limited and explicit** security guarantees:

- Message confidentiality against network and backend observers
- Information-theoretic security using One-Time Pad (when used correctly)
- Strict pad non-reuse enforced by design
- Detection of accidental corruption
- Human-verifiable ceremony correctness
- Minimal trusted infrastructure

ASH does **not** claim:
- anonymity at the network level
- resistance to device compromise
- protection against malicious participants
- forensic-level secure deletion
- perfect forward secrecy beyond OTP semantics

---

## Dependencies and Updates

- The shared Rust core aims to minimize dependencies.
- Dependencies are reviewed before inclusion.
- Security updates are applied deliberately, not automatically.

If a dependency introduces a security risk, it will be evaluated and addressed based on impact.

---

## Security Best Practices for Contributors

Contributors are expected to:

- respect documented trust boundaries
- avoid adding hidden persistence
- avoid introducing analytics or tracking
- avoid logging sensitive data
- follow the architecture and threat model
- add tests for any security-relevant changes

Security-relevant changes must include:
- rationale
- threat impact analysis
- tests where applicable

---

## Ethical Use and Misuse Concerns

ASH explicitly acknowledges the potential for misuse of secure communication tools.

The project:
- does not aim to enable abuse
- does not provide anonymity guarantees
- does not support covert mass communication
- includes clear documentation of limitations

Ethical considerations are documented in `/docs/ethics.md`.

---

## Final Note

ASH values **honest security over marketing claims**.

If a security property is unclear or undocumented,  
it should be treated as **not guaranteed**.

Responsible disclosure helps improve the project for everyone.