# LUNA-349 Test Value Plan (Unit + Integration)

## Purpose

Define high-value tests for the app-wide filesystem funnel and non-terminal runtime conformance work.  
This plan prioritizes regression detection and deterministic behavior over raw coverage.

## Value Rubric

A test is considered high-value only if it:

1. Protects a real regression mode called out in architecture/contracts.
2. Validates an observable invariant (not implementation details).
3. Uses deterministic assertions with low flake risk.
4. Uses minimal mocking at integration boundaries.

## Coverage Matrix

### Unit Tests (Component Invariants)

- `FilesystemActor`: deepest-root ownership routing, dedupe, bounded batch emission, deterministic path ordering.
- `PaneFilesystemProjectionStore`: `worktreeId` + `cwd` subtree filtering, nil-cwd fallback behavior, monotonic `batchSeq`.
- `WorkspaceGitStatusStore`: merge behavior for local git summaries + independent remote counts.
- `BridgeRuntime` / `WebviewRuntime` / `SwiftPaneRuntime`: lifecycle guards, command routing, replay buffer behavior.

### Integration Tests (Cross-Component Flows)

- Workspace root registration/activity -> `FilesystemActor` -> `PaneCoordinator` ingestion -> projection stores.
- Filesystem event -> local git summary update -> sidebar branch status rendering from centralized store.
- Non-terminal pane creation -> runtime registration -> runtime command dispatch -> runtime ack/event path.

### Non-Functional Reliability Tests

- Burst handling: very large change sets split into bounded payloads with stable ordering.
- Lifecycle cleanup: stream/task cancellation and continuation finish on shutdown.
- Priority behavior: active-in-app roots processed ahead of sidebar-only roots.

## Gap Checklist

- [x] Add/confirm a test for bounded batch splitting + deterministic ordering in `FilesystemActorTests`.
- [x] Add/confirm a test for nil-cwd projection fallback vs scoped subtree filtering in `PaneFilesystemProjectionStoreTests`.
- [x] Add/confirm an integration assertion that sidebar local dirty/branch state comes from centralized snapshot ingestion.
- [x] Add/confirm an integration assertion for active-in-app priority behavior under mixed root activity.
- [x] Add a real git-backed integration test under `tmp/` for local status summaries (`FilesystemActorShellGitIntegrationTests`).
- [x] Add a serialized E2E flow test for actor -> coordinator -> projection/git stores (`FilesystemSourceE2ETests`).

## Verification Gate

Run after any new/updated tests:

1. `mise run lint`
2. `mise run test`

Both must pass with exit code `0`.
