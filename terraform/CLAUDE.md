# CLAUDE.md — terraform

> Conventions and wayfinding specific to `terraform/`.
> No repetition of root rules. No architecture — that lives in `docs/decisions/`.

## Scope

Terraform for the Phase 3 use cases, driven by the official **panos v2** provider over the
XML-API (ADR-0005). The root composes three independently reusable modules:

- `modules/dg_app_publish` — UC1: address objects + service + security rule (device group).
- `modules/template_network` — UC2: ethernet interface + zone + virtual router (template).
- `modules/dg_nat_interplay` — UC3: a NAT rule referencing the template's zone/interface.

The root is **data-driven**: the full desired config lives in git under `desired/`
(`network.yaml` singleton + `apps/*.yaml` + `nat/*.yaml`); the root reads them with
`fileset()`+`yamldecode()` and `for_each`-es the app/NAT modules (keyed by record name, so a
change touches only that object). State is **persistent and authoritative** (ADR-0006).

Vocabulary (post data-driven model): **module = a *kind* of capability** (reusable);
**record = one *instance*** under `desired/`. The three are no longer symmetric:
`template_network` is the **singleton** scaffolding of the coupled Template↔Device-Group unit,
while `app_publish`/`nat_interplay` are **collections** (0..N records). The three use cases are
**reference patterns**; adding more is the documented path to full coverage — see
`../examples/gitlab/EXTENDING.md`.

## Local conventions

- Provider pinned `~> 2.0`. **Every module** declares its own `required_providers`
  (`panos = PaloAltoNetworks/panos`) or Terraform resolves it to the wrong namespace.
- Resources select their XPath container via `location { panorama | device_group | template }`.
  Policy rules use the `*_rules` form (`location` + `position` + a `rules` list).
- A `panos_template_stack` sets `default_vsys` so the provider emits the `<settings>` element
  PAN-OS requires at commit.
- The device group binds the template stack (`panos_device_group.templates`) so device-group
  rules can resolve the template's zones/interfaces — the UC3 interplay.

- `versions.tf` declares a partial `backend "http" {}` (GitLab-managed state). CI fills it via
  `-backend-config` (`$CI_JOB_TOKEN`); `validate` uses `init -backend=false`. Locally, plan offline
  with a gitignored `backend_override.tf` (`backend "local" {}`) or a `*.backendrc`.

## Run it

Against the mock (no device): `python mock/panorama_mock.py --port 8080`, then (with a local
backend override) `terraform init && terraform apply -var-file=mock.tfvars.example`. Connection
config comes from `*.tfvars`/`TF_VAR_panos_*`; the **desired** config is `desired/` (not variables).
State management (backend, drift, import, RBAC, lab-vs-mock) is documented in
`../examples/gitlab/STATE-MANAGEMENT.md`; the delivery pipeline lives in `../examples/gitlab/`.
