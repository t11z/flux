---
description: Create a new Structured MADR (smADR) under docs/decisions/
allowed-tools: Read, Glob, Grep, LS, Write, Edit, Bash(ls:*), Bash(git log:*)
---

You are creating a new Architecture Decision Record in Structured MADR format.

CONTEXT — existing ADRs:

```
!`ls -1 docs/decisions/ 2>/dev/null | grep -E '^(adr_|[0-9])' || echo "none yet"`
```

OBJECTIVE:
Write a new smADR for the decision the user describes. Follow these steps:

1. **Confirm it warrants an ADR.** It does if the decision is hard to reverse, spans multiple layers / a public interface / a contract, pins an invariant / provider / stack building block, or displaces a plausible alternative worth recording. If it is merely an implementation detail, local refactor, naming, helper structure, or test layout, say so and stop — that belongs in code review or a CLAUDE.md, not an ADR. When genuinely unsure, proceed with `status: proposed`.

2. **Assign the next ID.** Inspect the existing files above; use the next zero-padded number. First ADR is `0001`.

3. **Draft the ADR** from `docs/decisions/adr-template.md`. Requirements:
   - Frontmatter complete and valid (title, description, type: adr, category, tags, status, created/updated = today, author, project).
   - At least **two** seriously developed options, each with a risk assessment (Technical / Schedule / Ecosystem). A single real option means it is not a decision — reconsider whether an ADR is warranted.
   - Consequences must include honest **Negative** entries. An ADR with no downsides is suspect.
   - Body sections in English, in the required order, including the mandatory **Audit** section with an initial `Pending` entry.
   - Default `status: proposed` unless the user states the decision is already settled.

4. **Write** the file to `docs/decisions/{NNNN}-{slug}.md` and add a row to the index table in `docs/decisions/README.md`.

5. If this decision supersedes an existing ADR, set `status: superseded` + `superseded_by` on the old one is NOT allowed (append-only). Instead, note `Supersedes ADR-XXXX` in the new ADR's Status section and add `superseded_by` to the old ADR's frontmatter only — do not edit the old ADR's body.

Schema reference: https://smadr.dev/
