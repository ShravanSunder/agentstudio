# PR0 Review Comparison Basis — Accepted Delta

This document supersedes the older PR0 artifacts only where they describe a
common-commit-only comparison or the comparison popup. All other PR0 boundaries
remain unchanged.

## User experience

The popup separates the current comparison from selecting a different target.
The current state is shown first; Branch/Commit search is the selection state.

```text
┌─ BASE BRANCH ─────────────────────────────────────┐
│ origin/main · Default                             │
│ Comparing from [ Common commit @ xxxxx ▾ ]        │
└───────────────────────────────────────────────────┘

┌─ BASE BRANCH ─────────────────────────────────────┐
│ origin/main · Default                             │
│ Comparing from [ Branch tip @ yyyyy ▾ ]           │
└───────────────────────────────────────────────────┘

┌─ BASE BRANCH ─────────────────────────────────────┐
│ journey-stack-base                                │
│ Comparing from [ Common commit @ xxxxx ▾ ]        │
└───────────────────────────────────────────────────┘
```

Exact commits show `BASE COMMIT` and one commit hash without a comparison-basis
selector. The popup does not show movement history, `Review starts from`,
`Latest commit shared with`, or duplicate target/base hashes.

The current-state block uses the existing Agent Studio theme tokens. Target
selection uses the existing Popover, ToggleGroup, Input/Combobox, Button, and
DropdownMenu radio primitives with clear spacing and immediate input focus.

## Comparison behavior

- Moving symbolic targets persist `basis: commonCommit | branchTip` in the
  existing Bridge pane intent in `core.sqlite`.
- Branch selection defaults to `commonCommit`.
- `commonCommit` compares the worktree from the unique shared commit.
- `branchTip` compares the worktree directly from the selected target revision.
- Exact commit selection is basis-free and compares directly from that commit.
- One correlated `agentstudio-git` read resolves the reviewed HEAD, selected
  target, effective base, and worktree diff. No separate resolve-plus-diff race
  is introduced.
- Immutable origin reports `baseRole: commonCommit | selectedTarget` and
  `baseOID`; the UI presents `selectedTarget` as `Branch tip` only for moving
  branch/ref targets.

No new database, service, cache, watcher, IPC channel, or security system is
part of this delta.

## Proof

- Browser tests cover the current-state hierarchy, default marker, custom
  branch, exact commit, focus, spacing, and both basis selections.
- The Swift development server plus Vite proves the production Core/SQLite/Git
  path during iteration.
- The actual Agent Studio app is the final visual and interaction check.
