# PR1 Sidebar Correctness And Performance Checklist

Date: 2026-08-28
Branch: `fix/demand-admission-regression`
Current checkpoint: `05daa220d`
Status: not PR-ready

## Product Contract

Every applicable worktree row retains and displays the latest accepted facts:

- actual checked-out branch, or `detached HEAD` when that is the accepted fact;
- file-change chip facts, including tracked and untracked changes;
- ahead, behind, or diverged sync facts;
- accepted PR/check facts;
- the refresh control.

`Locally inactive` is a repository-level freshness annotation. It may suppress repeated automatic local, remote-reference, and Forge work. It must not erase or replace cached branch or chip facts. Cached facts stay visible while refresh is running. Loading is visible only for a real active request and terminates when that request settles.

When an attended sidebar worktree has no accepted local-Git baseline, one bounded local status read is required to make the sidebar useful. After that baseline settles, locally inactive worktrees receive no recurring automatic local deadline. Search, grouping, scrolling, and rendering never create source demand. Application-open recency is not repository-local activity and has no authority to classify or suppress repository facts.

PR1 uses the existing `RepositoryLocalActivityAtom`, store, and projector. It does not add replay. Persisted activity may be loaded for recovery, but a new process does not treat pre-restart continuous coverage as current authority until the existing live checkpoint restarts coverage. Until then the repository is unknown and follows ordinary bounded correctness admission. PR2 may later recover downtime history through FSEvents replay.

## Hard Priority Queue

- [x] Add red classifier/store tests proving application-open recency has no authority, restored coverage is unknown until the first live checkpoint, trustworthy local activity inside sixty days is warm, and trustworthy continuous negative coverage beyond sixty days is locally inactive.
- [x] Add a red integration test for an unknown attended repository with no cached baseline; it must receive bounded correctness facts instead of being falsely suppressed.
- [x] Prove the baseline publishes the actual branch plus dirty/file and ahead/behind facts into `RepoCacheAtom`.
- [x] Add a red Repo Explorer materialization test proving locally inactive rows retain cached branch, file, ahead/behind, and PR chips with no empty replacement row.
- [x] Cut demand and Repo Explorer classification over from application-open recency to the existing repository-local activity atom without adding replay machinery.
- [x] Fix local-Git admission so unknown/missing attended baselines remain bounded correctness work while truly inactive recurring deadlines remain suppressed.
- [x] Keep unknown-hydration local correctness eligibility while deferring automatic Remote/Forge demand to authoritative activity or open worktrees.
- [x] Remove locally-inactive presentation suppression from worktree and pane/tab projections while preserving the repository memorychip annotation.
- [x] Prove cached facts remain visible throughout explicit refresh and loading terminates.
- [x] Freeze the exact tracked row's native height through root/child menu updates, then reconcile height and scroll anchor after final close.
- [x] Prevent FSEvent activity-barrier flush from racing native stream retirement during the loaded startup baseline.
- [x] Preserve canonical topology membership through source assertion; bulk reconciliation no longer re-probes and silently unregisters owned worktrees.
- [x] Keep repository stable-key enrichment metadata-only; it no longer unregisters and re-registers unchanged filesystem roots or erases their pending Git baseline.
- [x] Rerun focused Git-demand, cache-convergence, projection, materialization, row-height, and mounted-row tests.
- [ ] Relaunch the same `lbim` data root without resetting watch folders, tabs, panes, or beta/production state.
- [ ] Capture PID-bound visual proof for By Repo, By Pane, and By Tab showing real branches and cached chips; prove search and scrolling do not collapse, clip, overlap, or move rows.
- [ ] Populate or verify the complete `open-source` and `project-dev` roots with exactly five tabs, twenty pane models, and zero debug-owned PTYs.
- [ ] Run exact-`lbim` process CPU populations: settled idle p99 below 10%; search/clear, grouping, hide/show, and tab switching p95 below 20% (release ceiling below 25% only where the owner explicitly accepts it).
- [ ] Diagnose and fix only marker-correlated PR1 hotspots; do not resume PR2 FSEvents replay work.
- [ ] Run `mise run format`, `mise run lint`, `mise run test`, `git diff --check`, fresh native proof, independent implementation review, and PR checks.

## Current Evidence

- Live PID-bound `lbim` proof showed widespread missing branch lines and missing cached chips.
- `RepoExplorerProjectionWorker` and `RepositoryFactDemandCoordinator` currently classify from application-open recency; missing rows are falsely treated as confirmed local inactivity.
- Materialization sets `showsRepositoryFactStatus` false for locally inactive worktree rows, contradicting the confirmed cached-facts UX.
- `GitWorkingDirectoryProjector.setRepositoryFactAttention` installs `warmAutomaticWorktreeIds` as the automatic-eligibility set before visibility admission; cold attended worktrees are filtered out even when no accepted baseline exists.
- Existing demand integration coverage proves warm facts survive later inactivity. It does not prove a cold, locally inactive, attended worktree receives its first baseline.
- Existing presentation tests explicitly encode cold status suppression; those expectations conflict with the confirmed product contract and must be replaced, not preserved.
- `95289e288` correctly stops treating absent PR facts as permanent loading and removes fabricated `Unknown branch`, but it exposed the missing-baseline defect and is not sufficient by itself.
- Fresh marker `debug-observability-lbim-1787955213-90463` proved 146 warm worktrees created baseline debt, then 145 intents disappeared without running Git because `FilesystemGitPipeline.assertTopology` re-probed and filtered canonical membership. The 146-worktree ownership integration now proves assertion performs zero secondary discovery calls while direct candidate registration still rejects certain non-repositories.
- Fresh marker `debug-observability-lbim-1787956797-50268` isolated the remaining identical collapse after the assertion-owner fix: stable-key enrichment alone forced 146 filesystem unregister/register cycles. The focused lifecycle test now proves the stable-key map updates while the existing stream registration remains unchanged.
- `c24be9beb` separates unknown activity from automatic remote demand: pending/unavailable hydration still warms local Git for correctness, but Remote/Forge receives only open worktrees until activity is authoritative. Coordinator coverage passes 8/8.
- `dc9d38b3a` replaces the insufficient stable-ID workaround with behavioral geometry ownership: the RED proof reproduced 63-point content inside a prematurely shortened 44-point native row; 28/28 native table tests and 27/27 worktree-row tests pass.
- `0e9a6f29f` separates one required missing-cache baseline from recurring local-Git cadence. Unknown attended worktrees receive one correctness read; only open/active or authoritatively warm worktrees retain automatic deadlines. Coordinator/pacing tests pass 11/11 and demand integration passes 2/2.
- `05daa220d` raises the bounded FSEvent ingress capacity from 64 to 512. The real-size RED/green test holds one filesystem plus one activity batch for 148 worktrees without manufactured overflow; the complete FSEvent stream suite passes 29/29.
- Active-root probes also exposed shared-parent UserDropped/KernelDropped fanout. The canonical design currently requires immediate fail-closed recovery; changing it to fingerprint-recovered Git currentness while activity becomes Unknown is a separate design amendment, not a silent PR1 implementation change.
- `60426e83c` process-isolates source-declared large suites that retain MainActor, OTLP/NIO, AppKit, or real FSEvents process-global runtime state. The parallel and nonparallel large lanes both exclude the same exact suite set and run each excluded suite through a fresh Swift Testing helper process.
- The periodic Git integration fixture now settles visibility admission before registration, derives the next provider call count dynamically, and advances the injected clock to the actual scheduler deadline. The focused leaf passed 1/1 and the complete `FilesystemGitPipelineIntegrationTests` suite passed 7/7.
- The Git enrichment integration fixture now drives the existing cache-apply clock explicitly and waits for stable Forge projection plus an ordered cache-consumer barrier. `GitEnrichmentEventPipelineIntegrationTests` passed 2/2 without wall-clock sleeps.
- `SWIFT_TEST_SKIP_PREBUILD=1 mise run test:swift:large` passed the broad 359-test/56-suite inventory, the 5-test PaneAgent owner, and every isolated process-global suite. `SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_PARALLEL=0 mise run test:swift:large` passed the same topology through the fallback path. `mise run format`, `mise run lint`, and `git diff --check` passed before the checkpoint commit; the final aggregate gate remains open.
- Final exact-HEAD aggregate `mise run test` at `b56dd54e5` completed successfully after the isolated topology suite passed 7/7: BridgeWeb unit 1,764, integration 19, browser 211 passed/5 skipped, E2E 4; Swift fast/isolated/large, WebKit serialized, and E2E serialized all passed (exit 0, 429s).

## Non-Goals

- Do not restore `Unknown branch`.
- Do not hide facts to make inactive rows compact.
- Do not trigger Git from search, grouping, scrolling, viewport changes, or rendering.
- Do not resume the PR2 restart-safe FSEvents replay design on this branch.
- Do not reset the `lbim` database or touch beta/production.
- Do not weaken CPU, observability, test, lint, or native proof gates.

## PR1 Release Wrap-Up

PR1 is ready to open or update only after every hard-priority row above is complete and the following release packet exists:

- [ ] One final requirements-to-proof matrix covers branch visibility, cached chips, inactive annotation, refresh behavior, all three grouping modes, search, scrolling, focus, row geometry, demand invariance, and CPU targets.
- [ ] `mise run format`, `mise run lint`, and `mise run test` pass on the exact final HEAD with exit code 0.
- [ ] The preserved `lbim` app is rebuilt from that exact HEAD and PID-bound captures prove By Repo, By Pane, and By Tab with real branches and cached file/ahead/behind chips.
- [ ] The exact debug PID passes the agreed settled-idle and ordinary-action CPU populations with complete watched roots, five tabs, twenty pane models, and zero PTYs.
- [ ] Fresh marker-scoped Victoria evidence agrees with the exact PID samples and shows no admission, debounce, projection, Forge, Git, filesystem, row-height, focus, or rendering loop.
- [ ] An independent implementation review finds no blocking correctness, UX, architecture, performance, or proof defect; accepted findings are remediated and re-proven.
- [ ] The branch is pushed, the PR description contains the proof matrix and exact commands, and GitHub checks, comments, review threads, and mergeability are all green.
- [ ] A beta release is proposed only from merged `main` through the repository tag-driven release flow; PR1 work never tags or releases directly from this branch.
