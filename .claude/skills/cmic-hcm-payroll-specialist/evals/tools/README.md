# Eval tooling notes

## Two eval systems — don't confuse them

| File | Format | What it measures | Runner |
|---|---|---|---|
| `evals/evals.json` | `{skill_name, evals:[{id, prompt, expected_output, files, expectations}]}` | **Behaviour** — does the reply do what it should | skill-creator Eval mode: an executor subagent runs each prompt, a grader subagent scores the `expectations[]` array |
| `evals/trigger-evals.json` | top-level array of `{query, should_trigger, note}` | **Triggering** — does the description fire the skill | `scripts/run_eval.py` (this folder) |

`expected_output` is prose for a human reviewer. **`expectations[]` is what the grader
actually scores** — every eval must carry it or a run produces nothing comparable.

## Why this folder has a patched copy of run_eval.py

Upstream is `skill-creator/scripts/run_eval.py`. The copy here carries three fixes.
They are NOT upstreamed yet — if they prove out, push them to skill-creator.

1. **Python 3.9 compatibility.** Upstream uses `str | None` in signatures, which needs
   3.10+. This Mac has only 3.9.6 (`/usr/bin/python3`). Fixed by adding
   `from __future__ import annotations` to `run_eval.py` and `utils.py`.

2. **Installed skills were never detected.** Upstream decides "triggered" by looking for
   its own synthetic command name (`<skill>-skill-<uuid>`) in the `Skill` tool input.
   A skill installed at `~/.claude/skills/` is invoked under its **real** name, which
   never contains that uuid — so every positive query scored 0 (false negative).
   Fixed: accept either the synthetic name or the real `skill_name`.

3. **A non-Skill first tool call aborted the check.** Upstream returns `False` the moment
   the first tool call isn't `Skill` or `Read`. This skill's whole job is Beacon retrieval,
   so any other leading tool call scored it zero. Fixed: keep scanning instead of failing.

## Running the trigger eval

    cd evals/tools && PYTHONPATH=. python3 scripts/run_eval.py \
      --eval-set ../trigger-evals.json \
      --skill-path ../.. \
      --runs-per-query 3 --num-workers 10 --timeout 45 --verbose

**Requires a valid `claude` CLI login.** An expired OAuth token makes every subprocess
fail 401 and the whole run returns 0/N on positives while negatives "pass" vacuously —
a uniform zero across all positives means check auth before reading anything into it.
Re-authenticate by running `claude` interactively and completing the login prompt.
