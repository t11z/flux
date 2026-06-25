# GitLab delivery pipeline (skeleton)

A runnable skeleton for delivering Panorama configuration changes via GitOps on a
**self-hosted GitLab runner**, using Terraform and the official
[`PaloAltoNetworks/panos`](https://registry.terraform.io/providers/PaloAltoNetworks/panos/latest)
provider (v2, XML-API). It is an *inert template* in this repo
(see [ADR-0003](../../docs/decisions/0003-github-dev-gitlab-runtime.md)) — copy
`.gitlab-ci.yml` into your delivery repository and adjust.

## Flow

```
validate ─▶ plan ─▶ apply ─▶ commit
   │          │        │         │
   │          │        │         └─ <commit> via XML-API, then ITSM webhook
   │          │        └─ terraform apply (candidate config) — manual gate
   │          └─ terraform plan (against Panorama or the mock)
   └─ schema gate (test_validator.py) + terraform fmt/validate
```

The Terraform lives in [`../../terraform/`](../../terraform) and ships three everyday
use cases as modules (publish an app, template network config, NAT interplay).

## Runnable by default (no real device)

Out of the box the pipeline targets the in-repo **mock Panorama**
(`mock/panorama_mock.py`): the `validate`, `plan`, `apply`, and `commit` stages run
end-to-end with no licensed hardware. The mock speaks exactly what the panos v2
provider sends (`X-PAN-KEY` header auth, `action=set` and `action=multi-config`,
`<commit>`), so it is a faithful stand-in for CI.

To run the same flow locally:

```bash
python mock/panorama_mock.py --port 8080 &
cd terraform
terraform init
terraform apply -auto-approve -var-file=mock.tfvars.example
# then commit candidate -> running:
KEY=flux-mock-key-0000000000000000000000000000
curl -s -H "X-PAN-KEY: $KEY" --data-urlencode 'type=op' --data-urlencode 'cmd=<commit></commit>' http://127.0.0.1:8080/api/
```

## Targeting a real Panorama

Set these CI/CD variables (Settings ▸ CI/CD ▸ Variables), then re-run:

| Variable | Value |
|----------|-------|
| `PANOS_PROTOCOL` | `https` |
| `PANOS_HOSTNAME` | your Panorama IP/FQDN |
| `PANOS_PORT` | `443` |
| `TF_VAR_panos_api_key` *(masked)* | a Panorama API key |

When `PANOS_PROTOCOL=https`, the `.start_mock` helper is a no-op and the jobs talk to
the real device.

**TLS is verified by default.** The API key travels in the `X-PAN-KEY` header, so an
unverified TLS connection would expose it to a man-in-the-middle. Only relax this for a
**self-signed lab** Panorama, and only there: set `TF_VAR_panos_skip_verify_certificate=true`
**and** `PANOS_CURL_INSECURE=-k` as CI/CD variables for that environment. A production
Panorama should present a trusted certificate and keep both at their secure defaults.

## Secrets via Bitwarden (optional)

Instead of a masked CI variable, the key can come from
[Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) (free tier):

1. Store the Panorama API key as a secret; note its UUID.
2. Add CI/CD variables `BWS_ACCESS_TOKEN` (masked) and `BWS_PANOS_KEY_ID`.
3. Uncomment the `- *bws` line in the `plan`/`apply`/`commit` jobs in `.gitlab-ci.yml`.

The `bws` CLI + `jq` must be present in the runner image.

## ITSM notification

The `commit` job POSTs a small JSON change record to `$ITSM_WEBHOOK_URL` on success
(skipped if unset). Point it at your ITSM intake (ServiceNow, Jira SM, …) to close the
GitOps loop with an auditable change record.

## Runner image

The jobs need **terraform** and **python3** (stdlib only) on `PATH`. Use a self-hosted
runner with both installed, or build a small CI image and set it as `default.image` in
`.gitlab-ci.yml`.
