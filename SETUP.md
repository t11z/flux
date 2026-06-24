# Setup

One-time setup so the Claude workflows can run. All Claude authentication uses
`CLAUDE_CODE_OAUTH_TOKEN` — never `ANTHROPIC_API_KEY`.

## Secrets to create

| Secret | Used by | How to get it |
|--------|---------|---------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | security-review, issue-triage | `claude setup-token` (locally, Pro/Max account) |
| `APP_ID` | issue-triage | GitHub App → App ID |
| `APP_PRIVATE_KEY` | issue-triage | GitHub App → generated private key (.pem contents) |

## 1. Claude OAuth token

```bash
claude setup-token
```

Copy the token (`sk-ant-oat...`) and store it as the repo secret `CLAUDE_CODE_OAUTH_TOKEN`:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

These tokens are CI-capable but finite. If a workflow fails with an auth error,
regenerate and update the secret.

## 2. GitHub App (for the triage bot)

The triage bot acts as a GitHub App so it has a real identity and so the PRs it
opens can trigger your other workflows (the default `GITHUB_TOKEN` cannot do that).

Run the helper, which walks you through it and pre-fills the required permissions:

```bash
./scripts/bootstrap-github-app.sh
```

Or do it manually:

1. Create a GitHub App (Settings → Developer settings → GitHub Apps → New).
   Repository permissions: **Issues: Read & write**, **Pull requests: Read & write**,
   **Contents: Read & write**. Subscribe to events: Issues, Issue comment, Pull request.
2. Generate a private key (.pem) and note the App ID.
3. Install the App on this repository.
4. Store the secrets:
   ```bash
   gh secret set APP_ID
   gh secret set APP_PRIVATE_KEY < path/to/private-key.pem
   ```

## 3. Repository hardening

- Settings → Actions → "Require approval for all external contributors" (the
  security-review workflow only runs on same-repo PRs, but keep this on).
- Branch protection on `main`: require the CI and ADR-validation checks to pass.

## What runs when

- **CI** (`ci.yml`) — on push to main and on PRs.
- **ADR validation** (`adr-validate.yml`) — on changes under `docs/decisions/`.
- **Security review** (`security-review.yml`) — on same-repo PRs (OAuth, deterministic FP-filtering).
- **Triage** (`issue-triage.yml`) — auto-labels/comments new issues & PRs; checks for ADR-breaking requests; opens PRs only when a maintainer comments `@claude implement`.
