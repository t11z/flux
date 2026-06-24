---
title: "Build the Mock Panorama Server in Python Stdlib"
description: "The Phase 2 mock Panorama XML-API server uses Python stdlib and reuses the validator."
type: adr
category: architecture
tags: [mock, python, panorama, testing]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
related: [0002-derive-schema-from-live-probing.md, 0003-github-dev-gitlab-runtime.md]
---

# ADR-0004: Build the Mock Panorama Server in Python Stdlib

## Status

Accepted

## Context

### Background and Problem Statement

Phase 2 of flux is a lightweight mock Panorama that speaks the XML-API, validates incoming
configuration, and returns realistic responses — so the GitOps pipeline can run end to end
without a real Panorama. It must mirror the device's two-layer behaviour (set-time structural
checks vs commit-time semantic checks) established in ADR-0002, and it must run in CI.

### Current Limitations

1. A real Panorama is a heavy, licensed dependency not available in CI or to every contributor.
2. The flux validator already encodes the schema behaviour (it implements ADR-0002); duplicating it would risk drift.

## Decision Drivers

### Primary Decision Drivers

1. **Reuse the validator**: one schema, one validation implementation for both the gate and the mock.
2. **Runs in CI**: dependency-free so it executes in the runner like the validator gate.

### Secondary Decision Drivers

1. **Faithfulness**: must reproduce set-time vs commit-time behaviour, not a toy stub.

## Considered Options

### Option 1: Python stdlib (http.server), reuse validate_config.py

**Description**: Implement the mock with `http.server`, an in-memory ElementTree config, and the
existing validator imported as a module (findings carry a `set`/`commit` phase).

**Technical Characteristics**:
- No pip dependencies; one shared validation code path.

**Advantages**:
- Zero dependencies; runs anywhere the gate runs.
- No validation drift between mock and gate.

**Disadvantages**:
- Manual routing/XML assembly (no framework conveniences).

**Risk Assessment**:
- **Technical Risk**: Low. 13/13 end-to-end mock tests green.
- **Schedule Risk**: Low. Implemented.
- **Ecosystem Risk**: Low. Stdlib only.

### Option 2: Python web framework (FastAPI/Flask)

**Description**: Build the mock on a web framework.

**Technical Characteristics**:
- Routing, request parsing, and tooling provided.

**Advantages**:
- Less boilerplate for HTTP handling.

**Disadvantages**:
- External dependencies; heavier than the "lightweight" remit; still needs the same XML logic.

**Risk Assessment**:
- **Technical Risk**: Low.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Medium. Adds a dependency to a deliberately dependency-free project.

**Disqualifying Factor**: Dependencies contradict the lightweight, runner-friendly remit.

## Decision

Build the mock with **Python stdlib** (`mock/panorama_mock.py`) and **reuse the validator**
(`tools/validate_config.py`) for set-time and commit-time checks.

The implementation will use:
- **`http.server`** for the endpoint and **ElementTree** for the in-memory candidate/running config.
- **`validate_config.validate_entry`** with finding phases to mirror set vs commit behaviour.

## Consequences

### Positive

1. **No drift**: the mock and the gate validate identically.
2. **CI-friendly**: dependency-free, runs in the runner.

### Negative

1. **Manual HTTP/XML plumbing** instead of a framework.

### Neutral

1. State is in-memory with an optional seed file; not durable by design.

## Decision Outcome

A faithful, dependency-free mock that the pipeline and CI can drive end to end.

Mitigations:
- End-to-end tests (`mock/test_mock.py`) cover keygen, set-time rejection, validate-full, commit.

## Related Decisions

- [ADR-0002: Derive the Schema From Live Probing](0002-derive-schema-from-live-probing.md) - the behaviour the mock mirrors.
- [ADR-0003: Develop on GitHub, Run the Delivered GitOps on GitLab](0003-github-dev-gitlab-runtime.md) - where the mock runs in CI and is delivered.

## Links

- [Python http.server](https://docs.python.org/3/library/http.server.html) - the HTTP layer.

## More Information

- **Date:** 2026-06-24
- **Source:** Phase 2 of the Engram `flux` note.
- **Related ADRs:** ADR-0002, ADR-0003.

## Audit

### 2026-06-24

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Mock is stdlib-only, reuses validator | mock/panorama_mock.py | - | compliant |
| Set vs commit behaviour mirrored | tools/validate_config.py | - | compliant |
| End-to-end tests green (13/13) | mock/test_mock.py | - | compliant |

**Summary:** The mock is implemented in Python stdlib, shares the validator, and passes end-to-end tests.

**Action Required:** None.
