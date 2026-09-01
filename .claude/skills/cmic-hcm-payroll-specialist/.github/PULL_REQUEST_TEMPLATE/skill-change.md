## Skill change — behaviour, evals, or corrections

> For changes to `SKILL.md`, `evals/`, or `corrections.jsonl` — anything that alters how the
> specialist behaves in future sessions. For promoting a finding from `learned/unverified/`
> to `learned/verified/`, use `verified-finding.md` instead.

### Change summary

- **Scope:** _(which files — SKILL.md / evals/evals.json / evals/trigger-evals.json / corrections.jsonl / evals/tools/)_
- **Type:** _(new behaviour · behavioural correction · new eval coverage · eval fix · tooling — delete what doesn't apply)_
- **Origin:** _(what prompted this — a live session where the skill misbehaved, a user correction, a gap noticed during review, a doc change)_
- **Not included:** _(anything deliberately left out of this PR, and why)_

### What changes about how the skill behaves

_(Plain description of the before and after. If nothing about runtime behaviour changes — e.g. an
evals-only PR — say so explicitly, so the reviewer knows not to look for it.)_

### Consistency check

Changes here interact. Confirm the ones that apply:

- [ ] `SKILL.md` and `corrections.jsonl` do not now contradict each other
- [ ] No eval's `expected_output` or `expectations[]` still encodes a rule a later correction reversed
- [ ] A new behavioural rule has eval coverage, and a new eval has a rule behind it in SKILL.md or corrections.jsonl
- [ ] A correction is behavioural ("the skill should do X"), not product-truth ("CMiC does X") — product-truth belongs in `learned/verified/`
- [ ] Guardrail wording matches the current standard: data-level detail (source tables/view, transaction-type codes, per-row columns) is permitted; code plumbing (SQL/code syntax, package / procedure / function / trigger names, method calls, session mechanics, repository paths, API endpoints) is not

### Eval status

- [ ] Trigger eval run — **result:** _(N/N passed, or "not run" + why)_
- [ ] Behavioural eval run (executor + grader) — **result:** _(pass rate, or "not run" + why)_
- [ ] Every eval touched or added carries an `expectations[]` array

**Do not claim a suite passes unless it was actually executed.** A uniform `0/N` on positives in a
trigger run means the `claude` CLI login has expired, not that the description is broken — see
`evals/tools/README.md`.

### Review checklist

- [ ] The change is the smallest one that addresses the origin
- [ ] Wording is unambiguous — a future session reading it cannot reasonably do the wrong thing
- [ ] No customer data, case detail, or credentials in any added text
- [ ] Assertions are verifiable statements, not restatements of the prose around them

### Related artifacts

- **Related correction:** _(scope + date in corrections.jsonl, or "None")_
- **Related support case:** _(Jira case number, or "None — internal")_
- **Companion Word draft:** _(filename in ~/cm32/Triage Folder/, or "None")_

### Notes for reviewer

_(Where to look first, what's easy to miss in the diff, anything deliberately deferred to a
follow-up, and any suggested change to the tooling or the templates themselves.)_
