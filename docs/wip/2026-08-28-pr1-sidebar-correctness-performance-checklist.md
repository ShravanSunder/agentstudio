# PR1 Sidebar Correctness And Performance Checklist

Date: 2026-08-28
Branch: `fix/demand-admission-regression`
Current implementation checkpoint: `bbdbf2b12` plus reviewed correctness remediation pending checkpoint
Status: wrap-up in progress; reviewed correction green, exact-final aggregate/review/publication open

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
- [x] Relaunch the same `lbim` data root without resetting watch folders, tabs, panes, or beta/production state.
- [x] Validate the preserved `lbim` sidebar in By Repo, By Pane, and By Tab with real branches and cached chips; owner accepted the live sidebar behavior after search, scrolling, grouping, and tab use.
- [x] Keep the extended five-tab/twenty-pane, zero-PTY fixture and reproducible PID-bound capture packet in PR2; it is not claimed as PR1 proof.
- [x] Keep exact-`lbim` idle p99 below 10% and ordinary-action p95 below 20% populations in PR2; PR1 does not claim those targets were proven.
- [x] Stop PR1 product changes after the accepted stable sidebar; marker-correlated residual tuning and FSEvents replay remain PR2 work.
- [x] Prevent Agent Studio-owned canonical-ref promotion from minting local activity while retaining Git invalidation; conservative live attribution restarts only the affected repository's coverage.
- [x] Keep untouched persisted repositories unknown after restart until each repository receives a current-session checkpoint.
- [x] Make repository Refresh preserve launcher/application-open recency.
- [x] Reconcile the Program Design and exact `agentstudio-git` pin with PR1's conservative live self-event boundary; replay and durable exact provenance remain PR2.
- [ ] Complete the exact-HEAD aggregate after the topology convergence test correction.
- [ ] Complete the independent implementation review, push, and PR checks.

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
- `a1234ae2b` keeps coverage-maturing unknown repositories on local background cadence without granting visible-tier, Remote, or Forge demand. The combined classifier, demand, projector, OTLP, strict-verifier, and real Git-pipeline run passed 52/52.
- `92ce38c13` exposes the production unknown/background-only proof seam and makes the strict verifier reject unknown-to-visible, unknown-to-Remote, unknown-to-Forge, or incomplete background projection. The settlement verifier passed 17/17 after formatting; `mise run lint` passed with 0 SwiftLint violations, architecture lint OK, and release-script checks green.
- `9c6f97b47` closes two independently reviewed gaps: sidebar visibility can no longer prompt a background-only missing baseline ahead of its registration phase, and the strict fixture requires positive unknown repository/worktree membership rather than permitting a vacuous zero-unknown proof.
- `07458d47d` removes the contradictory legacy guard that required `.unclassified == 0` even though the classifier intentionally represents every unknown repository as `.unclassified`; mixed warm/unknown/inactive fixture admission is now reachable.
- `236aabe44` records the exact applied Git/Remote/Forge demand sets at the pipeline/source owners, binds the strict verifier to those applied intersections, requires every registered background-only unknown key to own a finite deadline or classified in-flight work, exports the new numeric fields through the OTLP taxonomy, and adds exact cutoff plus background promotion/contraction transition proof. The final affected set passed 94/94 across 12 suites; `mise run format`, `mise run lint`, architecture lint, release checks, and `git diff --check` passed before the commit.
- The third independent implementation review at `07458d47d` found three proof gaps, all remediated by `236aabe44`. Its coverage is therefore stale for the corrected HEAD. The workflow's three automatic remediation passes are exhausted; a fourth fresh review requires explicit owner authorization.
- Exact Debug `lbim` PID `16674` relaunched against the preserved data root and showed stable By Repo branches, chips, and content-driven 44/63/70-point rows. The real root context menu remained open over chip-bearing rows. The root-plus-child menu geometry regression suite passed 4/4; live child-hover proof remains open.
- The final aggregate gate is externally blocked after a WindowServer restart. BridgeWeb headless Chrome aborted before executing any browser test on two consecutive runs. The Swift fast process then reproduced system pasteboard failure: every AppKit pasteboard-backed drag decode returned `nil`, followed by a Swift Testing signal-6 abort while rendering an invalid `NSPasteboard`. LaunchServices subsequently rejected the freshly built Debug bundle with `kLSNoExecutableErr`, and the direct-executable fallback exited immediately. No product, test-topology, or proof-gate workaround was applied.
- Exact-final proof retry at `a4100f38e` reproduced the same host boundary. `mise run test` passed format/lint/architecture/release checks and BridgeWeb unit 1,764/1,764, then Chrome exited `SIGABRT` before browser tests. A separate `mise run test:swift` executed the broad fast inventory until `DraggableTabBarWindowDragTests` received `.none` from AppKit and Swift Testing aborted on a null `NSPasteboard`.
- The standard debug launcher rebuilt and signed only `Agent Studio Debug lbim` against the preserved `~/.agentstudio-db/lbim` root, marker `debug-observability-lbim-1788056360-19573`. LaunchServices returned `kLSNoExecutableErr`; the built-in direct-executable fallback reported PID `20413` and then exited. Candidate validation reported it absent, and `mise run verify-debug-observability` confirmed the marker PID was not running. No native or CPU evidence was claimed.
- Legacy quiescence vectors now carry the strict positive unknown/background ownership fields added by `236aabe44`, so they reach their intended ready-debt and settlement assertions instead of failing fixture admission first. `SidebarPerformanceWorkloadScriptTests` plus `SidebarPerformanceWorkloadSettlementScriptTests` passed 41/41 before the host failure; the exact source then passed `mise run format`, `mise run lint` with 0 SwiftLint violations and architecture/release checks green, and `git diff --check`.
- The post-restart composite-continuity suite did execute: all thirteen tests and sixteen argument cases started, fourteen failed immediately because `prepare()` or `prepareAuthority()` returned `nil`, and two then waited forever for a synthetic shared flush that could no longer occur. The fixture now proves its local FSEvent participant exists before those two exact waits. The rebuilt suite exits in 0.018 seconds with sixteen explicit prerequisite/preparation failures and leaves no orphan owning `.build-agent-1`; no timeout, sleep, product behavior, or proof gate was weakened.
- One exact composite leaf reproduced `prepareAuthority() == nil` in three milliseconds, and the real native shared-item integration independently failed to receive its local-stream sentinel. The entire filesystem/composite lane has no source or test diff from last-green aggregate `b56dd54e5` to current HEAD. The macOS FSEvents service query also returns error 141 (`Reentrancy avoided`) after the restart. This is current host evidence, not authority to patch unchanged product continuity code.
- The exact current Debug lbim bundle rebuilt and signed against preserved `~/.agentstudio-db/lbim`, marker `debug-observability-lbim-1788058509-49131`. LaunchServices again returned `kLSNoExecutableErr`; direct fallback PID `52299` exited before exact candidate validation. No native, CPU, or fresh marker proof was claimed.
- After the full macOS reboot, native FSEvents continuity recovered (focused leaf 1/1), the shared OTLP stack restarted, and exact Debug lbim relaunched through LaunchServices as PID `15789` with preserved data and marker `debug-observability-lbim-1788083142-12324`; exact candidate validation and `verify-debug-observability` passed.
- The first recovered aggregate attempt passed lint, architecture, release, BridgeWeb unit 1,764/1,764, integration 19/19, and browser 211 passed/5 skipped, then exposed one PR1-relevant flaky proof gate: the native-table pilot compared baseline and doubled scale in separate sub-millisecond time blocks. Five exact pre-fix repetitions passed 3/5 and failed 2/5 even though every absolute p95 remained below 0.85 ms versus the unchanged 4 ms ceiling. The diagnostic now prepares both production-path runtimes and alternates baseline→doubled then doubled→baseline matched transactions before applying the unchanged 20% growth policy. The complete focused suite passed 7/7; five exact post-fix repetitions passed 5/5 with growth from -8.6% to +0.13%.
- Exact-final `mise run test` at `0e6c45e5e` passed with exit code 0 in 480.24 seconds: BridgeWeb unit 1,764/1,764, integration 19/19, browser 211 passed/5 skipped, E2E 4/4, and all Swift fast, isolated, large, serialized WebKit, and serialized E2E lanes completed successfully.
- The owner accepted the preserved `lbim` sidebar behavior as stable and suitable for PR1 wrap-up. Extended five-tab/twenty-pane capture, exact-process CPU populations, and deeper marker-scoped tuning are explicitly deferred to PR2 and are not represented as proven by PR1.
- The documentation-only `d6f1d6af1` aggregate reproduced one test-bound failure after 313.65 seconds: the watched-folder removal integration exhausted 200 `Task.yield()` turns in 0.002 seconds before the asynchronous scan/result/event pipeline emitted `repoRemoved`. Product source was identical to green `0e6c45e5e`. The test now uses the suite's established 1,000-turn convergence bound without adding a sleep or changing product behavior; the focused `TopologyEventPipelineIntegrationTests` suite passed 7/7 in 0.033 seconds.
- The fourth fresh implementation review at `bbdbf2b12` found four source-backed PR1 defects: the pinned in-process promotion was absent from the current-boundary prose; qualifying live `OwnEvent` ref changes minted local activity; one post-restart checkpoint published untouched persisted rows authoritative; and Refresh wrote unrelated application-open recency. The owner authorized immediate correction.
- The reviewed correction preserves the `c8dbd7ef0f344293160b8f7d72d93931328761fd` package pin, converts qualifying live process-owned ref changes into affected-repository coverage restart rather than activity, accumulates current-session authority by repository key, removes Refresh recency mutation, and reconciles the Program Design. The red run failed with five exact issues across the four affected suites; the green run passed 38/38 across five suites. Adjacent FSEvents, composite continuity, activity-projector, classifier, and demand integration coverage passed 52/52 across five suites.
- The exact package `GitStagedFetchIntegrationTests` suite passed 8/8 at the pinned `c8dbd7e` revision, including current-process attribution, atomic promotion, concurrent mutation rejection, cleanup, and abandoned-staging bounds. The complete package check reached its unrelated Bridge adapter compatibility suite and failed because that external package worktree targets a different Agent Studio checkout whose Bridge comparison DTOs have moved; no Git promotion test failed and no Bridge code was changed in PR1.
- The second exact-head aggregate exposed a separate test-clock race: the periodic Git fixture awaited a sleep, then yielded to read provider count before reading the sleep deadline, allowing cancellation to remove the deadline. The fixture now captures provider count before awaiting the exact deadline; the complete `FilesystemGitPipelineIntegrationTests` suite passes 7/7 without a wall-clock sleep.
- `mise run lint` passes after the reviewed correction with SwiftLint 0 violations, architecture lint OK, release-script verification green, and `git diff --check` clean.
- Push was not attempted after the WindowServer restart, per owner direction. The local branch remains the only publication source until the host and Git signing/network path recover.
- Active-root probes also exposed shared-parent UserDropped/KernelDropped fanout. The canonical design currently requires immediate fail-closed recovery; changing it to fingerprint-recovered Git currentness while activity becomes Unknown is a separate design amendment, not a silent PR1 implementation change.
- `60426e83c` process-isolates source-declared large suites that retain MainActor, OTLP/NIO, AppKit, or real FSEvents process-global runtime state. The parallel and nonparallel large lanes both exclude the same exact suite set and run each excluded suite through a fresh Swift Testing helper process.
- The periodic Git integration fixture now settles visibility admission before registration, derives the next provider call count dynamically, and advances the injected clock to the actual scheduler deadline. The focused leaf passed 1/1 and the complete `FilesystemGitPipelineIntegrationTests` suite passed 7/7.
- The Git enrichment integration fixture now drives the existing cache-apply clock explicitly and waits for stable Forge projection plus an ordered cache-consumer barrier. `GitEnrichmentEventPipelineIntegrationTests` passed 2/2 without wall-clock sleeps.
- `SWIFT_TEST_SKIP_PREBUILD=1 mise run test:swift:large` passed the broad 359-test/56-suite inventory, the 5-test PaneAgent owner, and every isolated process-global suite. `SWIFT_TEST_SKIP_PREBUILD=1 SWIFT_TEST_PARALLEL=0 mise run test:swift:large` passed the same topology through the fallback path. `mise run format`, `mise run lint`, and `git diff --check` passed before the checkpoint commit; the final aggregate gate remains open.
- Final exact-HEAD aggregate `mise run test` at `b56dd54e5` completed successfully after the isolated topology suite passed 7/7: BridgeWeb unit 1,764, integration 19, browser 211 passed/5 skipped, E2E 4; Swift fast/isolated/large, WebKit serialized, and E2E serialized all passed (exit 0, 429s).

## Current Requirement-To-Proof Matrix

| Requirement | Automated proof at reviewed remediation | Required native/runtime proof | Status |
| --- | --- | --- | --- |
| Actual branch or detached HEAD plus cached file/ahead/behind/PR facts | Cache, projection, materialization, refresh-lifetime, and Git-pipeline suites; final affected set 94/94 | Preserved lbim readback across By Repo/Pane/Tab | Automated green; live sidebar accepted by owner |
| Inactive annotates freshness without hiding facts | Classifier, cached-fact retention, projection, and row tests | Mixed warm/unknown/inactive headers and chips in lbim | Automated green; live sidebar accepted by owner |
| Unknown receives phased local self-heal and no visible/Remote/Forge demand | Exact cutoff/transition tests, applied pipeline/source metrics, deliberate misroute falsifier, strict self-heal ownership falsifier | Positive unknown marker with zero forbidden intersections | Automated green; marker proof open |
| Agent-owned fetch does not mint local activity | Local and shared real-ref `OwnEvent` tests; pinned staged-promotion integration 8/8 | Existing live observation boundary | Automated green; downtime/exact provenance deferred to PR2 |
| Restart authority is repository-keyed | Two-repository store restart test plus projector/classifier suites | Existing preserved-data launch | Automated green; untouched rows remain unknown |
| Refresh preserves launcher recency | AppDelegate command/admission suite | Existing command path | Automated green |
| Search/group/scroll/render create no source demand | Coordinator, pipeline, and projection demand tests | Action populations with source-call invariance | Automated green; extended native/OTLP population deferred to PR2 |
| Rows, scroll, focus, and root/child context menu remain stable | Native-table row-height/materializer/menu suites | Preserved lbim interaction | Automated green; live sidebar accepted by owner |
| Idle p99 below 10%; ordinary actions p95 below 20% | Verifier/parser/sampler contracts | Extended exact-lbim 5/20 populations | Deferred to PR2; not claimed by PR1 |
| Exact final aggregate gate | Focused 94/94, focused topology 7/7, prior full aggregate green | `mise run test` on the final test-stability checkpoint | Pending rerun |
| Independent implementation review | Fourth fresh review found four defects; remediation focused proof is green | Fresh review of final corrected HEAD | Pending |
| PR publication readiness | Local branch checkpoints and exact-final aggregate | Push, CI, comments, threads, and mergeability | Pending |

## Non-Goals

- Do not restore `Unknown branch`.
- Do not hide facts to make inactive rows compact.
- Do not trigger Git from search, grouping, scrolling, viewport changes, or rendering.
- Do not resume the PR2 restart-safe FSEvents replay design on this branch.
- Do not reset the `lbim` database or touch beta/production.
- Do not weaken CPU, observability, test, lint, or native proof gates.

## PR1 Release Wrap-Up

PR1 is ready to open or update only after every hard-priority row above is complete and the following release packet exists:

- [x] The final requirements-to-proof matrix covers branch visibility, cached chips, inactive annotation, refresh behavior, grouping modes, search, scrolling, focus, row geometry, and demand invariance; extended CPU targets are explicitly assigned to PR2.
- [ ] `mise run format`, `mise run lint`, and `mise run test` pass on the exact final test-stability checkpoint.
- [x] The preserved `lbim` app was rebuilt from `0e6c45e5e`, retained the existing data root, showed real branches and chips, and was accepted by the owner as stable.
- [x] Exact-process 5/20 CPU populations and deeper marker-scoped Victoria tuning are deferred to PR2; PR1 makes no quantitative CPU-target claim.
- [ ] An independent implementation review finds no blocking correctness, UX, architecture, performance, or proof defect; accepted findings are remediated and re-proven.
- [ ] The branch is pushed, the PR description contains the proof matrix and exact commands, and GitHub checks, comments, review threads, and mergeability are all green.
- [ ] A beta release is proposed only from merged `main` through the repository tag-driven release flow; PR1 work never tags or releases directly from this branch.
