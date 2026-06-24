---
title: "Python Stdlib Validator as the Validate-Before-Apply Gate"
description: "The gate is Python stdlib-only; PowerShell is used only for live discovery tooling."
type: adr
category: architecture
tags: [validator, python, powershell, ci]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
technologies: [python, powershell]
related: [0002-derive-schema-from-live-probing.md, 0004-github-dev-gitlab-runtime.md]
---

# ADR-0003: Python Stdlib Validator as the Validate-Before-Apply Gate

## Status

Accepted

## Context

### Background and Problem Statement

flux needs a "validate before apply" gate that runs inside the delivery pipeline (a GitLab
runner, typically Linux) to reject invalid configuration before it is pushed. The discovery
tooling, by contrast, runs interactively on the architect's Windows machine against a live
Panorama. The two have different runtime environments and constraints.

### Current Limitations

1. The discovery tooling already exists in PowerShell and talks to the live box.
2. A gate that runs in CI must be portable and dependency-free.

## Decision Drivers

### Primary Decision Drivers

1. **Portability of the gate**: it must run in the Linux runner without extra dependencies.
2. **Right tool per role**: live Windows discovery vs portable CI gate are different jobs.

### Secondary Decision Drivers

1. **Language-neutral interface**: the schema is JSON, consumable by any language.

## Considered Options

### Option 1: Python (stdlib) gate, PowerShell discovery

**Description**: Keep discovery/seeding/probing in PowerShell; implement the validator in Python
using only the standard library.

**Technical Characteristics**:
- `validate_config.py` uses `xml.etree`, `json`, `ipaddress`, `argparse` only.
- Consumes `schema/panorama-schema.json`.

**Advantages**:
- Runs anywhere with a Python interpreter; no pip install.
- Discovery stays in the language already proven against the box.

**Disadvantages**:
- Two languages in the repo.

**Risk Assessment**:
- **Technical Risk**: Low. Stdlib-only; 14/14 regression green.
- **Schedule Risk**: Low. Implemented.
- **Ecosystem Risk**: Low. Python is ubiquitous on runners.

### Option 2: PowerShell validator everywhere

**Description**: Implement the gate in PowerShell as well, for a single language.

**Technical Characteristics**:
- Requires `pwsh` in the runner.

**Advantages**:
- One language across the repo.

**Disadvantages**:
- Heavier runtime in Linux CI; less universal than Python for a gate.

**Risk Assessment**:
- **Technical Risk**: Low.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Medium. `pwsh` is less universally assumed than Python in pipelines.

## Decision

The validate-before-apply gate is **Python, stdlib-only** (`tools/validate_config.py`).
PowerShell remains for live discovery tooling (`tools/*.ps1`).

The implementation will use:
- **`tools/validate_config.py`** for validation and **`tools/test_validator.py`** for regression.

## Consequences

### Positive

1. **Portable gate**: runs in the Linux runner with zero dependencies.
2. **Clear separation**: discovery (Windows/PowerShell) vs gate (portable/Python).

### Negative

1. **Two languages** to maintain in one repo.

### Neutral

1. The JSON schema is the language-neutral contract between the two.

## Decision Outcome

A dependency-free gate that any pipeline can run, fed by the version-bound schema from ADR-0002.

Mitigations:
- `tools/CLAUDE.md` documents the split; CI runs the Python tests.

## Related Decisions

- [ADR-0002: Derive the Schema From Live Probing](0002-derive-schema-from-live-probing.md) - the schema the gate consumes.
- [ADR-0004: GitHub Dev, GitLab Runtime](0004-github-dev-gitlab-runtime.md) - where the gate runs.

## Links

- [Python xml.etree.ElementTree](https://docs.python.org/3/library/xml.etree.elementtree.html) - parser used.

## More Information

- **Date:** 2026-06-24
- **Source:** Implementation in `tools/`.
- **Related ADRs:** ADR-0002, ADR-0004.

## Audit

### 2026-06-24

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Gate is Python stdlib-only | tools/validate_config.py | - | compliant |
| Discovery tooling is PowerShell | tools/pan-api.ps1, tools/seed-fixtures.ps1 | - | compliant |
| Regression green (14/14) | tools/test_validator.py | - | compliant |

**Summary:** The gate is implemented in Python stdlib; PowerShell is confined to discovery.

**Action Required:** None.
