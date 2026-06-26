# ITSM-driven pipeline trigger (inbound)

How an external **ITSM workflow** starts this pipeline to apply **one** Terraform use case,
with parameters it supplies. This is the *inbound* direction — distinct from the *outbound*
notification the `commit` job already sends to `$ITSM_WEBHOOK_URL`.

```
ITSM workflow ──POST /trigger/pipeline──▶ GitLab pipeline ──▶ terraform apply (one use case) ──▶ commit ──▶ ITSM notified
   (approval)        FLUX_MODULE + TF_VAR_*           validate→plan→apply→commit (auto on trigger)
```

> The right GitLab primitive is a **pipeline trigger token**, not a "GitLab webhook" (those go
> the other way: GitLab → external). No custom receiver is needed — GitLab exposes the endpoint.

## 1. Create the trigger token

In the project: **Settings ▸ CI/CD ▸ Pipeline trigger tokens ▸ Add new token**. Copy the token
and store it **in your ITSM as a masked secret** (e.g. `FLUX_TRIGGER_TOKEN`). The token only
*starts pipelines* — it is not a repository credential and cannot read your code.

You also need the numeric **project ID** (shown on the project overview, or
`Settings ▸ General`).

## 2. The call ITSM issues

At the step in the ITSM workflow that should push the change, issue:

```bash
curl -fsS -X POST \
  --form token="$FLUX_TRIGGER_TOKEN" \
  --form ref=main \
  --form "variables[FLUX_MODULE]=app_publish" \
  --form "variables[TF_VAR_app_name]=billing-web" \
  --form 'variables[TF_VAR_server_ips]={"billing-1":"10.20.0.5/32","billing-2":"10.20.0.6/32"}' \
  --form 'variables[TF_VAR_app_applications]=["web-browsing","ssl"]' \
  --form 'variables[TF_VAR_app_source_zones]=["untrust"]' \
  --form "variables[TF_VAR_service_port]=8443" \
  "https://gitlab.com/api/v4/projects/<PROJECT_ID>/trigger/pipeline"
```

- `FLUX_MODULE` selects the use case (see the table below).
- Every object parameter is just a `variables[TF_VAR_<name>]` entry — Terraform reads
  `TF_VAR_*` natively. **Scalars** (`app_name`, `service_port`) pass as plain strings;
  **complex types** pass as JSON/HCL literals: an object `{...}` for the `server_ips` *map*, an
  array `[...]` for the `applications` / zone *lists*.
- A trigger run reports `CI_PIPELINE_SOURCE == "trigger"`, which is what flips apply/commit to
  automatic (step 4).

## 3. What runs — the selector → module map

`FLUX_MODULE` is validated by Terraform (`var.flux_module`). Selecting a dependent use case
**auto-enables its prerequisites** — the device group and the template network it builds on:

| `FLUX_MODULE` | template_network | device group | app_publish | nat_interplay |
|---|:--:|:--:|:--:|:--:|
| `all` *(default — what a normal push runs)* | ✓ | ✓ | ✓ | ✓ |
| `template_network` | ✓ | – | – | – |
| `app_publish` | ✓ (prereq) | ✓ (prereq) | ✓ | – |
| `nat_interplay` | ✓ (prereq) | ✓ (prereq) | – | ✓ |

The parameters each use case accepts are the `TF_VAR_*` of that module — see
`terraform/variables.tf` (e.g. `app_name`, `server_ips`, `service_port`, `app_source_zones`,
`app_applications` for `app_publish`; `nat_rule_name` for `nat_interplay`;
`interface_*`, `zone_name`, `virtual_router` for `template_network`).

## 4. Apply / commit policy

| Pipeline source | validate | plan | apply | commit |
|---|:--:|:--:|:--:|:--:|
| **Trigger** (ITSM) | auto | auto | **auto** | **auto** |
| **Push** (developer) | auto | auto | manual click | manual click |

On a trigger run apply + commit run automatically — **ITSM is the change-approval gate**, so a
second human click in GitLab would be redundant. The `$CI_PIPELINE_SOURCE == "trigger"` guard in
`.gitlab-ci.yml` guarantees a normal push can *never* auto-apply.

> **Want a human gate even for ITSM runs on a real device?** Add `&& $PANOS_PROTOCOL == "http"`
> to the trigger rule on `apply`/`commit` so only the **mock** auto-applies and real-Panorama
> trigger runs still require a click.

## 5. Security

- Treat the trigger token like a password: **masked secret in ITSM**, rotate it if it leaks
  (Settings ▸ CI/CD ▸ Pipeline trigger tokens ▸ revoke).
- It is least-privilege by design: it can only start pipelines on this project, not read or
  write the repo.
- Only trigger-sourced pipelines can auto-apply (the `CI_PIPELINE_SOURCE` guard), so a leaked
  *push* credential still cannot bypass the manual gate.
- The Panorama API key is still supplied separately as a masked `TF_VAR_panos_api_key` (or via
  Bitwarden) — the trigger never carries it.

## 6. Persistent-backend caveat

Gating the modules with `count` makes the device-group address `panos_device_group.dg[0]`. The
skeleton's state is local and ephemeral (mock), so nothing is needed. If you run a **persistent
backend against a real device** that predates this change, migrate once:

```bash
terraform state mv 'panos_device_group.dg' 'panos_device_group.dg[0]'
```

## Verify against the mock

Locally, prove that a selection runs only its use case (plus prerequisites):

```bash
python mock/panorama_mock.py --port 8080 &
cd terraform && terraform init
terraform plan -var-file=mock.tfvars.example -var 'flux_module=nat_interplay'
#   → template_network + device group + nat_interplay only; no app_publish
```

In CI, fire the step-2 curl with `variables[FLUX_MODULE]=nat_interplay` and confirm the pipeline
shows `source: trigger`, the `plan` log prints `flux_module=nat_interplay`, and apply + commit
run without a manual click.
