---
title: "Derive the Schema From Live Probing and Fixtures"
description: "Build a version-bound schema from set-time probing, real fixtures, and validate-full comparison."
type: adr
category: architecture
tags: [schema, panorama, validation, versioning]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
related: [0001-target-the-panorama-xml-api.md]
---

# ADR-0002: Derive the Schema From Live Probing and Fixtures

## Status

Accepted

Supersedes none.

## Context

### Background and Problem Statement

The XML-API has no officially exported, machine-readable schema (ADR-0001). flux still needs a
complete, normalized schema for the supported resources so the validator can act as a
"validate before apply" gate. The schema must reflect real PAN-OS behaviour, including the
difference between what `set` accepts and what a commit (`validate full`) requires.

### Current Limitations

1. A freshly deployed Panorama is empty, so there is nothing to scrape directly.
2. `set` enforces only some constraints (enums, formats, unknown elements); required fields and
   choice cardinality are only enforced at commit time.

## Decision Drivers

### Primary Decision Drivers

1. **Fidelity to the live box**: the schema must match real PAN-OS validation, not assumptions.
2. **Version binding**: PAN-OS behaviour can change across versions, so the schema must be tied
   to the version it was derived from.

### Secondary Decision Drivers

1. **Reproducibility**: re-running the toolchain should reproduce the same schema.

## Considered Options

### Option 1: Seed + probe + compile, bound to a PAN-OS version

**Description**: Seed representative objects, capture canonical fixtures, probe invalid `set`
calls and compare against `validate full`, then compile a curated JSON schema stamped with the
live PAN-OS version.

**Technical Characteristics**:
- `seed-fixtures.ps1`, `probe-constraints.ps1`, `compare-validation.ps1`, `build-schema.ps1`.
- Schema carries `panosVersion`; archived under `schema/versions/`.

**Advantages**:
- Grounded in real behaviour; consistency-checked against fixtures and `validate full`.
- Versioned and reproducible.

**Disadvantages**:
- Coverage is a curated subset, not every possible node.

**Risk Assessment**:
- **Technical Risk**: Low. Verified by a 13/13 comparison against Panorama's own validation.
- **Schedule Risk**: Low. Toolchain implemented and green.
- **Ecosystem Risk**: Medium. New PAN-OS versions need a re-derivation.

### Option 2: Hand-write a schema from documentation

**Description**: Author the schema from the PAN-OS docs without live verification.

**Technical Characteristics**:
- Static; no live cross-check.

**Advantages**:
- No lab box required.

**Disadvantages**:
- Drifts from real behaviour; misses set-time vs commit-time nuances.

**Risk Assessment**:
- **Technical Risk**: High. Unverified against the device.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Medium.

**Disqualifying Factor**: Cannot guarantee parity with Panorama's own validation.

## Decision

Derive the schema by **seeding + probing + compiling**, cross-checked against `validate full`,
and **bind it to the PAN-OS version** (`panosVersion` from `schema/source-info.json`).

The implementation will use:
- **`tools/build-schema.ps1`** to compile `schema/panorama-schema.json` and archive a versioned copy.
- **`tools/compare-validation.ps1`** to prove parity with Panorama's own validation.

## Consequences

### Positive

1. **Verified parity**: validator verdicts match Panorama (set + validate full).
2. **Version safety**: the schema is explicitly tied to the PAN-OS version it models.

### Negative

1. **Re-derivation needed** when targeting a new PAN-OS version.

### Neutral

1. Coverage is intentionally scoped to flux-relevant resources; extensible via the curated model.

## Decision Outcome

A normalized, version-bound schema that the Python gate validates against, proven equivalent to
Panorama's own validation for the supported resources.

Mitigations:
- CI re-compiles the schema and fails on drift; `--panos-version` enforces the binding.

## Related Decisions

- [ADR-0001: Target the Panorama XML-API](0001-target-the-panorama-xml-api.md) - why there is no OpenAPI source.
- [ADR-0003: Python Validator as the Gate](0003-python-validator-gate.md) - what consumes the schema.

## Links

- [smADR](https://smadr.dev/) - decision record format.

## More Information

- **Date:** 2026-06-24
- **Source:** Discovery against Panorama 12.1.2; see `schema/constraints/probe-results.md`.
- **Related ADRs:** ADR-0001, ADR-0003.

## Audit

### 2026-06-24

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Schema compiled and version-stamped | schema/panorama-schema.json, schema/versions/panorama-12.1.2.json | - | compliant |
| Parity proven vs validate full (13/13) | tools/compare-validation.ps1 | - | compliant |
| Behaviour documented | schema/constraints/probe-results.md | - | compliant |

**Summary:** The schema is derived from the live box, version-bound, and proven equivalent to Panorama's own validation.

**Action Required:** None.
