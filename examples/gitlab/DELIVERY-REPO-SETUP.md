# Setting up the delivery repo on GitLab

How to take the inert pipeline skeleton in this directory and stand it up as a **real,
running GitLab delivery repo**. Per [ADR-0003](../../docs/decisions/0003-github-dev-gitlab-runtime.md),
flux is *developed* on GitHub and the GitOps it demonstrates *runs* on GitLab — this guide is
the bridge between the two.

> The skeleton here (`.gitlab-ci.yml`, `README.md`) is intentionally inert. You do not run the
> pipeline from this repo; you assemble a delivery repo from it and push that to GitLab.

## Why a subset, and which files

The pipeline jobs reference paths from the **repo root** (`tools/test_validator.py`,
`mock/panorama_mock.py`, `terraform/`), and the Python tools locate their data by walking up
one directory (`Path(__file__).resolve().parent.parent`). So the delivery repo must keep that
relative layout. The minimum runnable subset is:

```
.gitlab-ci.yml            ← from examples/gitlab/.gitlab-ci.yml, at the ROOT
README.md                 ← delivery-repo readme (see examples/gitlab/README.md)
.gitignore                ← .terraform/, *.tfstate*, __pycache__/, tfplan, mock-audit.log
tools/
  validate_config.py      ← the validate-before-apply gate
  test_validator.py       ← its regression harness
mock/
  panorama_mock.py        ← stdlib mock Panorama XML-API
  test_mock.py            ← mock <-> gate parity test
schema/                   ← HARD dependency: the validator + mock load it at runtime
  panorama-schema.json
  source-info.json
  fixtures/               ← used by test_validator.py
terraform/                ← all *.tf, modules/, *.tfvars.example, .terraform.lock.hcl
                            (exclude the .terraform/ provider cache)
```

The PowerShell discovery tools (`pan-api.ps1`, `seed-fixtures.ps1`, `probe-constraints.ps1`,
`build-schema.ps1`, …) and `schema/constraints` + `schema/versions` are **dev-time** artifacts
and stay on the GitHub side — they are not needed to run the pipeline.

## Steps

### 1. Create (or pick) a GitLab project

On gitlab.com or a self-hosted instance, create an empty project (e.g. `you/flux`). Note its
clone URL: `https://gitlab.com/you/flux.git`.

### 2. Assemble the subset

Copy the files above into a fresh working tree, preserving the layout. Copy
`examples/gitlab/.gitlab-ci.yml` to the **root** as `.gitlab-ci.yml`. Add the `.gitignore`.

Smoke-test locally before pushing — both must pass from the delivery-repo root:

```bash
python tools/test_validator.py     # schema gate regression
python mock/test_mock.py           # mock <-> gate parity
( cd terraform && terraform init -backend=false && terraform fmt -check -recursive && terraform validate )
```

### 3. Choose a runner image

The jobs need **`terraform` + `python3` (stdlib only) + `curl`** on `PATH`.

- **gitlab.com shared runners:** the shipped `.gitlab-ci.yml` works out of the box — it uses
  `python:3.12-slim` and fetches a pinned `terraform` binary in `before_script`.
- **Self-hosted runner:** with the **Docker executor**, the host needs only Docker +
  `gitlab-runner` — the per-job tools come from the image + `before_script`, so the shipped
  `.gitlab-ci.yml` runs unchanged. Full Ubuntu walkthrough (using `docker.io`):
  [RUNNER-SETUP.md](RUNNER-SETUP.md). If your image already bundles terraform + python3 + curl,
  drop the `before_script` and set `default.image` to that tag.

> ⚠️ **Do not use `hashicorp/terraform` (Alpine) + `apk add python3`.** Alpine's packaged
> python3 ships a `pyexpat` linked against a newer `expat` than the image carries, so
> `import xml.etree.ElementTree` raises `ImportError` — which makes the schema gate *and* the
> mock crash on import. The failure is silent in the job log (the error goes to stderr that
> the harness swallows) and looks like every fixture failing validation. The Debian
> `python:3.12-slim` image has a consistent `expat` and avoids it.

### 4. Push

```bash
git init -b main
git add -A
git commit -m "flux delivery repo"
git remote add origin https://gitlab.com/you/flux.git
git push -u origin main
```

Pushing to `main` triggers the pipeline immediately. By default it targets the in-repo mock,
so `validate` and `plan` run automatically; `apply` and `commit` are **manual** gates you click
in **Build ▸ Pipelines**.

### 5. Target a real Panorama (CI/CD variables)

In **Settings ▸ CI/CD ▸ Variables** add, then re-run:

| Variable | Value | Notes |
|----------|-------|-------|
| `PANOS_PROTOCOL` | `https` | turns off the mock helper |
| `PANOS_HOSTNAME` | Panorama IP/FQDN | |
| `PANOS_PORT` | `443` | |
| `TF_VAR_panos_api_key` | a Panorama API key | **mask** it |

TLS is verified by default. Only for a **self-signed lab** Panorama set
`TF_VAR_panos_skip_verify_certificate=true` **and** `PANOS_CURL_INSECURE=-k` — never for
production (the API key rides in the `X-PAN-KEY` header). For Bitwarden-sourced secrets and
the ITSM webhook, see [`README.md`](README.md).

## Security

- Push with a **least-privilege** credential: a project access token / deploy token scoped to
  `write_repository` is enough; prefer it over a broad personal access token.
- Never commit a token. If a token is ever pasted into a chat, a terminal, or a commit,
  **rotate it** (GitLab ▸ Settings ▸ Access Tokens).
- Keep `TF_VAR_panos_api_key` and any `BWS_*` values as **masked** CI/CD variables, not in
  `.gitlab-ci.yml`.

## Keeping the delivery repo in sync

The delivery repo is assembled output, not a place to hand-edit Terraform or the schema.
Change those upstream in the GitHub source repo, then re-copy the subset (step 2) and push.
