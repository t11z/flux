# flux - implementation log

Dated working log (chronology / what + why). Architectural decisions also live as smADRs under
`docs/decisions/`. Granular history = Git (Conventional Commits).

## 2026-06-24 - Phase 1: Panorama discovery, schema & validator

**Goal.** Derive a version-bound schema of the **flux-relevant** Panorama XML resources from the
live API (a curated subset per ADR-0002, **not** the entire config tree) and build a lightweight
"validate before apply" gate from it.

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

## 2026-06-24 - Phase 2: Mock Panorama server

**Goal.** A lightweight mock Panorama (XML-API) so the pipeline can run end to end without a real,
licensed device.

**Done.**
- Refactored `tools/validate_config.py`: findings now carry a `phase` (`set` vs `commit`), and a
  reusable `validate_entry()` / `load_schema()` API. CLI behaviour unchanged (14/14 still green).
- `mock/panorama_mock.py` (Python stdlib `http.server`): keygen, config set/edit/get/show/delete,
  op (`show system info`, `validate full` + job poll, `commit`), in-memory candidate/running trees,
  optional `--seed`, and an audit log. Set-time violations are rejected on `set`; required/choice
  checks run at `validate full` / `commit` — mirroring the real device. Validation reuses the gate,
  so the mock and the gate never drift (ADR-0004).
- `mock/test_mock.py`: end-to-end over HTTP, **13/13 green** (set-time rejection, accept-incomplete,
  validate-full catches missing port, commit -> running, delete, system info). Added to CI.

**Open / next.**
- Later phases: Terraform modules driving the mock, GitLab pipeline (`examples/gitlab/`),
  optional TLS on the mock so the PowerShell `pan-api.ps1` (HTTPS) can target it directly.

## 2026-06-25 - Phase 3a: extend schema coverage for the panos provider use cases

**Goal.** Phase 3 targets the official `PaloAltoNetworks/panos` Terraform provider (v2, XML-API)
for typical firewall-admin use cases spanning **both** Panorama layers: device-group objects/policy
**and** template network config, plus their interplay (a NAT rule referencing a template interface/
zone). The Phase 1 curated subset covered device-group objects/security rules and the template
*shell* only - not the template *interior* (interfaces/zones/virtual-routers) nor NAT rules. The
live Panorama (still 12.1.2) was re-probed to close that gap **the ADR-0002 way** (seed + probe +
compare), rather than hand-curating from docs.

**Done.**
- Re-probed `192.168.99.2` (PAN-OS **12.1.2**, unchanged) and captured canonical fixtures for
  `ethernet-interface`, `zone`, `virtual-router` (template interior) and `nat-rule` (device-group):
  `schema/fixtures/template_interface.xml`, `template_zone.xml`, `template_virtual_router.xml`,
  `template_vsys_import.xml`, `dg_nat_rule.xml`.
- **Findings:** a zone references an interface only once it is **imported into the vsys**
  (`.../vsys/entry/import/network/interface`); interface references are checked **at set time**.
  NAT requires `from/to/source/destination/service` at commit, and NAT `to` cannot be `any`.
  Interface IP is **not** format-checked at set (the `<ip>` entry may be a named object).
- Extended `tools/seed-fixtures.ps1`, `tools/probe-constraints.ps1`, `tools/build-schema.ps1`
  (4 new resources; deep template-interior containers are predicate-stripped) and
  `tools/compare-validation.ps1`. **No validator code change** - the new resources are pure schema
  data (allowedChildren/enums/memberlists/nested/required + phase).
- **Parity re-proven:** `compare-validation.ps1` now **21/21 agree, 0 mismatches**. Validator
  regression `test_validator.py` **22/22**; `mock/test_mock.py` **13/13** (the mock validates the
  new resources automatically via the shared schema).
- **Fixed `tools/pan-api.ps1`:** Windows PowerShell mangled embedded `"` when handing the `element`
  arg to `curl.exe`, so any payload with quoted attributes (e.g. an interface `<ip><entry name=…/>`)
  failed as "Malformed Request". XML-bearing values now go through a temp file (`curl name@file`).
  This never surfaced before because no earlier fixture had a quoted attribute in its body.
- **Schema JSON reformatted to 2-space** (deterministic, via a best-effort Python pretty-print in
  `build-schema.ps1` with a raw fallback; CI compares the schema semantically, so formatting is free).
- Clarified the Phase 1 goal wording above: the schema is a **curated subset** (ADR-0002), never the
  whole config tree.

**Open / next.** Phase 3b: the panos v2 Terraform modules + examples for the three use cases, the
mock's `action=multi-config` handler (the provider batches writes), and the full GitLab pipeline
skeleton (`examples/gitlab/`).

## 2026-06-25 - Phase 3b: Terraform modules (panos v2) + GitLab pipeline

**Goal.** Drive the three use cases through the official `PaloAltoNetworks/panos` **v2** provider
end to end - `terraform apply` against the mock, then commit - and ship the GitLab delivery skeleton.

**Done.**
- **Terraform** (`terraform/`): root composition + three reusable modules — `dg_app_publish`
  (UC1: addresses + service + security rule), `template_network` (UC2: ethernet interface + zone +
  virtual router + template/stack), `dg_nat_interplay` (UC3: NAT rule referencing the template
  zone/interface). The device group binds the template stack, so the device-group NAT rule resolves
  the template's zone — the cross-layer interplay. Provider pinned `~> 2.0`; resources use the v2
  `location { … }` model; rule resources use the `*_rules` (location + position + rules) form.
- **Provider protocol, reverse-engineered against the mock** and confirmed on the live box: auth via
  the **`X-PAN-KEY` header**; version detect via `show system info`; reads via `action=get`; writes
  via `action=set`, and policy-rule resources via **`action=multi-config`** (`<multi-configure-request>`
  batches). `terraform plan` resolves against the live Panorama (12.1.2).
- **Mock upgraded** (`mock/panorama_mock.py`) to be a faithful stand-in for the v2 provider:
  accept the `X-PAN-KEY` header; always return a `<result>` element (code 19 with counts when found,
  code 7 `<result/>` when not — the SDK trips on a bare `<response/>`); a bracket-aware `split_xpath`
  so slash-bearing names (`ethernet1/1`) parse; PAN-OS-correct `edit` (replace-the-node); and an
  `action=multi-config` handler. Set-time validation still runs per op via the shared gate.
  `mock/test_mock.py` extended to **21/21** (header auth, empty-result get, slash names, multi-config).
- **End-to-end against the mock AND the live Panorama (12.1.2):** `terraform apply` creates all
  **12** resources, re-`plan` shows **no drift**, `validate full` is OK (mock also `commit`s). On the
  live box the provider **auto-imports** the interface into the vsys when creating the zone, so
  UC2/UC3 apply on real hardware.
- Two fixes surfaced by the live-box run: (1) the template stack needs `default_vsys` so the
  provider emits the `<settings>` PAN-OS requires at commit, and its `default-vsys` references
  `vsys1` — which only exists once the zone is created — so the stack `depends_on` the zone (else
  Terraform parallelism trips `default-vsys 'vsys1' is not a valid reference`). (2) The GitLab
  pipeline now **verifies TLS by default**; `skip_verify`/`-k` are opt-in via `PANOS_CURL_INSECURE`
  for a self-signed lab only (the API key rides the `X-PAN-KEY` header).
- **GitLab pipeline** (`examples/gitlab/.gitlab-ci.yml` + README): validate → plan → apply → commit,
  runnable against the mock by default, with Bitwarden-secret and ITSM-webhook stubs (ADR-0003).
- **ADR-0005** records the panos v2 / XML-API apply-path decision.

**Open / next.** Optional: TLS on the mock; a CI job that runs the Terraform e2e (needs terraform +
the provider in the runner); more use cases via the documented module pattern.
