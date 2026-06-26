# Extending flux — adding a use case

flux is a **half-mature GitOps skeleton**, not a finished product. It ships with **three reference
use cases** that demonstrate typical daily firewall-admin work:

- **publish an application** (`dg_app_publish`) — device-group address objects + service + security rule
- **template network config** (`template_network`) — interface + zone + virtual router (the Template dimension)
- **NAT interplay** (`dg_nat_interplay`) — a NAT rule that references the template's zone/interface

They are **patterns to copy**, not the limit. The end goal is that, once you have modelled the
objects you care about, flux **authoritatively manages your whole Panorama** as code. You get there
by adding use cases. This is the recipe.

## Vocabulary

- **module** = a *kind* of capability (app-publish, template-network, NAT). Reusable.
- **record** = one *instance* in `terraform/desired/` (one published app, one NAT rule).
- `template_network` is the **singleton** scaffolding of the coupled Template↔Device-Group unit;
  `apps/` and `nat/` are **collections** (0..N records). A new use case is usually a new collection.

## Recipe: add use case `X`

1. **Module** — create `terraform/modules/<x>/` with its own `versions.tf`
   (`required_providers { panos = PaloAltoNetworks/panos }`), `variables.tf`, `main.tf`
   (resources select their container via `location { panorama | device_group | template }`), and
   `outputs.tf`. Model **named** objects (the name is the record key).
2. **Schema coverage** — teach the validator about X's XPaths/fields: extend
   `schema/panorama-schema.json` (rebuild with `tools/build-schema.ps1`; keep
   `schema/source-info.json` in sync — ADR-0002). Add a valid **and** an invalid fixture under
   `schema/fixtures/` and a case in `tools/test_validator.py`.
3. **Mock parity** — the mock reuses `tools/validate_config.py`, so set-time vs commit-time checks
   come for free; add a `mock/test_mock.py` assertion only if X has special device behaviour.
4. **Desired-state kind** — add `terraform/desired/<x>/` (one YAML record per object) and a
   `for_each` block in `terraform/main.tf` that maps records → your module, reading any foundation
   outputs it needs (`module.template_network.zone_name` / `.interface_name`,
   `panos_device_group.dg.name`).
5. **Converge** — `terraform plan` now shows only X's objects; the full converge stays consistent,
   and `commit` + the scheduled `drift` job cover X automatically.

That is the whole deliverable shape: **framework + 3 examples + this recipe.** Everything you add
joins one authoritative state and the same validate→plan→apply→commit→drift discipline.

## Authoritative-ownership note

flux's converge is **authoritative over the objects it models**. Two implications as you extend:

- **Ordered rulebases:** `panos_security_policy_rules` / `panos_nat_policy_rules` own an *ordered
  list* at a rulebase position. As you bring a position under flux, model **all** rules for that
  position in `desired/` (or scope the position) — flux's authoritative converge will otherwise plan
  to remove rules it doesn't know about. That is the *intended* end state (flux owns it), but it
  must be a deliberate step, not a surprise.
- **Coverage is the boundary:** flux only manages what it models. Objects/kinds you have not added
  yet are simply outside flux's scope — untouched and not drift-checked — until you extend it.
