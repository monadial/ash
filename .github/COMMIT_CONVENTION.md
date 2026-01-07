# Commit Convention

This project follows [Conventional Commits](https://www.conventionalcommits.org/).

## Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Code style (formatting, semicolons, etc.) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or external dependencies |
| `ci` | CI/CD configuration |
| `chore` | Other changes that don't modify src or test files |
| `revert` | Reverts a previous commit |
| `security` | Security-related changes |

## Scopes

| Scope | Description |
|-------|-------------|
| `core` | Core Rust library (`core/`) |
| `ios` | iOS application (`apps/ios/`) |
| `backend` | Backend relay server (`backend/`) |
| `bindings` | FFI bindings (`bindings/`) |
| `website` | Documentation website (`website/`) |
| `infra` | Infrastructure (`infra/`) |
| `deps` | Dependencies |

## Examples

```
feat(core): add fountain code encoder

fix(ios): resolve crash on QR scan timeout

ci: add release workflow for automated deployments

docs: update threat model with relay attack vectors

chore(deps): bump astro to 5.16.6
```

## Breaking Changes

Add `!` after type/scope or include `BREAKING CHANGE:` in footer:

```
feat(core)!: change pad format to v2

BREAKING CHANGE: Pads created with v1 are no longer compatible.
```
