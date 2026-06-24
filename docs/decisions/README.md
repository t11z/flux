# Architecture Decision Records

This directory holds Architecture Decision Records (ADRs) in [Structured MADR](https://smadr.dev/) format. They are validated in CI by `.github/workflows/adr-validate.yml`.

## When to write an ADR

Write one when a decision:

- is hard to reverse, or
- spans multiple layers, a public interface, or a contract, or
- pins an invariant, a provider, or a stack building block, or
- displaces a plausible alternative worth recording.

Do **not** write one for implementation details, local refactors, naming, helper structures, or test layout. When unsure, open one in `proposed` status.

## File naming

`{NNNN}-{slug}.md`, zero-padded sequential number — e.g. `0001-use-postgresql-for-primary-storage.md`. Copy `adr-template.md` as the starting point, or run `/adr-new`.

## Lifecycle

`proposed` → `accepted` → (`deprecated` | `superseded`)

ADRs are **append-only**. Once `accepted`, the body is immutable. To change a decision, write a new ADR and link them via `supersedes` / `superseded_by`.

## Required sections

Frontmatter (title, description, type, category, tags, status, created, updated, author, project) plus body sections Status, Context, Decision Drivers, Considered Options (with per-option risk assessment), Decision, Consequences, Decision Outcome, and a mandatory Audit section. The full schema is enforced by the validator.

## Index

| ID | Title | Status |
|----|-------|--------|
| [0001](0001-target-the-panorama-xml-api.md) | Target the Panorama XML-API, Not the REST API | accepted |
| [0002](0002-derive-schema-from-live-probing.md) | Derive the Schema From Live Probing and Fixtures | accepted |
| [0003](0003-github-dev-gitlab-runtime.md) | Develop on GitHub, Run the Delivered GitOps on GitLab | accepted |
| [0004](0004-mock-server-python-stdlib.md) | Build the Mock Panorama Server in Python Stdlib | accepted |
