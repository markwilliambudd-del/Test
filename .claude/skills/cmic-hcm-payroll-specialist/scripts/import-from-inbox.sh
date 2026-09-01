#!/usr/bin/env bash
# import-from-inbox.sh — maintainer side.
# Polls the OneDrive inbox for pending findings from non-GitHub analysts,
# validates each, imports to local learned/unverified/, and calls
# promote-finding.sh to open a PR under the maintainer's identity
# (with `contributed_by` attribution preserved in the PR body).
#
# Usage:  scripts/import-from-inbox.sh [--dry-run]
#
# Preconditions:
#   - Run by the maintainer (Imran) on their machine
#   - `gh` CLI is authenticated with repo write access
#   - promote-finding.sh is present alongside this script
#
# Behaviour:
#   - Lists all JSONs in inbox/pending/
#   - For each: validates schema, copies to local learned/unverified/,
#     runs promote-finding.sh <slug>, moves the inbox file to processed/
#   - Files that fail validation move to rejected/ with a .reason file
#   - Files with slugs that already exist in verified/ or an open PR are
#     rejected as duplicates

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1 && echo "DRY RUN — no changes will be made."

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.claude/skills/cmic-hcm-payroll-specialist")"
cd "$REPO_ROOT"

INBOX_BASE="$HOME/Library/CloudStorage/OneDrive-SharedLibraries-CMIC/api-triage/HCM Specialist Findings Inbox"
PENDING="$INBOX_BASE/pending"
PROCESSED="$INBOX_BASE/processed"
REJECTED="$INBOX_BASE/rejected"

if [[ ! -d "$PENDING" ]]; then
  echo "Error: inbox pending folder not found:" >&2
  echo "  $PENDING" >&2
  exit 1
fi

shopt -s nullglob
PENDING_FILES=("$PENDING"/*.json)

if [[ ${#PENDING_FILES[@]} -eq 0 ]]; then
  echo "Inbox is empty. Nothing to import."
  exit 0
fi

echo "Found ${#PENDING_FILES[@]} pending finding(s) in inbox."
echo ""

# Ensure we're on main and up-to-date
git fetch origin main >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git pull --ff-only origin main >/dev/null 2>&1

IMPORTED=0
REJECTED_COUNT=0

for f in "${PENDING_FILES[@]}"; do
  fname="$(basename "$f")"
  slug="${fname%.json}"
  echo "----------------------------------------"
  echo "Processing: $fname"

  # Validate schema
  set +e
  reason="$(python3 - "$f" 2>&1 <<'PY'
import json, sys
required = {"slug", "title", "question", "answer", "source_citation", "verified_date"}
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception as e:
    print(f"invalid JSON: {e}", file=sys.stdout); sys.exit(1)
missing = required - set(data.keys())
if missing:
    print(f"missing required fields: {sorted(missing)}"); sys.exit(1)
if not isinstance(data.get("answer"), str) or len(data["answer"]) < 40:
    print("'answer' should be a non-trivial functional description (>= 40 chars)"); sys.exit(1)
if data.get("slug") != sys.argv[1].split("/")[-1].removesuffix(".json"):
    print("slug in JSON must match filename"); sys.exit(1)
PY
)"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "  REJECTED (schema): $reason"
    if [[ $DRY_RUN -eq 0 ]]; then
      mv "$f" "$REJECTED/$fname"
      echo "$reason" > "$REJECTED/${slug}.reason"
    fi
    REJECTED_COUNT=$((REJECTED_COUNT + 1))
    continue
  fi

  # Duplicate check: already verified on main?
  if [[ -f "$REPO_ROOT/learned/verified/${slug}.json" ]]; then
    echo "  REJECTED (duplicate): slug already exists in learned/verified/ on main"
    if [[ $DRY_RUN -eq 0 ]]; then
      mv "$f" "$REJECTED/$fname"
      echo "duplicate: already exists in learned/verified/${slug}.json" > "$REJECTED/${slug}.reason"
    fi
    REJECTED_COUNT=$((REJECTED_COUNT + 1))
    continue
  fi

  # Duplicate check: an open PR already promoting this slug?
  open_pr="$(gh pr list --state open --search "verified-finding/${slug}-" --json number,url --jq '.[0].url' 2>/dev/null || echo "")"
  if [[ -n "$open_pr" ]]; then
    echo "  REJECTED (duplicate): open PR exists: $open_pr"
    if [[ $DRY_RUN -eq 0 ]]; then
      mv "$f" "$REJECTED/$fname"
      echo "duplicate: open PR $open_pr" > "$REJECTED/${slug}.reason"
    fi
    REJECTED_COUNT=$((REJECTED_COUNT + 1))
    continue
  fi

  # Import to local unverified/
  DEST="$REPO_ROOT/learned/unverified/${slug}.json"
  echo "  Importing to $DEST"
  if [[ $DRY_RUN -eq 0 ]]; then
    cp "$f" "$DEST"
    contributor="$(python3 -c "import json; d=json.load(open('$DEST')); c=d.get('contributed_by',{}); print(f\"{c.get('name','?')} <{c.get('email','?')}>\")")"
    echo "  Contributor: $contributor"

    echo "  Running promote-finding.sh..."
    if "$REPO_ROOT/scripts/promote-finding.sh" "$slug"; then
      echo "  PR opened."
      mv "$f" "$PROCESSED/$fname"
      IMPORTED=$((IMPORTED + 1))
      # Return to main for the next iteration
      git checkout main >/dev/null 2>&1
    else
      echo "  ERROR: promote-finding.sh failed. Leaving JSON in inbox for retry."
      rm -f "$DEST"
      REJECTED_COUNT=$((REJECTED_COUNT + 1))
    fi
  else
    echo "  (dry-run: would import + promote)"
  fi
done

echo ""
echo "========================================"
echo "Import summary:"
echo "  Imported to PR: $IMPORTED"
echo "  Rejected:       $REJECTED_COUNT"
echo ""
[[ $REJECTED_COUNT -gt 0 ]] && echo "Check $REJECTED for rejected files and .reason explanations."
