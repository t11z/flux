---
title: "Authoritative, Persistent, Data-Driven Terraform State (One Config, Full Converge)"
description: "Hold the whole managed Panorama config as git desired-state, converge it as a whole into ONE persistent GitLab-managed Terraform state, with out-of-band commit and scheduled drift detection."
type: adr
category: architecture
tags: [terraform, state, gitops, panorama, drift, gitlab]
status: proposed
created: 2026-06-26
updated: 2026-06-26
author: "Thomas Sprock"
project: flux
related: [0003-github-dev-gitlab-runtime.md, 0004-mock-server-python-stdlib.md, 0005-use-the-panos-terraform-provider-v2.md]
---

# ADR-0006: Authoritative, Persistent, Data-Driven Terraform State (One Config, Full Converge)

## Status

Proposed

## Context

### Background and Problem Statement

flux drives a **real** Panorama in production (the in-repo mock is only a license-saving
stand-in). Terraform used the **default local backend**, so state was ephemeral and gitignored —
fine for the mock, unfit for a device that **persists** its configuration. The target operating
model is that the Panorama is configured **exclusively through flux**.

Two properties of Panorama shape the decision:
- It has **one configuration that must be internally consistent**, with one candidate and a
  (scopeable) commit. Splitting Terraform state *per use case* would not split the device — every
  state would write the same shared candidate, and a global `<commit>` would promote other states'
  in-flight changes.
- It is **two-dimensional (Template ↔ Device-Group) and coupled** — the NAT use case references
  the template's zone/interface and the device-group binds the template stack — so the consistency
  unit is template+device-group **together**, not either dimension and not a use case.

### Current Limitations

1. No persistent state ⇒ no source of truth for "what exists"; every run would re-create.
2. No drift signal ⇒ out-of-band GUI/CLI edits go unnoticed.
3. No durable mock ⇒ a persistent-state demo against the mock would drift (state remembers, the
   in-memory mock forgets between jobs).

## Decision Drivers

### Primary Decision Drivers

1. **One consistent config**: model the device as a single coherent desired state, converged whole.
2. **GitLab-native, no new infra** (consistent with ADR-0003): reuse the runtime we already have.
3. **No accidental destruction**: a change to one object must not remove another.
4. **Industry alignment**: match the proven PAN-OS-as-code pattern, not a bespoke engine.

### Secondary Decision Drivers

1. **Verifiable "no drift"** claim. 2. **Honest mock** (durability mirrors the real device).

## Considered Options

### Option 1: One authoritative state + data-driven full converge (Terraform, GitLab backend)

**Description**: One GitLab-managed Terraform state for the whole managed config. The desired
config lives in git as data records (`terraform/desired/*.yaml`) and the root converges the FULL
set every run, `for_each`-ing over records. Out-of-band commit (Terraform cannot commit in-band);
scheduled `terraform plan -detailed-exitcode` as a drift watcher; Panorama RBAC makes flux the sole
writer. The mock gains `--state-file` durability so CI mirrors a persistent device.

**Technical Characteristics**:
- GitLab HTTP backend (`CI_JOB_TOKEN` auth, built-in locking); `for_each` keyed by record name.
- Reuses the existing `panos` v2 provider (ADR-0005) and the out-of-band commit step.

**Advantages**:
- Matches Panorama's one-consistent-config reality; adding/removing a record touches only that
  object (no sibling destroy); per-state locking; the de-facto industry pattern (YAML+`for_each`).

**Disadvantages**:
- The plural ordered `*_rules` provider resources need care when many records share a rulebase.

**Risk Assessment**:
- **Technical Risk**: Low. Standard Terraform + GitLab-native state.
- **Schedule Risk**: Low. Localized to the root, CI, mock, docs.
- **Ecosystem Risk**: Low. No new components.

### Option 2: Multiple states per use case (or per dimension)

**Description**: Separate Terraform state per use case / per device-group.

**Advantages**: Per-state isolation in Terraform.

**Disadvantages**: A Panorama has ONE config + one shared candidate; multiple states still write it
and a global commit promotes each other's in-flight work. Per-use-case `count`-gating in one state
would **destroy** deselected siblings on the device.

**Risk Assessment**:
- **Technical Risk**: High. Destroy-on-deselect / cross-state commit coupling.
- **Schedule Risk**: Medium. **Ecosystem Risk**: Low.

**Disqualifying Factor**: Contradicts the one-consistent-config invariant.

### Option 3: Bespoke XML config-as-code reconciler (no Terraform state)

**Description**: Treat the desired XML as truth; diff vs the device; push deltas via the XML-API.

**Advantages**: Full coverage; device is its own state; no external state file.

**Disadvantages**: Reinvents diff/ordering/idempotency the `panos` provider already gives; not the
industry norm; revisits ADR-0005.

**Risk Assessment**:
- **Technical Risk**: Medium-High. **Schedule Risk**: High. **Ecosystem Risk**: Medium.

## Decision

Adopt **Option 1**. The implementation uses:
- **GitLab-managed Terraform state** (HTTP backend, `CI_JOB_TOKEN`) — one state (`flux`) for the
  whole managed config.
- **Git desired-state** under `terraform/desired/` (`network.yaml` + `apps/*.yaml` + `nat/*.yaml`),
  converged as a whole via `for_each`; the template+device-group scaffolding stays a singleton.
- **Out-of-band `<commit>`** after apply (kept), and a **scheduled drift job**
  (`plan -detailed-exitcode`).
- **Mock `--state-file`** durability (stdlib JSON) + GitLab cache so the mock-target CI is honest.
- **Panorama RBAC** (documented) so flux is the sole read-write admin.

## Consequences

### Positive

1. **One consistent, reproducible config**: apply-from-git reproduces the managed device config.
2. **No accidental destroys**: record-keyed `for_each` isolates per-object changes.
3. **Verifiable ownership**: the scheduled drift job catches out-of-band edits.
4. **No new infrastructure**; reuses ADR-0005's provider and the existing commit step.

### Negative

1. **Coverage is bounded by the `panos` provider** (full 1:1 only for the modeled surface).
2. **Plural ordered `*_rules`** resources need a single owner per rulebase as records scale.

### Neutral

1. Reproduction source is **git + `terraform apply`**, not the state file (state is the
   convergence ledger). Brownfield adoption uses `terraform import`.

## Decision Outcome

flux holds the managed Panorama config as one authoritative, persistent, git-sourced state that is
converged as a whole, with drift detection and a durable mock — matching the real device's
single-consistent-config model and the industry PAN-OS-as-code pattern.

Mitigations:
- Document the brownfield `import` runbook and the local-dev backend override.
- Note the ordered-`*_rules` ownership caveat for multi-record growth.

## Related Decisions

- [ADR-0003: Develop on GitHub, Run on GitLab](0003-github-dev-gitlab-runtime.md) — the GitLab runtime hosting the state backend.
- [ADR-0005: Use the panos Terraform Provider v2](0005-use-the-panos-terraform-provider-v2.md) — the apply path this state tracks.
- [ADR-0004: Mock Panorama in Python stdlib](0004-mock-server-python-stdlib.md) — `--state-file` durability stays within its stdlib-only remit.

## Links

- [GitLab-managed Terraform state](https://docs.gitlab.com/ee/user/infrastructure/iac/terraform_state.html)
- [pan.dev — Policy as Code from YAML](https://pan.dev/terraform/docs/panos/guides/policy-from-yaml/)
- `examples/gitlab/STATE-MANAGEMENT.md` — operator guide (backend, drift, RBAC, import, lab-vs-mock).

## More Information

- **Date:** 2026-06-26
- **Source:** `terraform/` (data-driven root + `desired/`), `examples/gitlab/.gitlab-ci.yml`, `mock/panorama_mock.py`
- **Related ADRs:** 0003, 0004, 0005

## Audit

### 2026-06-26

**Status:** Pending

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Awaiting implementation audit | - | - | pending |

**Summary:** ADR created alongside the implementation; awaiting post-merge audit.

**Action Required:** Audit the merged implementation against this decision.
