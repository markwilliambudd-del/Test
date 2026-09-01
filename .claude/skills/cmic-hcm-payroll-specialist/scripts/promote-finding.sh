#!/usr/bin/env bash
# promote-finding.sh — promote a finding from learned/unverified/ to learned/verified/ via PR.
#
# Usage:  scripts/promote-finding.sh <slug>
#
# Preconditions:
#   - The finding file exists at learned/unverified/<slug>.json (git-ignored, local-only)
#   - `gh` CLI is authenticated with repo write access
#   - Current directory is the skill repo root (or a subdirectory of it)
#
# What it does:
#   1. Validates the JSON entry (minimal schema check)
#   2. Creates a branch: verified-finding/<slug>-YYYYMMDD
#   3. Moves the file from unverified/ to verified/ (so git tracks it — unverified/ contents are gitignored)
#   4. Commits with a standard message
#   5. Pushes and opens a PR to main with the verified-finding template
#   6. Adds the `verified-finding` label
#
# The PR blocks on CODEOWNERS approval before merging.

set -euo pipefail

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  echo "Usage: $0 <slug>" >&2
  echo "Example: $0 min-take-home-requires-highest-calc-sequence" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

UNVERIFIED="learned/unverified/${SLUG}.json"
VERIFIED="learned/verified/${SLUG}.json"

if [[ ! -f "$UNVERIFIED" ]]; then
  echo "Error: no finding at $UNVERIFIED" >&2
  echo "Available unverified findings:" >&2
  ls learned/unverified/*.json 2>/dev/null || echo "  (none)" >&2
  exit 1
fi

if [[ -f "$VERIFIED" ]]; then
  echo "Error: a verified finding with slug '$SLUG' already exists at $VERIFIED" >&2
  echo "Pick a different slug or remove the existing entry first." >&2
  exit 1
fi

# Minimal JSON schema check: must have slug, title, question, answer, source_citation, verified_date
python3 - "$UNVERIFIED" <<'PY'
import json, sys
required = {"slug", "title", "question", "answer", "source_citation", "verified_date"}
with open(sys.argv[1]) as f:
    data = json.load(f)
missing = required - set(data.keys())
if missing:
    print(f"Error: finding is missing required fields: {sorted(missing)}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data.get("answer"), str) or len(data["answer"]) < 40:
    print("Error: 'answer' should be a non-trivial functional description (>= 40 chars)", file=sys.stderr)
    sys.exit(1)
print(f"Finding validates. Title: {data.get('title')}")
PY

DATE="$(date +%Y%m%d)"
BRANCH="verified-finding/${SLUG}-${DATE}"

# Check we're on main and up-to-date
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "Warning: not on main (currently on $CURRENT_BRANCH). Continue? [y/N]"
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi

echo "Fetching latest main..."
git fetch origin main
git checkout -B "$BRANCH" origin/main

# Move the file
mkdir -p learned/verified
git mv "$UNVERIFIED" "$VERIFIED" 2>/dev/null || {
  # unverified/ contents are gitignored, so `git mv` may fail. Fall back to plain mv + git add.
  mv "$UNVERIFIED" "$VERIFIED"
  git add "$VERIFIED"
}

TITLE="$(python3 -c "import json; print(json.load(open('$VERIFIED'))['title'])")"

git commit -m "$(cat <<COMMIT
Verify finding: ${TITLE}

Promotes learned/unverified/${SLUG}.json to learned/verified/${SLUG}.json.

Reviewer: confirm the functional description matches product intent
per the checklist in the PR body before approving.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
COMMIT
)"

git push -u origin "$BRANCH"

# Build the PR body from the template + finding contents
BODY_FILE="$(mktemp)"
python3 - "$VERIFIED" > "$BODY_FILE" <<'PY'
import json, sys, textwrap
with open(sys.argv[1]) as f:
    d = json.load(f)
print("## Verified finding — promote from `unverified/` to `verified/`")
print()
print(f"### Finding summary")
print()
print(f"- **Topic:** {d.get('title', '(missing)')}")
print(f"- **Slug:** `{d.get('slug', '(missing)')}`")
print(f"- **Origin question:** {d.get('question', '(missing)')}")
contributor = d.get("contributed_by")
if contributor:
    name = contributor.get("name", "?")
    email = contributor.get("email", "?")
    print(f"- **Contributed by:** {name} <{email}> (submitted via inbox; PR opened by the maintainer on their behalf)")
print()
print("### Functional answer")
print()
print(d.get('answer', '(missing)'))
print()
print(f"### Source citation")
print()
print(d.get('source_citation', '(missing)'))
print()
print("### Verification checklist for the reviewer")
print()
print("- [ ] The JSON `answer` describes the behaviour in functional / business voice — no code, SQL, table / column / package / procedure names, or repository paths")
print("- [ ] The JSON `source_citation` names an actual document in the HCM Document Library and the citation is accurate")
print("- [ ] The functional description matches product intent")
print("- [ ] Any accompanying library-gap Word draft has been reviewed")
print("- [ ] The finding does not duplicate an existing entry in `learned/verified/`")
print()
draft = d.get('companion_draft')
case = d.get('related_case')
if draft or case:
    print("### Related artifacts")
    print()
    if draft:
        print(f"- **Companion library-gap Word draft:** {draft}")
    if case:
        print(f"- **Related support case:** {case}")
    print()
notes = d.get('reviewer_notes')
if notes:
    print("### Notes for reviewer")
    print()
    print(notes)
PY

gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "Verify finding: ${TITLE}" \
  --body-file "$BODY_FILE" \
  --label "verified-finding" 2>&1 || {
  echo ""
  echo "Note: 'verified-finding' label may not exist yet. Create it with:"
  echo "  gh label create verified-finding --color 0e8a16 --description 'Promotes a specialist finding from unverified to verified'"
  echo ""
  # Retry without the label
  gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "Verify finding: ${TITLE}" \
    --body-file "$BODY_FILE"
}

rm -f "$BODY_FILE"

echo ""
echo "Promoted. PR is open — reviewer signoff required before merge."
echo "Once merged, all analysts get the verified finding on their next pull."
