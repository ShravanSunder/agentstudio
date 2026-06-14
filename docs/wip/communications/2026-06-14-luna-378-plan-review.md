# LUNA-378 Plan Review

## Scope

Reviewed `docs/plans/2026-06-14-luna-378-git-cli-data-plane-migration.md` against the live worktree, PR #165 merge state, the app's pinned `agentstudio-git` revision, and the adjacent SDK checkout used only for source inspection.

The review stayed read-only against product code. Only the plan artifact was edited.

## Verdict

Ready for implementation after accepted plan revisions.

The original draft had the right lane split, but it left too many implementation-time decisions unresolved. The revised plan now locks the decisions needed for one PR:

- status projection hard-cuts to an app-owned AgentStudioGit provider after CLI-vs-SDK parity tests.
- status mapping preserves projector/eventbus behavior, including `.awaitingResolution`, unborn heads, credentialed-origin hardening, and partial-failure degraded snapshots.
- the SDK-backed status provider must preserve off-actor execution.
- RepoScanner validation migrates behind AgentStudioGit; SDK capability and package-pin updates are in scope if needed for submodule/superproject parity.
- watched-folder scanning uses an explicit async validation boundary instead of blocking on async SDK APIs.
- `WorktrunkService.discoverWithGit` is classified as Worktrunk workflow discovery and is left in place unless replacement is deliberately proven.
- production process scans now match Swift call-site syntax rather than only prose-like command strings.
- Bridge vocabulary is guarded by an SDK-source negative scan, not a broad noisy mixed scan.

## Accepted Findings

### Blockers resolved

1. RepoScanner could not remain a fuzzy "SDK gap or shell exception" item. The plan now requires SDK capability plus app pin updates in the same PR unless the user explicitly approves a temporary shell exception.
2. The status provider path needed an explicit off-actor/libgit2 execution contract. The plan now requires `@concurrent nonisolated` or equivalent proof.
3. The source-scan gate missed real Swift process call sites such as `command: "git"`. The plan now uses production-only scans for Git, `wt`, `gh`, zmx/process infrastructure, and a broad test/docs scan.
4. Worktrunk `git worktree list --porcelain` was mislabeled fallback-only. The plan now states it is live workflow discovery and treats replacement as optional, deliberate scope expansion.

### Important issues resolved

- Added `.awaitingResolution` and origin retry behavior to status mapping/proof.
- Added unborn/no-commit parity coverage.
- Added partial-failure semantics for shortstat/origin failures.
- Added credentialed HTTP(S) remote redaction as intentional hardening only with tests.
- Added SDK proof gates when adjacent `agentstudio-git` changes.
- Replaced ambiguous E2E language with integration proof unless an opt-in E2E gate is explicitly run.
- Required async scanner-boundary tests, not just stubbed topology tests.
- Required Worktrunk parsing/reconciliation tests if discovery replacement is attempted.
- Added a security context with assets, trust boundaries, invariants, and proof.

## Implementation Handoff

Start implementation from the revised plan. Do not re-split LUNA-378 into multiple PRs. Use the recommended slice order:

1. Inventory/source scans.
2. Status parity tests.
3. AgentStudioGit status provider.
4. Runtime default switch and eventbus proof.
5. RepoScanner provider plus SDK API/pin update if required.
6. Worktrunk classification proof, or deliberate replacement with parity tests.
7. Boundary scans, lint, focused tests, and full test when feasible.
