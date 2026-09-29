# Typed-fact test harness — Requirements

Status: owner-accepted direction 2026-09-28; revised after advisor round 6 · 2026-09-28

Artifacts: [Requirements](2026-09-28-typed-fact-test-harness-requirements.md) · [Specification](2026-09-28-typed-fact-test-harness.md) · [Program Design](2026-09-28-typed-fact-test-harness-program-design.md)

## Requirements

| Id | Need | Authority |
|---|---|---|
| U1 | An async test's verdict comes from program logic, never from machine speed. Within the scope a test asserts (one owner operation, lifetime or generation), the order of facts is contractual and the same on every run. Independent operations aren't ordered relative to each other, and the harness exposes an unexpected order instead of hiding it. | Owner 2026-09-27: "tests should be deterministic"; CLAUDE.md No Wall-Clock Tests |
| U2 | Tests don't wait for things to settle. They observe typed facts that owners emit at steps, in order. A fact that doesn't arrive is a failure. | Owner 2026-09-27: "typed facts that should have observers at steps to make sure they arrive, if not it failed" |
| U3 | One generic, reusable, repeatable harness, used by every async test. | Owner 2026-09-27 |
| U4 | `waitUntilIdle` is not used in tests. | Owner 2026-09-28: "banned" |
| U5 | Test observation doesn't turn internal steps into app-wide production contracts. The app `EventBus` carries only real runtime facts, and a new event type needs owner approval. | CLAUDE.md Bus rules; advisor round 4 |
| U6 | A stuck test names the fact it was waiting for, even when the runner has to kill the process. | Advisor round 4; the existing `HeldStepEventLog` contract |

## Non-goals

- Rewriting every async test in one change: the rollout goes one owner at a time.
- Changing owners' production behavior beyond emitting typed facts. Some owners also need explicit operation correlation and new closing facts on paths that report nothing today; that's in scope, and each owner's fact list goes to the owner.
- Removing production `waitUntilIdle` APIs that production code itself calls (e.g. `RepositoryFactDemandCoordinator`).

## Current reality (origin/main 471ab85a3)

| Pattern in tests | Uses | Files |
|---|---|---|
| `assertEventuallyMain` | 108 | 30 |
| `waitUntilIdle` | 81 | 12 |
| `assertEventuallyAsync` | 78 | 27 |
| `RecordingSubscriber` (lossy by default; finds the first match in history) | 41 | 12 |
| `HeldStep` (kept) | 213 | 49 |
| `TestPushClock` (kept) | 197 | 56 |
