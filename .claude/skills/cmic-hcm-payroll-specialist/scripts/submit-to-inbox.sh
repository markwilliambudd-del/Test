#!/usr/bin/env bash
# submit-to-inbox.sh — non-GitHub analyst path.
# Copies a local unverified finding into the shared OneDrive inbox so
# the maintainer can review and open a PR under their identity.
#
# Usage:  scripts/submit-to-inbox.sh <slug>
#
# Preconditions:
#   - The finding file exists at learned/unverified/<slug>.json locally
#   - The api-triage SharePoint library is synced to this machine
#     (path: ~/Library/CloudStorage/OneDrive-SharedLibraries-CMIC/api-triage/)
#
# Attribution: prompts for the analyst's name/email and writes it to
# the JSON as `contributed_by` so the maintainer's PR preserves it.

set -euo pipefail

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  echo "Usage: $0 <slug>" >&2
  echo "Example: $0 min-take-home-requires-highest-calc-sequence" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.claude/skills/cmic-hcm-payroll-specialist")"
UNVERIFIED="$REPO_ROOT/learned/unverified/${SLUG}.json"

if [[ ! -f "$UNVERIFIED" ]]; then
  echo "Error: no finding at $UNVERIFIED" >&2
  echo "" >&2
  echo "Available unverified findings on this machine:" >&2
  ls "$REPO_ROOT/learned/unverified/"*.json 2>/dev/null | while read -r f; do
    echo "  - $(basename "$f" .json)" >&2
  done
  exit 1
fi

INBOX="$HOME/Library/CloudStorage/OneDrive-SharedLibraries-CMIC/api-triage/HCM Specialist Findings Inbox/pending"

if [[ ! -d "$INBOX" ]]; then
  echo "Error: inbox folder is not synced on this machine:" >&2
  echo "  $INBOX" >&2
  echo "" >&2
  echo "Fixes to try:" >&2
  echo "  1. Confirm the api-triage SharePoint library is synced (in OneDrive settings)" >&2
  echo "  2. Confirm you have access to the library — ask the maintainer if unsure" >&2
  echo "  3. Wait for OneDrive to finish syncing after mounting the library" >&2
  exit 1
fi

# Attribution — prompt if not set via env vars
CONTRIBUTOR_NAME="${HCM_SPECIALIST_CONTRIBUTOR_NAME:-}"
CONTRIBUTOR_EMAIL="${HCM_SPECIALIST_CONTRIBUTOR_EMAIL:-}"

if [[ -z "$CONTRIBUTOR_NAME" ]]; then
  read -r -p "Your name (for finding attribution): " CONTRIBUTOR_NAME
fi
if [[ -z "$CONTRIBUTOR_EMAIL" ]]; then
  read -r -p "Your email (for finding attribution): " CONTRIBUTOR_EMAIL
fi

if [[ -z "$CONTRIBUTOR_NAME" || -z "$CONTRIBUTOR_EMAIL" ]]; then
  echo "Error: attribution requires both name and email." >&2
  echo "" >&2
  echo "Tip: set these in your shell profile to skip the prompt next time:" >&2
  echo "  export HCM_SPECIALIST_CONTRIBUTOR_NAME='Jane Doe'" >&2
  echo "  export HCM_SPECIALIST_CONTRIBUTOR_EMAIL='jane.doe@cmic.ca'" >&2
  exit 1
fi

# Add contributed_by to the JSON (preserves the original file)
DEST="$INBOX/${SLUG}.json"
if [[ -f "$DEST" ]]; then
  echo "Error: a finding with slug '$SLUG' is already pending in the inbox." >&2
  echo "  $DEST" >&2
  echo "Either use a different slug, or ask the maintainer to process the existing one." >&2
  exit 1
fi

python3 - "$UNVERIFIED" "$DEST" "$CONTRIBUTOR_NAME" "$CONTRIBUTOR_EMAIL" <<'PY'
import json, sys
src, dst, name, email = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(src) as f:
    data = json.load(f)
data["contributed_by"] = {"name": name, "email": email}
with open(dst, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"Wrote {dst}")
PY

echo ""
echo "Submitted to inbox."
echo "  Slug: $SLUG"
echo "  Attribution: $CONTRIBUTOR_NAME <$CONTRIBUTOR_EMAIL>"
echo "  Location: $DEST"
echo ""
echo "Next: the maintainer periodically imports the inbox and opens PRs."
echo "Your local copy at $UNVERIFIED is unchanged and can be deleted or kept."
