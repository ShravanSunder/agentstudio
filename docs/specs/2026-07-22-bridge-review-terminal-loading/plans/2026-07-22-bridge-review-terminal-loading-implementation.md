# Bridge Review Terminal Loading Implementation Plan

Date: 2026-07-22

Source: `docs/specs/2026-07-22-bridge-review-terminal-loading/bridge-review-terminal-loading.md`

## Goal

Make Review terminate as content, “No changes to review,” or the existing
unavailable shell for the four observed failures, without adding a new owner,
protocol, retry system, or failure cache.

## Scope Guard

- Reuse existing atoms, controller, publication coordinator, metadata stream,
  reset operation, worker state, and fallback shells.
- Do not add an actor, EventBus route, Browser store, protocol message,
  scheduler, retry loop, or late-subscriber failure memory.
- Use existing generation and admission checks to reject stale work.
- Add tests only to existing suites and fixtures.

## Serial Execution

These changes are serial because the Swift slices share Review models and
controller behavior. Parallel edits would add coordination cost without making
this small fix faster.

1. Baseline selection
   - Add failing opener tests for cached `master` and absent enrichment.
   - Select the main-worktree cached branch when usable; otherwise persist
     `.ref(name: "HEAD")`.
   - Keep detached/empty cache values from becoming baselines.

2. Gitlink and Git error boundary
   - Add failing adapter/package tests for mode `160000` on each content role.
   - Preserve `oldMode`/`newMode`, omit handles and locators only for gitlink
     roles, and keep the metadata item.
   - Map shared-capture dependency errors and raw `locked`/`unsupported` prose
     to existing scrubbed `BridgeProviderFailure` cases.
   - Classify exact revision-resolution not-found as the existing typed
     unavailable endpoint so only `.ref(name: "HEAD")` retries once.

3. Existing failure reset and zero-change presentation
   - Add a failing controller/metadata test proving a current initial failure
     resets the current Review subscription without touching File.
   - Allow fresh Review intake to retry native `.error` state.
   - Add failing BridgeWeb tests separating awaiting metadata from a ready
     zero-item source and asserting “No changes to review.”
   - Reuse the existing strict `metadataUnavailable` failed patch.

4. Verification
   - Run focused Swift tests for the three existing suites.
   - Run the focused BridgeWeb unit and browser shell tests.
   - Run BridgeWeb check, `mise run lint`, and the relevant broad Swift test
     gate.
   - Inspect the final diff for any new authority or unrelated refactor.

## Compact Proof Line

RED/GREEN focused tests must prove cached/non-`main` baseline selection, exact
HEAD fallback, role-specific gitlink omission, scrubbed shared-capture failure,
current Review reset, retry after `.error`, and the visible zero-change copy.
Existing refresh-retention tests must remain green. A debug-app check against
`agent-vm`, `ai-dev-skills`, and a clean repository is the final product proof.

## Split Trigger

Stop and return to design only if a focused test proves the existing reset or
fresh-intake path cannot express the required behavior without stored failure
state or a new transport contract.
