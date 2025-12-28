# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ASH is a secure, ephemeral messaging application for high-security, low-frequency communication. It uses One-Time Pad (OTP) encryption with no key recovery, no key escrow, and minimal infrastructure trust.

## Architecture

ASH consists of four subsystems:

```
Users → iOS App (SwiftUI) → ash-core (Rust) → Backend (Rust Relay)
```

### ash-core (Shared Rust Core)
The cryptographic authority. Handles OTP creation/consumption, pad enforcement, encryption/decryption, ceremony rules, frame encoding, and mnemonic checksums.

**Must never:** access network, perform I/O, access OS randomness directly, contain platform-specific code, store data, include UI logic, log sensitive data.

### iOS Application (SwiftUI)
Presentation and orchestration layer. Invokes ash-core, manages UI, handles QR code display/scanning.

**Must never:** reimplement cryptography, bypass ash-core, persist decrypted messages.

### Backend (Rust Relay)
Untrusted stateless relay. Accepts/relays encrypted blobs, propagates burn signals, sends silent push notifications. TTL-based ephemeral storage only.

**Must never:** decrypt messages, identify users, store data long-term.

## Trust Boundaries

| Component | Trust Level |
|-----------|-------------|
| ash-core | Trusted |
| iOS App | Partially trusted |
| Backend | Untrusted |
| Network | Untrusted |

## Core Principles (Non-negotiable)

- OTP only (no other encryption)
- No key escrow/recovery
- No crypto agility
- No silent background behavior
- No hidden persistence
- No reliance on backend trust

## Security Considerations for Contributors

- Respect documented trust boundaries
- No hidden persistence or analytics
- No logging sensitive data
- Security-relevant changes require rationale, threat impact analysis, and tests
- If a security property is unclear or undocumented, treat it as not guaranteed

## Key Documentation

- `docs/scope.md` - v1 feature scope (what's in/out)
- `docs/architecture.md` - Component boundaries and data flows
- `docs/thread-model.md` - Explicit threat model and security guarantees
- `docs/backend-contract.md` - Backend API invariants and TTL policies
- `SECURITY.md` - Vulnerability reporting process
