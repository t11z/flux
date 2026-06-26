---
title: "Expose an Inbound ITSM Pipeline Trigger for a Single Use Case"
description: "ITSM starts the delivery pipeline via the GitLab trigger token API, selecting one Terraform use case with FLUX_MODULE + TF_VAR_* parameters; trigger runs auto-apply."
type: adr
category: architecture
tags: [gitlab, ci, itsm, trigger, terraform, gitops]
status: proposed
created: 2026-06-26
updated: 2026-06-26
author: "Thomas Sprock"
project: flux
related: [0003-github-dev-gitlab-runtime.md, 0005-use-the-panos-terraform-provider-v2.md]
---

# ADR-0006: Expose an Inbound ITSM Pipeline Trigger for a Single Use Case

## Status

Proposed

## Context

### Background and Problem Statement

The delivery pipeline integrated with ITSM in one direction only: the `commit` job POSTs an
outbound change record to `$ITSM_WEBHOOK_URL` after a successful run. The operationally valuable
direction was missing — an ITSM workflow, at a defined approval step, starting the pipeline to
apply the **one** Terraform use case that matches the workflow, with parameters the workflow
supplies (e.g. "publish app *billing-web* on these servers"). This makes ITSM the system of
record that *drives* change, not merely one that is *notified* of it.

Two properties must be settled because they form a public contract an external system hard-codes
against, and they change how applies are gated:

1. **How the change enters GitLab** (the trigger mechanism and parameter contract).
2. **How one use case is selected and run** given that the root Terraform composes three modules
   with a hard dependency chain.

### Current Limitations

1. No inbound path: no trigger token, no `CI_PIPELINE_SOURCE` handling, no parameter contract.
2. `terraform/main.tf` instantiates all three modules unconditionally
   (`template_network → panos_device_group.dg → {app_publish, nat_interplay}`), so a run is
   "all or nothing" — there is no way to apply a single use case.
3. `apply`/`commit` are always manual clicks, which defeats straight-through ITSM automation.

## Decision Drivers

### Primary Decision Drivers

1. **Lightweight skeleton**: prefer GitLab-native primitives and documented patterns over new
   services or infrastructure (consistent with ADR-0003/0004).
2. **Stable public contract**: the variable names ITSM hard-codes must be explicit and versioned
   in docs/ADR.
3. **Single root, single state**: keep one Terraform root and one state; do not fragment.
4. **Backward compatibility**: a normal developer push must behave exactly as before.

### Secondary Decision Drivers

1. **Auditability**: the selected use case and pipeline source should be visible in logs.
2. **Safety**: only an authorized, ITSM-sourced run may bypass the manual apply gate.

## Considered Options

### Option 1: GitLab pipeline **trigger token** + `count`-gated single root

**Description**: ITSM calls `POST /projects/:id/trigger/pipeline` with a trigger token, `ref`,
`variables[FLUX_MODULE]`, and `variables[TF_VAR_*]`. A single root var `flux_module` drives
`locals` that put `count` on each module/resource; selecting a dependent use case auto-enables
its prerequisites.

**Technical Characteristics**:
- No new infrastructure; GitLab exposes the endpoint natively.
- `CI_PIPELINE_SOURCE == "trigger"` distinguishes ITSM runs from pushes.
- Complex Terraform inputs pass as `TF_VAR_*` JSON/HCL literals — no pipeline parsing code.

**Advantages**:
- Minimal surface; one root, one state; full backward compatibility (`flux_module` defaults to `all`).
- Clear, documentable variable contract.

**Disadvantages**:
- `count` rewrites resource addresses (`dg` → `dg[0]`), a one-time state-move on persistent backends.

**Risk Assessment**:
- **Technical Risk**: Low. Native GitLab + standard Terraform `count`/`one()`.
- **Schedule Risk**: Low. Localized changes to CI + three Terraform files + docs.
- **Ecosystem Risk**: Low. No third-party components.

### Option 2: Custom inbound **webhook receiver** service

**Description**: Stand up a small service that receives ITSM webhooks and calls the GitLab API.

**Technical Characteristics**:
- A new always-on component with its own auth, hosting, and secrets.

**Advantages**:
- Could enforce richer validation/mapping before starting a pipeline.

**Disadvantages**:
- New infrastructure to run and secure; contradicts the skeleton's "no extra machinery" stance.

**Risk Assessment**:
- **Technical Risk**: Medium. More moving parts, another deployment.
- **Schedule Risk**: Medium. Service + ops work beyond the repo.
- **Ecosystem Risk**: Medium. Bespoke component to maintain.

**Disqualifying Factor**: GitLab already exposes a secure inbound trigger; a receiver adds cost for no skeleton benefit.

### Option 3: Per-use-case **root modules** (`terraform/usecases/<name>/`) or data sources

**Description**: Either a separate Terraform root per use case, or `data` lookups so dependent
modules run standalone assuming scaffolding exists.

**Advantages**:
- A root per use case trivially runs one use case.

**Disadvantages**:
- Duplicates the root composition and fragments state (roots), or fails against the empty mock
  and adds provider-read complexity (data sources). Breaks the single-root design in
  `terraform/CLAUDE.md`.

**Risk Assessment**:
- **Technical Risk**: Medium. State fragmentation or empty-device lookups.
- **Schedule Risk**: Medium. More files and duplication to maintain.
- **Ecosystem Risk**: Low.

## Decision

Adopt **Option 1**. The implementation will use:

- **A GitLab pipeline trigger token** as the inbound mechanism (`POST /trigger/pipeline`).
- **`FLUX_MODULE`** (`all | template_network | app_publish | nat_interplay`) as the selector,
  flowed to Terraform as **`TF_VAR_flux_module`**; object parameters as `variables[TF_VAR_*]`.
- **`count` + `locals` in the single Terraform root**, with a dependent use case auto-enabling
  its prerequisites so cross-references stay in range.
- **Source-aware gating**: `apply` and `commit` auto-run when
  `CI_PIPELINE_SOURCE == "trigger"`; a push to `main` keeps the manual gate.

## Consequences

### Positive

1. **Straight-through automation**: ITSM drives a scoped change end-to-end; ITSM is the approval gate.
2. **Backward compatible**: pushes behave exactly as before (`flux_module` defaults to `all`).
3. **No new infrastructure**: GitLab-native trigger; one root, one state.

### Negative

1. **State address change**: `count` makes `panos_device_group.dg[0]`; persistent backends need a one-time `terraform state mv`.
2. **Trust in the trigger token**: anyone holding it can start a (scoped) pipeline.

### Neutral

1. The outbound ITSM notification is unchanged; integration is now bidirectional.

## Decision Outcome

ITSM can apply a single use case with parameters via one authenticated call, while the everyday
push path is untouched. The `CI_PIPELINE_SOURCE` guard ensures only trigger runs auto-apply.

Mitigations:
- Document the state-move one-liner for persistent backends (`ITSM-TRIGGER.md`).
- Treat the trigger token as a masked secret with rotation; offer a `PANOS_PROTOCOL == "http"`
  qualifier so real-device trigger runs can still require a manual click if desired.

## Related Decisions

- [ADR-0003: Develop on GitHub, Run the Delivered GitOps on GitLab](0003-github-dev-gitlab-runtime.md) - the GitLab runtime this trigger plugs into.
- [ADR-0005: Use the panos Terraform Provider v2](0005-use-the-panos-terraform-provider-v2.md) - the apply path the selected use case drives.

## Links

- [GitLab pipeline trigger tokens](https://docs.gitlab.com/ee/ci/triggers/) - the inbound mechanism.
- `examples/gitlab/ITSM-TRIGGER.md` - the operator-facing guide and variable contract.

## More Information

- **Date:** 2026-06-26
- **Source:** flux delivery pipeline (`examples/gitlab/.gitlab-ci.yml`), `terraform/`
- **Related ADRs:** 0003, 0005

## Audit

### 2026-06-26

**Status:** Pending

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| Awaiting implementation | - | - | pending |

**Summary:** ADR created alongside the initial implementation; awaiting post-merge audit.

**Action Required:** Audit the merged implementation against this decision.
