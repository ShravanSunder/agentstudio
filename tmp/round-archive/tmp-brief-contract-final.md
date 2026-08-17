# Brief: sidebar contract validation + fix loop (persistent sidekick)

You are the persistent sidekick for the sidebar-grouping feature. This named
session keeps history: future rounds and owner feedback arrive here as
follow-up prompts, and you fold them into what you already know. Never assume
a fresh start; re-read this brief and the contract if unsure.

## Ground truth

- Worktree: /Users/shravansunder/Documents/dev/project-dev/agent-studio.sidebar-grouping
  (branch feat/sidebar-grouping-rows, draft PR #296).
- THE requirements gate: `SIDEBAR-VISUAL-CONTRACT.md` at the worktree root —
  19 mandatory items. Read it fully before touching anything. Every delivery
  must satisfy ALL items; a regression in any one fails the round no matter
  what else improved.
- Item 19 amendment (owner-decided): reload chip is TWO STATES ONLY for now —
  stale = static hollow dot, no animation; the animated "refreshing" state is
  DEFERRED until a real keyed refresh-lifecycle fact exists in the cache. Do
  not build new runtime plumbing; do not infer refresh state locally. Amend
  the contract file's item 19 text to record this deferral and commit it.
- History: tmp-brief-round3.md, tmp-brief-round5.md, tmp-brief-polish.md,
  tmp-brief-spinner.md, tmp-RESULT.md record prior rounds (superseded by the
  contract but explain intent). tmp-brief-spinner.md contains the diagnosed
  root cause for contract item 11 (sort button animation/flicker = view
  identity churn at the RepoExplorerView call site; the shared
  SidebarSortButton component is correct — fix the call site's identity, do
  not touch the shared component's animation).

## Current state

- HEAD 44023b0c7 committed the full implementation (pane activity rows,
  labeled chips, static stale dot). Two test files are still MODIFIED and
  uncommitted: RepoExplorerViewTests.swift, RepoExplorerWorktreeRowTests.swift.
  Inspect the diff, finish/repair them, get them green, commit.

## Your job this round

1. Finish the uncommitted test work; focused suites green; commit.
2. Verify EVERY contract item (1–19 as amended) against the BUILT app:
   - Gates (mise tasks ONLY): `mise run test:swift -- --filter "<suites>"` for
     focused; `SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise run test`
     for the full aggregate; `mise run lint`.
   - Visual pass: launch debug app `mise run run-debug-observability -- --detach`
     (background launch, do NOT steal foreground focus), use Peekaboo with PID
     targeting for screenshots. Capture per contract section: a dirty By Repo
     row with "● +N -M" counts, a >0 PR "⑂N" chip row, the 3-button toggle in
     each selection state (accent icon + accent TEXT label, no borders),
     pane rows showing real last-notification text (NEVER the literal
     "New terminal activity"), the empty state per mode, sort-rotation frames,
     header-vs-row icon gap parity, chip left-alignment parity. Save to
     tmp-screenshots/contract-final/. TERM the app when done.
3. Fix any violation found and re-verify — loop until ALL 19 hold in ONE build.
4. Push (updates draft PR #296). Update tmp-RESULT.md with a per-item
   checklist: item number → evidence file → pass/fail.

## Rules

- Build/test only via mise tasks; the worktree has 2 build slots of its own.
- No wall-clock sleeps in tests; no new `#if DEBUG` hooks.
- Commit early per green slice; unsigned fallback (`git commit --no-gpg-sign`)
  after two 1Password failures. Never `--no-verify`.
- Decision authority: style/mechanical calls you decide per the contract.
  Stop and record in tmp-RESULT.md ONLY for a genuine design contradiction or
  a missing data source — not for anything the contract already answers.
- Final output: the per-item pass/fail table, nothing else.
