# flux - implementation log

Dated working log (chronology / what + why). Architectural decisions also live as smADRs under
`docs/decisions/`. Granular history = Git (Conventional Commits).

## 2026-06-24 - Phase 1: Panorama discovery, schema & validator

**Goal.** Derive a complete schema of the Panorama XML configuration from the live API and build
a lightweight "validate before apply" gate from it.

**Done.**
- Verified the live Panorama: **12.1.2**, `management-only`, `192.168.99.2` (XML-API reachable,
  keygen/get/op work).
- XML-API wrapper `tools/pan-api.ps1` (PowerShell + curl): keygen, config get/show/set/edit/delete, op.
- Seeding `tools/seed-fixtures.ps1`: created representative objects (address, service, address-group,
  device-group, security-rule, template, template-stack), read them back, stripped bookkeeping
  attributes -> canonical fixtures under `schema/fixtures/`. Also records `schema/source-info.json`
  (PAN-OS version/model/hostname) so the schema is bound to that version.
- Constraint probing `tools/probe-constraints.ps1`: invalid `set` calls -> PAN-OS error messages.
  **Finding:** `set` enforces enums/format/unknown elements, but **not** required fields and **not**
  choice cardinality - those apply at commit. -> `schema/constraints/probe-results.md`.
- Schema compiler `tools/build-schema.ps1` -> `schema/panorama-schema.json` (single source of truth),
  stamped with the live PAN-OS version, archived under `schema/versions/`. Consistency check vs fixtures.
- **Validator `tools/validate_config.py` (Python, stdlib-only)** - deliberately not PowerShell, so the
  gate runs dependency-free in the GitLab runner (Linux). Checks allowedChildren, required, choice
  (oneOf), enums, formats, member lists (recursively). Choice semantics: zero -> error, more-than-one
  -> warning (matches PAN-OS, which keeps one). Optional `--panos-version` enforces the schema binding.
- Regression `tools/test_validator.py`: 14/14 green.
- **Comparison vs Panorama's own validation** `tools/compare-validation.ps1`: runs every fixture through
  both flux and Panorama's two layers (`set` + `validate full`). **Result: 13/13 agree, 0 mismatches.**
  Reconciled three initial divergences: device-group (harness `revert` glitch -> delete-isolation),
  two-address-types (warning/parity), template-stack (`settings` required at commit).

**Repo bootstrap (cc-project-bootstrap, full).** Applied the plugin: CLAUDE.md hierarchy
(`CLAUDE.md`, `tools/CLAUDE.md`), smADR scaffold in `docs/decisions/`, `.claude/` commands/agents/
ADR-skill, `.github/` workflows (CI adapted to the flux stack: Python tests + schema-drift check;
security-review, adr-validate, issue-triage) with SHA-pinned actions, issue/PR templates,
Dependabot, `SETUP.md`. AIRS declined. Recorded the core architecture decisions as **smADR
0001-0003** (XML-API only · version-bound schema as source of truth · GitHub dev / GitLab
runtime). Implementation/tooling choices (validator language, adopting the bootstrap) were
intentionally left out of the ADR set as non-architectural.

**Open / next.**
- Architect: configure CI secrets per `SETUP.md` (`CLAUDE_CODE_OAUTH_TOKEN`, GitHub App).
- Later phases: mock Panorama server, Terraform modules, GitLab pipeline (`examples/gitlab/`).

**Two-layer model.** flux is *developed* on **GitHub** (repo CI). The *delivered/demonstrated* GitOps
runs on **GitLab + a local runner** (skeleton templates in the repo).
