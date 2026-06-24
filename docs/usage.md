---
title: Usage
nav_order: 3
---

# Usage
{: .no_toc }

1. TOC
{:toc}

---

## Requirements

- **Python 3.x** — the validator and the mock are stdlib-only (no `pip install`).
- **PowerShell + curl** — only for the discovery tooling that talks to a *real* Panorama.

## Validate a config fragment (the gate)

The gate checks an XML `<entry>` fragment against the version-bound schema before it would be
pushed. Exit code `0` = PASS, `1` = FAIL.

```bash
python tools/validate_config.py \
  --xml schema/fixtures/shared_address.xml \
  --xpath "/config/shared/address/entry[@name='web']"
```

A deliberately broken fixture shows the reasons and the phase (`set` vs `commit`):

```bash
python tools/validate_config.py \
  --xml schema/fixtures/invalid/service_no_port.xml \
  --xpath "/config/shared/service/entry[@name='svc']"
# FAIL - 1 violation(s):
#   [error/commit] entry[svc]/protocol/tcp/port: required field 'port' is missing
```

Add `--json` for a machine-readable report, or `--panos-version 12.1.2` to enforce that the target
matches the schema's bound version.

## Run the mock Panorama

```bash
python mock/panorama_mock.py --port 8080 --version 12.1.2
```

Then drive it exactly like the real device:

```bash
KEY=$(curl -s "http://127.0.0.1:8080/api/?type=keygen&user=admin&password=x" | sed -n 's:.*<key>\(.*\)</key>.*:\1:p')

# set an address (set-time validated)
curl -s "http://127.0.0.1:8080/api/" \
  --data-urlencode "type=config" --data-urlencode "action=set" --data-urlencode "key=$KEY" \
  --data-urlencode "xpath=/config/shared/address/entry[@name='web']" \
  --data-urlencode "element=<ip-netmask>10.0.0.1/32</ip-netmask>"

# full (commit-time) validation
curl -s "http://127.0.0.1:8080/api/" \
  --data-urlencode "type=op" --data-urlencode "key=$KEY" \
  --data-urlencode "cmd=<validate><full></full></validate>"
```

Useful flags: `--seed candidate.xml` preloads a starting config, `--log-file audit.log` records an
audit trail. State is in-memory by design.

## Tests

```bash
python tools/test_validator.py   # validator regression (14/14)
python mock/test_mock.py         # mock end-to-end (13/13)
```

## Discovery against a real Panorama (PowerShell)

```powershell
. .\tools\pan-api.ps1
Connect-Pan -PanHost 192.168.99.2 -User admin -Password '****'
.\tools\seed-fixtures.ps1        # capture fixtures + source-info.json
.\tools\build-schema.ps1         # compile schema, bound to the live PAN-OS version
.\tools\compare-validation.ps1   # prove the gate matches Panorama's own validation
```
