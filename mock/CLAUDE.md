# CLAUDE.md — mock

> Conventions, rules, and wayfinding specific to `mock/`.
> No repetition of root rules. No architecture — that lives in `docs/decisions/`.

## Scope

A stdlib-only mock Panorama XML-API server:
- `panorama_mock.py` — the server (http.server + ElementTree in-memory config).
- `test_mock.py` — end-to-end tests driven over HTTP.

## Local conventions

- Stdlib only; no pip dependencies (it must run in the runner like the validator).
- Reuse `tools/validate_config.py` for all schema checks — never reimplement validation here, or
  the mock and the gate will drift. Use the finding `phase` (`set` vs `commit`) to decide whether a
  violation blocks a `set` or only a `commit`/`validate full`.
- Keep responses shaped like the real device (`<response status="...">`, nested `<msg><line>`,
  job results under `response/result/job`) so the existing tooling can parse them.
- State is in-memory by design; do not add a database. `--seed` loads a starting candidate.

## Wayfinding

- The schema and its behavioural notes live under `../schema/`.
