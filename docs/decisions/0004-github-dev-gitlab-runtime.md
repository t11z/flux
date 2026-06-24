---
title: "Develop on GitHub, Run the Delivered GitOps on GitLab"
description: "flux is developed on GitHub; the GitOps it demonstrates runs on GitLab with a local runner."
type: adr
category: infrastructure
tags: [github, gitlab, ci, gitops]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
related: [0005-adopt-cc-project-bootstrap-conventions.md]
---

# ADR-0004: Develop on GitHub, Run the Delivered GitOps on GitLab

## Status

Accepted

## Context

### Background and Problem Statement

flux has two distinct CI/CD concerns that are easy to conflate: the CI that develops flux
itself, and the GitOps pipeline that flux *demonstrates and ships*. The repository bootstrap
(ADR-0005) provides GitHub Actions, while the firewall-automation use case targets GitLab with a
self-hosted runner. Treating these as one would create a false mismatch.

### Current Limitations

1. The bootstrap's CI is GitHub-native (OAuth workflows, App tokens).
2. The product's GitOps target is GitLab + a local runner.

## Decision Drivers

### Primary Decision Drivers

1. **Separation of concerns**: repo CI and delivered pipeline are different artifacts.
2. **No false mismatch**: GitHub workflows are correct for development; GitLab templates are
   correct for the delivered skeleton.

### Secondary Decision Drivers

1. **Clarity for contributors**: each layer has an obvious home in the repo.

## Considered Options

### Option 1: Two layers — GitHub dev, GitLab runtime templates

**Description**: Develop flux on GitHub (active repo CI). Ship the GitLab pipeline as skeleton
templates inside the repo (`examples/gitlab/`), wired to a local runner in later phases.

**Technical Characteristics**:
- `.github/workflows/` are real repo CI.
- `examples/gitlab/` will hold the delivered, inert-until-deployed pipeline.

**Advantages**:
- Each layer is correct and clearly separated; no disabling of useful CI.

**Disadvantages**:
- Two CI vocabularies in one repo (mitigated by directory separation).

**Risk Assessment**:
- **Technical Risk**: Low.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Low.

### Option 2: GitLab only (mirror the dev repo to GitLab)

**Description**: Develop and deliver entirely on GitLab.

**Technical Characteristics**:
- Single platform.

**Advantages**:
- One CI system.

**Disadvantages**:
- Discards the bootstrap's GitHub-native automation (smADR validation, OAuth security review,
  triage bot) that is wanted for development.

**Risk Assessment**:
- **Technical Risk**: Low.
- **Schedule Risk**: Medium. Re-implementing the bootstrap automation on GitLab.
- **Ecosystem Risk**: Medium.

**Disqualifying Factor**: Throws away the chosen GitHub development automation.

## Decision

flux is **developed on GitHub** (the bootstrap's workflows are real, active repo CI). The
**delivered GitOps runs on GitLab + a local runner** and lives as skeleton templates in the repo.

The implementation will use:
- **`.github/workflows/`** for development CI.
- **`examples/gitlab/`** (later phase) for the delivered pipeline templates.

## Consequences

### Positive

1. **No false mismatch**: GitHub workflows are not disabled; they belong to the dev layer.
2. **Clear delivery story**: the GitLab pipeline is an artifact flux ships, not its own CI.

### Negative

1. **Two CI vocabularies** coexist in the repo.

### Neutral

1. The GitLab templates are inert until deployed to a GitLab project with a runner.

## Decision Outcome

A clean separation between developing flux and the GitOps flux demonstrates.

Mitigations:
- Directory separation and CLAUDE.md wayfinding make the two layers obvious.

## Related Decisions

- [ADR-0005: Adopt cc-project-bootstrap Conventions](0005-adopt-cc-project-bootstrap-conventions.md) - source of the GitHub automation.

## Links

- [GitLab self-managed runners](https://docs.gitlab.com/runner/) - the delivered runtime.

## More Information

- **Date:** 2026-06-24
- **Source:** Project framing in the Engram `flux` note.
- **Related ADRs:** ADR-0005.

## Audit

### 2026-06-24

**Status:** Partial

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| GitHub dev CI present | .github/workflows/ | - | compliant |
| GitLab delivery templates | examples/gitlab/ | - | pending (later phase) |

**Summary:** The development layer (GitHub) is in place; the delivered GitLab pipeline templates are a later phase.

**Action Required:** Add `examples/gitlab/` skeleton in a later phase.
