#!/usr/bin/env bash
set -euo pipefail

# Interactive helper for the one-time secret/App setup.
# Authenticates Claude via CLAUDE_CODE_OAUTH_TOKEN — never ANTHROPIC_API_KEY.

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

bold "Claude project — setup helper"

# --- preconditions ---
step "Checking prerequisites"
HAVE_GH=1
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh CLI present and authenticated"; else
    warn "gh CLI present but not authenticated — run: gh auth login"; HAVE_GH=0; fi
else
  warn "gh CLI not found — secrets must be set manually in repo Settings → Secrets"; HAVE_GH=0
fi

REPO=""
if [ "$HAVE_GH" = "1" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$REPO" ] && ok "Repository: $REPO"
fi

set_secret() {
  # $1 = secret name; reads value from stdin or file arg $2
  local name="$1"; shift || true
  if [ "$HAVE_GH" = "1" ]; then
    if [ "${1:-}" = "--file" ]; then gh secret set "$name" < "$2"; else gh secret set "$name"; fi
    ok "set secret $name"
  else
    warn "set $name manually in Settings → Secrets and variables → Actions"
  fi
}

# --- 1. OAuth token ---
step "1. Claude OAuth token (CLAUDE_CODE_OAUTH_TOKEN)"
echo "Generate a token with:  claude setup-token"
echo "It looks like: sk-ant-oat..."
read -r -p "Set CLAUDE_CODE_OAUTH_TOKEN now? [y/N] " ans
if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
  echo "Paste the token, then press Enter:"
  set_secret CLAUDE_CODE_OAUTH_TOKEN
fi

# --- 2. GitHub App ---
step "2. GitHub App for the triage bot"
cat <<'TXT'
Create a GitHub App (Settings → Developer settings → GitHub Apps → New App):
  Repository permissions:
    - Issues:        Read & write
    - Pull requests: Read & write
    - Contents:      Read & write
  Subscribe to events: Issues, Issue comment, Pull request
Then: generate a private key (.pem), note the App ID, and Install the App on this repo.
TXT
read -r -p "Have you created and installed the App? [y/N] " ans
if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
  read -r -p "App ID: " app_id
  if [ -n "${app_id:-}" ]; then printf '%s' "$app_id" | { [ "$HAVE_GH" = "1" ] && gh secret set APP_ID --body "$app_id" && ok "set secret APP_ID" || warn "set APP_ID manually"; }; fi
  read -r -p "Path to private-key .pem: " pem
  if [ -n "${pem:-}" ] && [ -f "$pem" ]; then set_secret APP_PRIVATE_KEY --file "$pem"; else warn "pem not found; set APP_PRIVATE_KEY manually"; fi
fi

# --- 3. hardening reminder ---
step "3. Hardening (manual)"
echo "  - Settings → Actions: Require approval for all external contributors"
echo "  - Branch protection on main: require CI + ADR-validation checks"

step "Done"
echo "Secrets needed: CLAUDE_CODE_OAUTH_TOKEN, APP_ID, APP_PRIVATE_KEY"
[ "$HAVE_GH" = "1" ] && gh secret list || true
