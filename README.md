# flux

[![CI](https://github.com/t11z/flux/actions/workflows/ci.yml/badge.svg)](https://github.com/t11z/flux/actions/workflows/ci.yml)

**A lightweight, extensible firewall GitOps automation skeleton for Palo Alto Networks Panorama.**

flux demonstrates configuration-as-code for Panorama: configuration flows from Git through
Terraform into Panorama, but every change is checked by a **validate-before-apply gate** derived
from the live device's own schema — so invalid config is rejected *before* it is ever pushed.

📖 **Documentation:** https://t11z.github.io/flux/ · **Decisions:** [`docs/decisions/`](docs/decisions/)

## Architecture

```mermaid
flowchart LR
    subgraph Git["Git (config as code)"]
        cfg["address / service /<br/>security-rule patterns"]
    end
    subgraph Pipeline["GitLab runner"]
        tf["Terraform (panos / XML-API)"]
        gate["validate-before-apply gate<br/>validate_config.py"]
    end
    schema[("panorama-schema.json<br/>bound to a PAN-OS version")]
    pano["Panorama / mock<br/>XML-API"]
    itsm["ITSM ticket"]

    cfg -->|push| gate
    gate -. reads .-> schema
    gate -->|valid| tf
    gate -->|invalid → fail| cfg
    tf -->|set / commit| pano
    pano -->|success / failure| itsm

    classDef store fill:#1f2937,stroke:#6366f1,color:#e5e7eb;
    class schema store;
```

The schema is **derived from a live Panorama** (seeding + constraint probing) and **bound to its
PAN-OS version**; the validator is proven to agree with Panorama's own validation. See the
[architecture page](https://t11z.github.io/flux/architecture.html) for the full picture.

## Status

| Phase | Scope | State |
|------|-------|-------|
| 1 | XML-API discovery, version-bound schema, validate-before-apply gate | ✅ done |
| 2 | Mock Panorama XML-API server (end-to-end without a real device) | ✅ done |
| 3 | Terraform modules + GitLab pipeline (`examples/gitlab/`) | ⏳ planned |

## Quickstart

**Validate a config fragment against the schema (the gate):**

```bash
python tools/validate_config.py \
  --xml schema/fixtures/shared_address.xml \
  --xpath "/config/shared/address/entry[@name='web']"
```

**Run the mock Panorama and talk to it like the real device:**

```bash
python mock/panorama_mock.py --port 8080 &
curl -s "http://127.0.0.1:8080/api/?type=keygen&user=admin&password=x"
```

**Run the tests:**

```bash
python tools/test_validator.py   # validator regression (14/14)
python mock/test_mock.py         # mock end-to-end (13/13)
```

The discovery tooling (PowerShell, `tools/*.ps1`) talks to a real Panorama; the gate and mock are
Python stdlib-only so they run anywhere, including CI.

## Repository layout

```
tools/    XML-API wrapper, seeding, probing, schema compiler, validator (Python + PowerShell)
mock/     stdlib mock Panorama XML-API server + end-to-end tests
schema/   panorama-schema.json (source of truth), fixtures/, constraints/, versions/
docs/     documentation site (GitHub Pages), decisions/ (smADRs), implementation log
```

## Conventions

- **XML-API only** — flux targets the XPath-based XML-API (what the `panos` Terraform modules
  speak), never the REST API. ([ADR-0001](docs/decisions/0001-target-the-panorama-xml-api.md))
- **The schema is bound to a PAN-OS version** and is the single source of truth.
  ([ADR-0002](docs/decisions/0002-derive-schema-from-live-probing.md))
- **Repository artifacts are in English.** Architecture decisions live in `docs/decisions/` as
  Structured MADR; see [`CLAUDE.md`](CLAUDE.md).
