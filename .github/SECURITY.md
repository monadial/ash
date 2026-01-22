# Security Policy

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

ASH takes security seriously. If you discover a security vulnerability, we appreciate your help in disclosing it to us responsibly.

### How to Report

Email your findings to: **security@ashprotocol.app**

Please include:

- A description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggested fixes (optional)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
- **Updates**: We will keep you informed of our progress
- **Credit**: We will credit you in our security advisories (unless you prefer to remain anonymous)

### Scope

The following are in scope for security reports:

- ASH iOS application
- ASH cryptographic core (`core/`)
- ASH relay backend (`backend/`)
- ASH website (ashprotocol.app)

### Out of Scope

- Social engineering attacks
- Denial of service attacks
- Issues in third-party dependencies (report these to the respective maintainers)

## Security Model

ASH uses One-Time Pad (OTP) encryption with the following security properties:

- **Information-theoretic security**: Messages cannot be decrypted without the pad, even with unlimited computing power
- **No key escrow**: Keys exist only on user devices
- **Untrusted relay**: The backend server cannot decrypt messages or identify users
- **Forward secrecy**: Each message uses unique key material that is immediately destroyed

For full details, see our [Security page](https://ashprotocol.app/security) and [Whitepaper](https://ashprotocol.app/whitepaper).

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Contact

- Security issues: security@ashprotocol.app
- General support: support@ashprotocol.app
- Legal inquiries: legal@ashprotocol.app
