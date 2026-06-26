# CLAUDE.md — terraform

> Conventions and wayfinding specific to `terraform/`.
> No repetition of root rules. No architecture — that lives in `docs/decisions/`.

## Scope

Terraform for the Phase 3 use cases, driven by the official **panos v2** provider over the
XML-API (ADR-0005). The root config composes three independently reusable modules:

- `modules/dg_app_publish` — UC1: address objects + service + security rule (device group).
- `modules/template_network` — UC2: ethernet interface + zone + virtual router (template).
- `modules/dg_nat_interplay` — UC3: a NAT rule referencing the template's zone/interface.

## Local conventions

- Provider pinned `~> 2.0`. **Every module** declares its own `required_providers`
  (`panos = PaloAltoNetworks/panos`) or Terraform resolves it to the wrong namespace.
- Resources select their XPath container via `location { panorama | device_group | template }`.
  Policy rules use the `*_rules` form (`location` + `position` + a `rules` list).
- A `panos_template_stack` sets `default_vsys` so the provider emits the `<settings>` element
  PAN-OS requires at commit.
- The device group binds the template stack (`panos_device_group.templates`) so device-group
  rules can resolve the template's zones/interfaces — the UC3 interplay.
- `var.flux_module` (`all` | `template_network` | `app_publish` | `nat_interplay`) selects which
  use case a run touches; `main.tf` `locals` translate it into `count` on each module/resource.
  A dependent use case auto-enables its prerequisites (`want_app`/`want_nat` ⇒ `want_dg` ⇒
  `want_template`), so the `[0]` cross-references stay in range. Default `all` = the original
  apply-everything behavior. The ITSM trigger sets it via `TF_VAR_flux_module`
  (see `../examples/gitlab/ITSM-TRIGGER.md`).

## Run it

Against the mock (no device): `python mock/panorama_mock.py --port 8080`, then
`terraform apply -var-file=mock.tfvars.example`. Against a real Panorama: use
`panorama.tfvars.example` and supply credentials via `TF_VAR_panos_*`.
State is local and gitignored; the delivery pipeline lives in `../examples/gitlab/`.
