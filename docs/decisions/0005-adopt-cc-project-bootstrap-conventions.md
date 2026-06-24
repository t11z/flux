---
title: "Adopt cc-project-bootstrap Conventions"
description: "Use cc-project-bootstrap for the CLAUDE.md hierarchy, smADRs, and OAuth-based GitHub CI."
type: adr
category: architecture
tags: [bootstrap, adr, ci, conventions]
status: accepted
created: 2026-06-24
updated: 2026-06-24
author: "Thomas Sprock"
project: flux
related: [0004-github-dev-gitlab-runtime.md]
---

# ADR-0005: Adopt cc-project-bootstrap Conventions

## Status

Accepted

## Context

### Background and Problem Statement

flux needs a traceable implementation history (why/what/when) and a consistent project
structure. The architect chose the `cc-project-bootstrap` plugin, which is opinionated and
stack-agnostic: a CLAUDE.md hierarchy, smADRs in `docs/decisions/`, slash commands/agents/skills
for ADR authoring and security review, and OAuth-only GitHub workflows.

### Current Limitations

1. Before bootstrapping, the repo had no decision history, ADR format, or CI.

## Decision Drivers

### Primary Decision Drivers

1. **Traceable decisions**: smADRs capture why/what/when in a validated format.
2. **Consistency**: a single, opinionated convention set rather than ad-hoc files.

### Secondary Decision Drivers

1. **Low maintenance**: CLAUDE.md carries conventions; architecture lives in ADRs.

## Considered Options

### Option 1: Adopt cc-project-bootstrap

**Description**: Apply the plugin's full structure (CLAUDE.md hierarchy, `docs/decisions/`,
`.claude/` commands/agents/skill, GitHub workflows, templates, Dependabot, SETUP).

**Technical Characteristics**:
- smADR validation in CI; OAuth-only auth; SHA-pinned actions.

**Advantages**:
- Ready-made, validated ADR workflow and a consistent structure.
- Its conventions already mandate the desired English-repo language regime.

**Disadvantages**:
- Heavier than strictly necessary; some workflows need secrets to run.

**Risk Assessment**:
- **Technical Risk**: Low. Files are inert without secrets.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Medium. GitHub-specific automation (acceptable per ADR-0004).

### Option 2: Plugin-free, hand-rolled ADR files

**Description**: Maintain a minimal `docs/decisions/` and a changelog by hand.

**Technical Characteristics**:
- No CI validation, no tooling.

**Advantages**:
- No external dependency.

**Disadvantages**:
- No validation; conventions drift over time.

**Risk Assessment**:
- **Technical Risk**: Medium. Unvalidated ADRs rot.
- **Schedule Risk**: Low.
- **Ecosystem Risk**: Low.

**Disqualifying Factor**: No enforcement; loses the consistency the architect asked for.

## Decision

Adopt **cc-project-bootstrap** in full. Use smADRs in `docs/decisions/`, the CLAUDE.md hierarchy,
the `.claude/` ADR and security-review tooling, and the OAuth GitHub workflows. CI is adapted to
the flux stack (Python tests + schema-drift check).

The implementation will use:
- **`.claude/`**, **`docs/decisions/`**, **`.github/`**, **`SETUP.md`** from the bootstrap.

## Consequences

### Positive

1. **Validated decision history**: smADRs checked in CI.
2. **Consistent structure** and language regime out of the box.

### Negative

1. **GitHub automation needs secrets** (OAuth token, GitHub App) to run; the architect sets them up.

### Neutral

1. AIRS hooks were declined (default); can be added later.

## Decision Outcome

A consistent, validated project structure with a traceable decision history.

Mitigations:
- `SETUP.md` documents the one-time secret setup; workflows are inert until then.

## Related Decisions

- [ADR-0004: GitHub Dev, GitLab Runtime](0004-github-dev-gitlab-runtime.md) - why GitHub automation is correct here.

## Links

- [cc-project-bootstrap](https://github.com/t11z/cc-project-bootstrap) - the plugin.
- [smADR](https://smadr.dev/) - the ADR format.

## More Information

- **Date:** 2026-06-24
- **Source:** Plugin assets under the bootstrap skill.
- **Related ADRs:** ADR-0004.

## Audit

### 2026-06-24

**Status:** Compliant

**Findings:**

| Finding | Files | Lines | Assessment |
|---------|-------|-------|------------|
| CLAUDE.md hierarchy present | CLAUDE.md, tools/CLAUDE.md | - | compliant |
| smADR scaffold + ADRs | docs/decisions/ | - | compliant |
| ADR/security tooling | .claude/ | - | compliant |
| OAuth CI, SHA-pinned, CI adapted | .github/workflows/ | - | compliant |

**Summary:** The bootstrap is applied; CI is adapted to the flux stack; AIRS declined.

**Action Required:** Architect to configure CI secrets per SETUP.md.
