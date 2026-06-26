# Terraform state management

How flux holds the Panorama configuration as **one authoritative, persistent state**, converged
from a **git source of truth**. This is the model for running against a **real** Panorama; the mock
is only a stand-in (made durable so the demo is honest). See
[ADR-0006](../../docs/decisions/0006-authoritative-persistent-state.md).

## The model in one picture

```
git: terraform/desired/        ──►  terraform apply (full converge)  ──►  Panorama (one config)
  network.yaml  (template+DG)        one GitLab-managed state             candidate ──<commit>──► running
  apps/*.yaml   (one per app)        for_each over records                ▲
  nat/*.yaml    (one per rule)                                            └─ scheduled drift plan = "No changes"
```

- **Desired state = git.** Everything flux manages is declared under `terraform/desired/`. Apply
  converges the **whole** set; the device is a projection of git.
- **One state, not many.** A Panorama has ONE consistent config and one (scopeable) commit.
  Splitting state per use case is wrong — every state would write the same candidate. flux keeps
  **one** GitLab-managed state for the coupled Template+Device-Group unit.
- **`for_each`, not `count`.** Records are keyed by name, so adding/editing/removing one app or NAT
  rule touches **only that object** — it never destroys a sibling.

## Backend: GitLab-managed Terraform state (HTTP)

`terraform/versions.tf` declares a partial `backend "http" {}`. CI fills address + auth at `init`:

```bash
terraform init -input=false \
  -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}" \
  -backend-config="lock_address=.../${STATE_NAME}/lock" \
  -backend-config="unlock_address=.../${STATE_NAME}/lock" \
  -backend-config="username=gitlab-ci-token" \
  -backend-config="password=${CI_JOB_TOKEN}" \
  -backend-config="lock_method=POST" -backend-config="unlock_method=DELETE" -backend-config="retry_wait_min=5"
```

- **Auth in CI:** the predefined `CI_JOB_TOKEN` is auto-scoped to this project's Terraform-state
  API. Nothing to store.
- **Locking:** `lock_address`/`unlock_address` give real state locking — concurrent runs serialize
  (HTTP 423 + retry), so two pipelines never write the state at once.
- **State name:** `STATE_NAME` (default `flux`). One authoritative config ⇒ one state.
- View/manage states in GitLab under **Operate ▸ Terraform states**.

### Local development

Use a gitignored `*.backendrc` with a personal access token (api scope):

```
# foundation.backendrc  (gitignored)
address  = https://gitlab.com/api/v4/projects/<ID>/terraform/state/flux
username = <your gitlab user>
password = <PAT with api scope>
```
```bash
terraform init -backend-config=foundation.backendrc
```

Or, to plan offline against the local mock without GitLab state, drop a **gitignored**
`backend_override.tf` (Terraform merges `*_override.tf`, replacing the backend):

```hcl
terraform { backend "local" {} }
```
```bash
terraform init && terraform plan -var-file=mock.tfvars.example
```

`*_override.tf` and `*.backendrc` are gitignored — they never ship.

> **Sensitive artifact (real device):** the saved `tfplan` passed between stages embeds resolved
> sensitive provider attributes, including `TF_VAR_panos_api_key`. Against a real Panorama, restrict
> it (`artifacts.access: developer`, short `expire_in`) or re-plan inside `apply` rather than
> persisting `tfplan`. The `mock-state/` artifact is benign.

## Desired state (`terraform/desired/`)

```
terraform/desired/
  network.yaml          # template + stack + interface + zone + VR + device-group identity (singleton)
  apps/<name>.yaml      # one published app per file  (filename = for_each key)
  nat/<name>.yaml       # one NAT rule per file
```

Add an app = add `apps/<name>.yaml`; remove it = delete the file; edit it = change the file. The
root reads them with `fileset()`+`yamldecode()` and `for_each`-es the modules. Because keys are
stable names, a change to one record produces a plan that touches only that record's objects.

> **Ordered-rules caveat.** The `panos_security_policy_rules` / `panos_nat_policy_rules` resources
> manage an *ordered list* at a rulebase position. With a single owner this is fine; if you grow to
> many app records each emitting their own rule group at the same position, give the rulebase a
> single owner (one aggregating rules resource) rather than one per record.
>
> **Address-name uniqueness caveat.** Backend address objects are named from each app's
> `server_ips` map keys, and object names are global within a device group. Each `apps/<name>.yaml`
> is a separate module instance, so Terraform cannot see a cross-file name clash at plan time — keep
> `server_ips` keys **globally unique across all app files** (the seed keys are already prefixed,
> e.g. `flux-web-srv-1`).

## Commit is out-of-band

Terraform **cannot** commit a PAN-OS candidate in-band. The `commit` job promotes candidate →
running via the XML-API `<commit>` after `apply` (the industry-standard pattern; alternatives are a
`null_resource` `local-exec` or the `panos-commit` helper). This is unchanged by the state work.

## Drift detection (the "exclusively flux" guarantee)

A **scheduled** pipeline runs `terraform plan -detailed-exitcode` (the `drift` job). Exit code `2`
means the device no longer matches git+state — someone changed it out-of-band. To keep this green:

- **Make flux the sole writer** via Panorama **RBAC**: flux's API account is the only read-write
  admin; humans get **read-only** (WebGUI/CLI for viewing). This turns "only flux writes" from a
  convention into an enforced control — and makes the drift job a true tripwire.
- Schedule it in GitLab under **Build ▸ Pipeline schedules** (e.g. hourly).

## Reproducibility & brownfield import

- **Reproduce** the managed config on a blank device with `terraform apply` from git — git is the
  source of truth; the state file is the convergence ledger (not a lossless XML dump).
- **Adopt an existing device** (objects already present, no state) by importing each object once
  into the fresh state:
  ```bash
  cd terraform && terraform init -backend-config=foundation.backendrc
  terraform import 'panos_device_group.dg' <dg-import-id>
  terraform import 'module.template_network.panos_template.tpl' <id>
  terraform import 'module.app_publish["flux-web"].panos_service.svc' <id>
  # ... per the panos v2 provider's documented import-id format, for each managed object
  ```

## Testing: durable mock vs real lab

- **Durable mock (everyday CI).** The mock gains `--state-file`; `.start_mock` passes
  `--state-file mock-state/$STATE_NAME.json`, and GitLab `cache` (key `mock-$STATE_NAME`) + a
  `mock-state/` artifact carry it across jobs and runs. So the mock "device" persists like a real
  one, and plan/apply/commit/drift see a consistent device.
  > The cross-run carrier is the GitLab **cache**, which is **best-effort** — if it is evicted, the
  > mock restarts empty while the durable Terraform state still records every object, so the next
  > plan/drift reports a spurious full re-create. This is a mock-only artifact of the demo; for
  > persistence-sensitive validation use the real lab path. (The intra-pipeline artifact handoff is
  > reliable; only cross-pipeline durability depends on cache retention.)
- **Real lab Panorama (gold standard).** A real device is durable by nature — no mock, no cache.
  Set `PANOS_PROTOCOL=https`, `PANOS_HOSTNAME=<lab>`, `PANOS_PORT=443`, masked
  `TF_VAR_panos_api_key` (self-signed lab also: `TF_VAR_panos_skip_verify_certificate=true` +
  `PANOS_CURL_INSECURE=-k`). Apply, change one app record, confirm the NAT rule is untouched, then
  run the drift job after a manual GUI edit and watch it catch the drift.
