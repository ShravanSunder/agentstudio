# Filesystem Watching: Swift 6.2 Concurrency Hygiene + Pipeline Tuning

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

The FSEvents → FilesystemActor → git pipeline is structurally sound (C callback
bridging, `@concurrent` isolation of blocking I/O, and shutdown draining were
all audited and verified correct), but three verified deviations from the
repo's own Swift 6.2 standards remain:

1. **The FSEvents ingress stream has no buffering policy.** Every other stream
   in the runtime system declares one (`.bufferingNewest(256)` on EventBus,
   `.bufferingNewest(128)` on PaneRuntimeEventChannel); the ingress stream —
   the one fed directly by event storms during rebases/installs — is
   unbounded. CLAUDE.md: "explicit buffering policy, always cancel on
   shutdown."
2. **`.gitignore` reload does synchronous file I/O on the actor executor.**
   `FilesystemPathFilter.load()` calls `String(contentsOf:)` from inside
   `FilesystemActor.ingestRawPaths`, stalling the drain loop on slow disks.
   SE-0461: blocking I/O called from an actor needs `@concurrent nonisolated`.
3. **`GitWorkingDirectoryProjector` defaults `coalescingWindow` to `.zero`.**
   Production wiring passes 200ms via `FilesystemGitPipeline`, but any future
   call site (or test) using the default gets one `git status` subprocess per
   filesystem event — a silent footgun.

## Current Evidence

- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift:57`
  — `AsyncStream.makeStream(of: FSEventBatch.self)` with no
  `bufferingPolicy` (defaults to unbounded).
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift:255`
  — `root.pathFilter = FilesystemPathFilter.load(forRootPath: root.rootPath)`
  executes on the actor;
  `FilesystemPathFilter.swift:19` — `static func load(...)` does synchronous
  file reads.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift:42`
  — `coalescingWindow: Duration = .zero`;
  `Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift:44` passes
  the real 200ms value.
- Verified correct during audit (no action): C callback context lifetime
  (`DarwinFSEventStreamClient.swift:10-44`, passRetained/teardown-release with
  weak client), `FilesystemActor.scanFolder` `@concurrent` isolation
  (`FilesystemActor.swift:637`), `GitWorkingTreeStatusProvider.computeStatus`
  `@concurrent` subprocess isolation, shutdown task draining
  (`FilesystemActor.swift:199-220`).

## Non-Goals

- No change to the topology accumulator pattern, event taxonomy, or bus
  contracts (audited healthy).
- FSEventStream `defaultLatency` (0.1s) tuning is deferred: it sits behind a
  500ms debounce, so changes are unmeasurable without a profiling harness;
  revisit only with profile data.
- No configurability knobs for debounce windows (constructor injection already
  serves tests).

## Scope

Write surfaces:
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift`
  — explicit buffering policy.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemPathFilter.swift`
  — `@concurrent nonisolated` async load.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift`
  — await the async load at the `.gitignore`-change call site.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`
  — remove the `.zero` default (require explicit window) or default to the
  production value.
- Tests: `Tests/AgentStudioTests/.../FilesystemActorTests.swift`, projector
  tests.

Read-only context:
- `Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift` —
  buffering-policy precedent (256).
- `docs/architecture/pane_runtime_eventbus_design.md` — SE-0461 rules table.

## Task Sequence

1. **Buffering policy.** Set `.bufferingNewest(256)` on the FSEvents ingress
   stream (matching EventBus precedent). Drop-tolerance rationale — state it
   precisely, not loosely: dropped batches are tolerable because per-path
   facts are recomputed from disk on the next event for that root (events are
   triggers, not accumulated deltas) and the git projector has a periodic
   refresh; the 300s fallback rescan covers watched-folder discovery
   specifically. Verification step: read `startFallbackRescan` and confirm
   its scope (watched folders vs all registered roots) before writing the
   comment — do not claim "recovers anything missed" unless the code shows
   it. Add the verified rationale as the code comment.
2. **Async path-filter load.** Mark `FilesystemPathFilter.load` as
   `@concurrent nonisolated` async; update the `FilesystemActor` call site to
   `await`. Confirm no actor-state mutation occurs across the new suspension
   point (re-read `ingestRawPaths` for reentrancy: capture `root` state before
   the await, validate the root still exists after).
3. **Projector default.** Pre-flight: `grep -rn
   "GitWorkingDirectoryProjector(" --include="*.swift"` to confirm the full
   call-site set (expected: pipeline + tests only). Then make
   `coalescingWindow` a required parameter (hard cutover — repo convention)
   and update every call site to pass values explicitly.
4. **Tests.** (a) Storm test: yield 10k synthetic batches with no consumer,
   assert bounded memory/no hang via the buffering policy; (b) gitignore
   reload test with a slow-filter fake (gated on a test-controlled
   continuation, no sleeps) proving the drain loop continues; (b2) reentrancy
   test: unregister the root while its filter load is suspended — assert no
   crash and the loaded filter is discarded, not applied to a dead root; (c)
   projector test asserting one `git status` per coalescing window under
   rapid changesets (using injected clock).
5. **Docs.** Add the buffering-policy table (who buffers what, and why) to
   `docs/architecture/pane_runtime_eventbus_design.md`.

## Proof Gates

- Red/green: new tests above fail before the change where applicable (the
  projector-window test must fail against a `.zero` window).
- Focused validation: `mise run test -- --filter "FilesystemActor"`,
  `mise run test -- --filter "GitWorkingDirectoryProjector"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: in a watched repo, run a churny operation (`git rebase` over many
  commits) and confirm sidebar enrichment stays live and CPU stays bounded
  (Activity Monitor spot check).

## Stop Conditions

- Stop if `ingestRawPaths` holds invariants across the new await that cannot
  be revalidated cheaply (actor reentrancy hazard) — report and consider
  loading the filter content via a detached read + message-back instead.
- Stop if making `coalescingWindow` required breaks call sites outside the
  audited two — enumerate them and report before widening scope.

## Risks

- `.bufferingNewest` can drop oldest batches under extreme storms: mitigated
  by the periodic fallback rescan (300s) and the debounce-coalesced semantics
  (per-path facts are recomputed from disk, not accumulated deltas). State
  this in the code comment.
- Reentrancy across the new await in task 2 — the explicit revalidation step
  is the mitigation; the test in task 4b proves it.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-filesystem-watch-swift62-hygiene.md
Start by validating the plan against current git state before editing files.
Tasks 1, 2, 3 are independent slices; task 4 follows its corresponding slice.
Parent owns integration and final proof (mise run test, mise run lint).
```
