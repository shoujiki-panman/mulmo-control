# Agent Instructions

Mulmo Control uses Issue #67 as the single source of truth for AI QA and security work:

https://github.com/shoujiki-panman/mulmo-control/issues/67

Do not rely on chat memory. At the start of every task in this repo:

```bash
git fetch origin --prune
git status -sb
./qa/diagnose
./qa/check
./qa/next
```

If network access is unavailable, say that you could not refresh Issue #67 and continue from the local instructions here.

## Workflow

1. Read this file, `CLAUDE.md`, `SECURITY.md`, and Issue #67 before changing code.
2. Add or extend a failing check before fixing a recurring bug class.
3. Keep deterministic checks in `check.sh` or `qa/`.
4. Update `qa/patterns.tsv` when a catalog item becomes covered.
5. Lower `.mulmo-control-qa/baseline.json` only when coverage improves. Do not raise it just to pass a check.
6. Do not commit, push, release, auto-freeze, or update `main` unless the user explicitly asks.

## Risk Boundaries

Changes touching install, uninstall, self-update, release, LaunchAgent, shell execution, `app-info.env`, or network downloads are high-risk. They need a reproducible check and human review.

Treat `app-info.env` as data, not shell. Read it through `scripts/mulmo-control-config`; do not `source` or `.` that file directly.
