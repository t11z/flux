# CLAUDE.md

> Behaviour, conventions, and wayfinding for this repository.
> This file never duplicates architecture decisions or other volatile facts — those live in `docs/decisions/` as smADRs. Keep this file from becoming a maintenance burden.

## Project

`flux` — a lightweight, extensible firewall GitOps automation skeleton that demonstrates configuration-as-code patterns for Palo Alto Panorama.

## Language regime

- Conversation with the architect: in the architect's language.
- Repository artifacts (code comments, documentation, issues, pull requests, commit messages, ADRs, this file): **English**, consistently.

## Architecture decisions

Architecture lives in `docs/decisions/` as Structured MADR (smADR). Write an ADR when a decision:

- is hard to reverse, or
- spans multiple layers, a public interface, or a contract, or
- pins an invariant, a provider, or a stack building block, or
- displaces a plausible alternative worth recording.

Do **not** write an ADR for implementation details, local refactors, naming, helper structures, or test layout — those are settled in code review and, where stable, captured here.

When unsure, open an ADR in `proposed` status. ADRs are append-only: once `accepted`, supersede instead of editing.

## Authentication

This project authenticates Claude tooling via `CLAUDE_CODE_OAUTH_TOKEN`, never `ANTHROPIC_API_KEY`. See `SETUP.md` for secret setup.

## Conventions

- **Panorama interface is the XML-API only.** The XPath-based XML-API is the source of truth and the only interface flux targets (it is what the panos Terraform/pango modules speak). Do not introduce the REST API. See `docs/decisions/`.
- **The schema is bound to a PAN-OS version.** `schema/panorama-schema.json` carries `panosVersion`; rebuild it with `tools/build-schema.ps1` and keep `schema/source-info.json` in sync with the box it was derived from.
- **Two languages, two roles.** Discovery/seeding against a live Panorama is PowerShell (`tools/*.ps1`); the "validate before apply" gate is Python stdlib-only (`tools/validate_config.py`) so it runs dependency-free in the GitLab runner.

## Wayfinding

- `docs/decisions/` — architecture decision records (smADR). Start at `docs/decisions/README.md`.
- `docs/IMPLEMENTATION-LOG.md` — dated working log; `docs/panorama-xpath-map.md` — supported XPaths.
- `tools/` — XML-API wrapper, seeding, probing, schema compiler, validator (see `tools/CLAUDE.md`).
- `mock/` — stdlib mock Panorama XML-API server for end-to-end pipeline runs (see `mock/CLAUDE.md`).
- `schema/` — `panorama-schema.json` (source of truth), `fixtures/`, `constraints/`, `versions/`.
- `.claude/commands/` — slash commands: `/adr-new`, `/security-review`.
- `.claude/agents/` — subagents: `adr-author`, `security-reviewer`.
- `.github/workflows/` — CI, smADR validation, security review, issue triage.
