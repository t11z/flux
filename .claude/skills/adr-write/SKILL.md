---
name: adr-write
description: Writes a Structured MADR (smADR) architecture decision record for this project under docs/decisions/. Use when the user says "write an ADR", "document this decision", "decision record", "ADR for X", or wants a decision with trade-offs captured. Enforces the smADR schema, the project's ADR-trigger criteria, and the append-only lifecycle.
---

# ADR Write (smADR, project-local)

Writes architecture decision records for this repository in Structured MADR format. One decision per ADR, English, append-only once accepted. Schema: https://smadr.dev/ — condensed in the project's bootstrap reference; full template at `docs/decisions/adr-template.md`.

## Gate

Write an ADR only when the decision is hard to reverse, spans multiple layers / a public interface / a contract, pins an invariant / provider / stack building block, or displaces a plausible alternative worth recording. Not for implementation details, local refactors, naming, helper structures, or test layout. When unsure: `status: proposed`.

## Procedure

1. Determine the next zero-padded ID from `docs/decisions/`.
2. Copy `docs/decisions/adr-template.md`. Fill frontmatter (title, description, type: adr, category, tags, status, created/updated = today, author, project).
3. Develop **at least two** real options, each with Technical / Schedule / Ecosystem risk assessment.
4. State Consequences honestly, including Negative ones.
5. Keep all required body sections in order, including the mandatory Audit section (initial `Pending` entry).
6. Write to `docs/decisions/{NNNN}-{slug}.md`; add a row to the index in `docs/decisions/README.md`.

## Append-only

Once `accepted`, the body is immutable. To revise, write a new ADR, note `Supersedes ADR-XXXX` in its Status, and set only `superseded_by` in the old ADR's frontmatter. Never edit an accepted body.

## Output language

The ADR is written in English (repository-artifact rule). Discussion with the architect happens in the architect's language.
