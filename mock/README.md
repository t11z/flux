# Mock Panorama (XML-API)

A lightweight, dependency-free stand-in for a Panorama management plane that speaks the PAN-OS
XML-API. It lets the GitOps pipeline run end to end without a real (licensed) Panorama. See
[ADR-0004](../docs/decisions/0004-mock-server-python-stdlib.md).

## Run

```bash
python mock/panorama_mock.py --port 8080 [--version 12.1.2] [--seed candidate.xml] [--log-file audit.log]
```

Then talk to it like the real device, e.g.:

```bash
curl -s "http://127.0.0.1:8080/api/?type=keygen&user=admin&password=x"
curl -s "http://127.0.0.1:8080/api/" \
  --data-urlencode "type=config" --data-urlencode "action=set" --data-urlencode "key=<KEY>" \
  --data-urlencode "xpath=/config/shared/address/entry[@name='web']" \
  --data-urlencode "element=<ip-netmask>10.0.0.1/32</ip-netmask>"
```

## Behaviour

Mirrors the real device's two layers (see `schema/constraints/probe-results.md`):

- **`set`/`edit`** apply to the in-memory **candidate** and are rejected on **set-time** schema
  violations (unknown elements, bad enums, bad value formats) — HTTP body `status="error"`, code 12.
- **`validate full`** / **`commit`** run the **commit-time** checks (required fields, choice
  cardinality, member lists) across the whole candidate, returning a job whose result is `OK`/`FAIL`.
- **`commit`** copies candidate → **running**; `get` reads candidate, `show` reads running.

Validation reuses `tools/validate_config.py`, so the mock and the validate-before-apply gate never
drift. State is in-memory (optionally preloaded with `--seed`); it is not durable by design.

## Supported requests

`type=keygen`, `type=config` (`set`/`edit`/`get`/`show`/`delete`), `type=op`
(`<show><system><info>`, `<validate><full>`, `<commit>`, `<show><jobs><id>`), `type=commit`.

## Tests

```bash
python mock/test_mock.py
```
