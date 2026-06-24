# Constraint probing - Panorama 12.1.2 (XML-API)

Produced by sending deliberately invalid `set` calls to `192.168.99.2` (XML-API, candidate
config). Goal: find out which constraints the XML-API enforces **at `set` time** and which
only apply at commit time - this determines what the flux validator must cover itself.

## Key insight: set-time vs commit-time
PAN-OS does **not** validate everything on `action=set` (candidate):

| Constraint class            | Enforced on `set`? | Evidence |
|-----------------------------|--------------------|----------|
| Unknown element             | **Yes** (code 12)  | `address/<bogus>` -> `bogus unexpected here` |
| Enum / keyword value        | **Yes** (code 12)  | `action=foobar` -> `action 'foobar' is not an allowed keyword` |
| Value format (IP)           | **Yes** (code 12)  | `ip-netmask=not-an-ip` -> `invalid ipv4/v6 address` |
| Value format/range (port)   | **Yes** (code 12)  | `tcp/port=99999` and `abc` -> `port is invalid` |
| **Required field missing**  | **No** (code 20)   | `address` with only `<description>` -> `command succeeded` |
| **Choice: >1 type set**     | **No**             | `ip-netmask` + `fqdn` -> set succeeds, PAN-OS silently keeps one |

=> **Consequence for flux:** the validator must check **required / cardinality** itself (the
XML-API accepts incomplete objects in candidate; only a commit would complain). Enums/format/
unknown elements are detected by the API too, but the validator checks them locally before the
push ("validate before apply") so the gate works without a live Panorama.

## Live-verified error messages (raw)
```
action 'foobar' is not an allowed keyword            (rule/action)
ip-netmask not-an-ip is an invalid ipv4/v6 address   (address/ip-netmask)
... protocol -> tcp -> port is invalid               (service tcp/port, 99999 and 'abc')
... bogus unexpected here                            (unknown child under address)
```
Note: on enums the API does **not** list the allowed set. Enum lists for the supported
resources come from the PAN-OS docs and are stored in the schema; the live API remains the
final authority (cross-check below).

## Comparison: flux validator vs Panorama's own `validate full`
"Panorama's own validation" has two layers: (A) `set`/`edit` blocks structure/unknown/enum/
format immediately; (B) `validate full` (the commit check) catches semantics - required fields,
choice cardinality, references, missing mandatory sub-nodes. Panorama rejects if A OR B rejects.

`tools/compare-validation.ps1` runs every fixture through both flux and Panorama. Result:
**13/13 agree, 0 mismatches.** Findings that shaped the schema:

- **address: choice of type** - zero types -> commit error `is missing one of ip-netmask,
  ip-range, ip-wildcard or fqdn`; **more than one type -> accepted** (PAN-OS keeps one). So
  flux treats zero as an **error** and `>1` as a **warning** (matches the pass/fail verdict
  while surfacing the ambiguity GitOps would otherwise lose silently).
- **service: protocol/port** - a `tcp`/`udp` without `port` is accepted on `set` but rejected
  by `validate full` (`is missing 'port'`). flux requires `port`.
- **template-stack: settings** - a stack without `<settings>` is accepted on `set` but rejected
  by `validate full` (`is missing 'settings'`); an empty `<settings/>` satisfies it. flux
  requires `settings`.

Known limit: the schema is a **curated subset**. A valid but un-curated element would be flagged
as "unexpected" (false positive) - extend via `allowedChildren` / `build-schema.ps1`.

## Reproduction
- `tools/probe-constraints.ps1` - set-time probes (idempotent; creates/deletes temp `flux-probe*`).
- `tools/compare-validation.ps1` - full comparison against Panorama's `validate full`.
