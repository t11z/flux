# CLAUDE.md — tools

> Conventions, rules, and wayfinding specific to `tools/`.
> No repetition of root rules. No architecture — that lives in `docs/decisions/`.

## Scope

Discovery and validation tooling for the Panorama XML-API:
- `pan-api.ps1` — XML-API wrapper (keygen, config get/show/set/edit/delete, op). Dot-source it.
- `seed-fixtures.ps1` — create sample objects, capture canonical fixtures, record `source-info.json`.
- `probe-constraints.ps1` — set-time constraint probing.
- `build-schema.ps1` — compile `schema/panorama-schema.json` (single source of truth).
- `compare-validation.ps1` — compare the validator against Panorama's own `validate full`.
- `validate_config.py` — the validate-before-apply gate (Python, stdlib-only).
- `test_validator.py` — regression harness for the validator.

## Local conventions

- PowerShell scripts: never persist the password; the API key is fetched at runtime and kept in memory. Credentials come from `$env:PAN_HOST` / `PAN_USER` / `PAN_PASSWORD`.
- When run via `powershell.exe -File`, `$PSScriptRoot` is empty in `param()` defaults — resolve paths in the body (see existing scripts).
- The Python validator stays dependency-free (stdlib only) so it runs in the Linux runner. Keep user-facing messages in English.
- Regenerate the schema with `build-schema.ps1` whenever the curated model or fixtures change; CI checks for drift.

## Wayfinding

- Schema and fixtures live under `../schema/`; behavioural findings in `../schema/constraints/probe-results.md`.
