# Bridge Viewer Product Recovery Implementation Plan

Status: accepted after the one permitted Fable plan review, one parent
remediation and one same-relationship remediation verification. Ready for
`implementation-execute-plan`.

Goal id: 2026-07-13-bridge-recovery

Recovery anchor: 38fe66aefda5df752f7f5c211de74c9d126eec3a

Planning head: df38a5fb59af4c00114eded0bb9f4fa16638bcf6

## 1. Outcome

Finish the Bridge hard cut without redoing the product recovery already
checkpointed:

- Swift owns canonical Review package and source authority.
- One pane comm worker owns accepted File/Review metadata, projection, demand,
  complete-item assembly/cache/residency, retry and reconstructable client
  state.
- File View keeps its hierarchical tree, streams and assembles the complete
  selected text file off-main, submits one complete public Pierre item, and
  remains painted through sustained deep scrolling.
- Review keeps its hierarchical fully expanded @pierre/trees navigation and one
  continuous multi-file public Pierre CodeView with search, facets, reveal,
  selection, collapse and selected/visible hydration.
- Native pane admission closes synchronously; Review A-to-B publication is
  transactional; hidden loaded panes retain state and coalesce invalidations;
  state-aware commands reuse or explicitly duplicate panes.
- Synchronous libgit2 reads run on the package blocking queue while Agent Studio
  owns worktree-keyed admission, operation classes, logical deadlines and
  physical draining custody.
- Browser, hosted WebKit, packaged LaunchServices WKWebView, immutable
  correctness/p99 workloads, quality gates, implementation review, CI and PR
  readiness are proven at the final source and artifact identity.
- Pierre remains unmodified. The terminal is PR ready and not merged.

## 2. Source Coverage And Authority

The parent read and accepted the complete 1,979-line canonical spec:

- docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md

Supporting product specifications remain normative where the canonical spec
does not supersede them:

- docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md
- docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md

Creation evidence:

- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/plan-ledger.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/native-codebase-boundary.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/web-codebase-boundary.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/validation-proof.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/security-reliability.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/vertical-slice-decomposition.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/execution-order.md
- tmp/plan-workflows/2026-07-16-bridge-native-authority-recovery/lanes/scope-and-proof-fit.md

The superseded contents of this plan file and the absent 2026-07-12 temporary
plan are broken evidence only. This file is the sole implementation-plan
authority after its capped review is accepted.

## 3. Hard Boundaries And Non-Goals

- Never modify, fork, patch, proxy or privately drive Pierre.
- Do not restore the deleted product/projection worker, main product store,
  package-first startup, resource GET carrier, page/native relay or any second
  owner.
- Do not add a permanent File size/line cap without measured failure evidence
  and explicit user reconvergence.
- Production Bridge Git uses agentstudio-git only. TypeScript CLI Git remains
  limited to Vite development and test-fixture utilities.
- Do not use browser visibility or active viewer mode as native activity truth.
- Do not create one global serial Git actor, an actor-per-worktree registry,
  UUID ordering or replacement tasks after logical timeout.
- Do not invent scheduler capacities or widen the one-unobserved-frame stream
  window before the required workloads.
- Do not add a second Vite E2E configuration or a parallel source-cell/reporter
  framework.
- Commit-comparison UX, unrelated infrastructure, release and merge are out of
  scope.
- Never weaken or delete a required proof to make a gate pass.

## 4. Achieved Checkpoints — Documentary, Not Future Tasks

Do not restart these slices:

- 0129ad2f recovered the viewer/worker cutover.
- dc7e44a9 restored fully expanded hierarchical trees and retained same-identity
  Pierre membership reconciliation.
- 098c8281 through 310b7f41 removed File prefix behavior and proved complete
  File streaming/deep-scroll paths.
- 29c37700 through 384d3cb1 established exact fulfillment and retained
  File/Review render pipelines.
- 2f333aef through 26e04f1a established the Vite provider and removed the
  rejected parallel proof framework.
- 2605671f repaired Review intake retry/acknowledgement.
- 5ac6494a checkpointed the 204-path product-stream hard cut.
- 66a7d277 and df38a5fb accepted the R67-R69 native authority spec after one
  Fable review and one remediation.

These checkpoints may satisfy final proof only when their touched surfaces
remain unchanged and their evidence is fresh enough for the claim. A later
touch reruns the smallest affected gate; it does not reimplement the slice.

## 5. Current Baseline

At planning head:

- production BridgeWeb and Swift build pass;
- BridgeWeb full unit is RED: 205/218 files passed, 1,422/1,445 tests passed,
  13 files and 23 tests failed;
- the focused 13-file rerun is RED: 105/128 passed, 23 failed;
- BridgeWeb check stops at ten files over the 1,000-line architecture cap;
- the private-Pierre static witness has one false prohibition against the
  public worker parseDiffFromFile path;
- no dedicated BridgeWeb/vitest.e2e.config.ts exists;
- no native ProductAdmissionGate, BridgeReviewPublicationCoordinator,
  BridgePaneActivityCoordinator or bounded BridgeGitReadScheduler exists;
- BridgeContentStore still combines package authority with loading/cache;
- BridgePaneProductMetadataCoordinator still changes content authority;
- pane presentation becomes ready before awaited Review publication;
- Review reload clears readable A before B succeeds;
- hidden filesystem invalidations immediately drain Review refreshes;
- Review/File commands always create a new tab;
- Agent Studio pins agentstudio-git at 397b8e1;
- package checkpoint b9e019f is locally clean and proven but not remotely
  reachable. The W3 discovery branch has since advanced to 97b73a6 with
  96aeb47 and 97b73a6, and that head is not an ancestor of b9e019f, so the
  latest W3 commits must be merge-integrated and reverified before the package
  branch can be pushed or pinned;
- no current Swift compile failure is confirmed, but the full Swift test target
  and suite are unproven; and
- the hosted WebKit support orders a background window while its product test
  requires visible document state and live animation frames.

The 23 BridgeWeb failures are bounded to:

- two stale projection-worker expectations;
- one false private-Pierre prohibition;
- two overlapping line-cap witnesses;
- three File preparation continuation fixtures;
- four Review epoch/demand fixtures;
- one File render-receipt identity mismatch;
- one File descriptor-length fixture mismatch;
- one render-snapshot fixture missing an array;
- seven unit tests assuming browser animation-frame globals; and
- one stale Vite route expectation.

Each failure is classified against the accepted contract before editing.

## 6. Accepted Architecture Freeze

Per Bridge pane:

    synchronous ProductAdmissionGate
      -> immediate close and epoch validation

    @MainActor BridgeReviewPublicationCoordinator
      -> state-only active A, optional pending B, retiring A leases
      -> synchronous package/descriptor and pane-presentation commit

    BridgeReviewContentLoaderCache actor
      -> off-main provider I/O, candidate validation/indexing, coalescing,
         cache and eviction only

    BridgePaneProductMetadataCoordinator actor
      -> subscriptions, delivery reservation, replay and task lifecycle only

    one comm worker
      -> separate File and Review stores/projections
      -> pending B delivery staging
      -> complete-item demand/cache/residency

Application scope:

    BridgePaneActivityCoordinator
      -> sole foreground/loaded-hidden/dormant/closed mint

    BridgeGitReadScheduler actor
      -> worktree-keyed admission, rank, classes and logical deadlines

Package scope:

    LibGit2BlockingReadExecutor
      -> synchronous libgit2 bodies and true-return acknowledgement

Native B commits before any worker-visible B frame. The worker holds complete B
pending until a validated commit barrier, then swaps once. Pre-commit failure
preserves A. Post-commit delivery failure leaves native B authoritative and
worker-visible A stale while B retries. Stream uninstall changes delivery only.

A loaded pane never becomes dormant in this increment. Loaded-hidden retains
bounded package/cache and both presentation positions, admits no body/prefetch/
refresh work and collapses invalidations to one dirty fact. Dormant means never
instantiated in the current app lifetime.

## 7. Execution Slices And Local Proof

Every behavior slice begins with a permanent failing witness for the expected
reason, then implements only its approved manifest, makes that witness pass,
climbs its named proof layers and commits the verified checkpoint. Behavior-
neutral movement proves parity before and after instead of inventing a RED.

### S0a — Review Runtime Structure Prerequisite

Purpose:

- split bridge-comm-worker-runtime-protocol.ts and its unit test by existing
  Review responsibilities before transactional publication edits;
- preserve behavior and public exports exactly.

Allowed writes:

- the two source/test files above and adjacent extracted Review runtime helpers.

Proof:

- focused runtime protocol tests before and after;
- BridgeWeb typecheck, product-contract typecheck, type-aware lint and format;
- architecture line-cap check for the moved files;
- no product-contract, Pierre, Swift or runtime behavior change.

Dependencies: none. May run in parallel with S1, S5a and S8a.

Checkpoint: behavior-neutral BridgeWeb structure commit.

Split trigger: stop if extraction requires a wire or behavior change; that
belongs to S2.

### S8a — SwiftPM WebKit Transport And Lifecycle Lower Gate

Purpose:

- keep the SwiftPM Swift Testing process as the real in-process WKWebView lower
  gate without claiming that its non-running `NSApplication` is compositor
  visible;
- prove the bundled app, custom-scheme streams, one pane comm worker, native
  request/receipt lifecycle and teardown through real WebKit; and
- retain real-git source identity, protocol correlation and zero-residue facts
  that do not depend on visible-document animation frames.

Allowed writes:

- BridgeProductWebKitCarrierTestSupport and its focused hosted WebKit tests.

Proof:

- permanent host classification prevents the SwiftPM helper from being used as
  a physical-paint oracle;
- the real-git File/Review worker, scheme, request/receipt and teardown canary
  remains green;
- no product workaround or wall-clock sleep.

Dependencies: none. May run in parallel with S0a, S1 lower layers and S5a.
S8a must be green before S1 hosted-native transport proof and later in-process
WebKit integration. Visible-document, RAF and painted-disposition proof belongs
only to the LaunchServices-launched app in S8b.

Checkpoint: SwiftPM WebKit lower-gate commit.

### S1 — Synchronous Pane Product Admission

Purpose:

- add the non-actor ProductAdmissionGate;
- carry admission tokens through every control, metadata and content route;
- close/advance synchronously before teardown;
- recheck after suspension and before cache, descriptor, pane-state, metadata
  or response publication;
- retain capability-first external rejection and ensure no lock spans await.

Likely writes:

- new ProductAdmissionGate.swift and focused tests;
- BridgePaneController.swift, +Bootstrap.swift and +IPCProjection.swift;
- BridgePaneProductSchemeProvider and scheme request admission/dispatch seams;
- teardown and residue snapshots.

Permanent RED:

- request starting immediately after close is rejected synchronously;
- admitted request completing after close cannot cache or publish;
- close during provider I/O, producer delivery and response construction leaves
  zero mutation and complete residue accounting.

Proof layers:

- unit: gate state/epoch and lock-free token behavior;
- integration: every product entry/post-await mutation seam;
- hosted native after S8a: pane close with in-flight content and metadata;
- static: no product route bypasses gate admission.

Checkpoint: synchronous admission commit.

Split trigger: any route cannot carry/recheck a token; split that route before
shipping partial coverage.

### S2 — Transactional Review Publication And Worker Commit Barrier

Purpose:

- add BridgeReviewPublicationCoordinator;
- prepare and pre-index immutable Review candidates off-main, then keep the
  MainActor publication coordinator state-only and make package/descriptor
  authority plus pane presentation one synchronous commit turn;
- move package/descriptor authority out of metadata delivery and content cache;
- rename/extract BridgeContentStore as authority-free
  BridgeReviewContentLoaderCache;
- retain readable A while staging isolated B;
- commit native B before worker-visible B;
- stage complete B in the comm worker and swap once at the validated barrier;
- retry/resync post-commit B without native rollback;
- retire A after B observation or admitted A-lease settlement;
- replay committed native B after worker-stream reinstall.

Native write sublane:

- pane controller diff/publication/bootstrap/teardown owners;
- off-main Review candidate preparation/indexing, the state-only MainActor
  publication coordinator and the authority-free loader cache;
- metadata/content sources and delivery coordinator;
- focused Swift authority, lease, failure and replay tests.

Worker write sublane:

- Review metadata projection/applicator;
- extracted Review runtime helper from S0a;
- bridge-product-review-metadata-contracts and codecs only if barrier inspection
  proves a contract change necessary;
- focused pending-B, gap, stale identity, replay and disposition tests.

Protected surfaces:

- recovered React viewer, tree and CodeView presentation;
- File runtime;
- pane-worker ownership;
- public Pierre adapter and dependency.

Permanent RED matrix:

- staging, delivery reservation, native commit, first frame, partial delivery,
  final barrier, observation, retry and uninstall/reinstall failures;
- no partial B paint, no gapped completion and no B-to-A snapback;
- pre-commit failure preserves A; post-commit failure retains native B;
- terminal residue includes coordinator/source tasks, observations, producers,
  leases, queued bytes and lifecycle acknowledgements.

Proof layers:

- Swift and TypeScript unit state machines;
- real native-worker protocol integration;
- SwiftPM WebKit A/B native-worker transport and lifecycle journey;
- LaunchServices A/B source-to-readable-DOM/disposition journey in S8b;
- hostile/stale/teardown static and integration gates.

Dependencies: S0a and S1. The in-process WebKit layer additionally requires
S8a; visible paint remains a later S8b obligation.

Checkpoint: one serial cross-language transactional-publication commit after
both sublanes join. No independent completion claims.

Split trigger: if existing frames cannot represent pending complete B, add a
bounded framing prerequisite; never add a second authority or accept a final
commit barrier without completeness.

### S3a — Canonical Pane Activity Facts

Purpose:

- add missing visible, miniaturized and occluded window facts to the canonical
  lifecycle owner;
- create BridgePaneActivity and the sole App-owned
  BridgePaneActivityCoordinator;
- derive foreground/loaded-hidden/dormant/closed from residency, installed
  controller, tab/arrangement/drawer, pane visibility/zoom, window and app facts;
- keep focus as rank only and browser signals out of activity authority.

Likely writes:

- shared Core visibility derivation;
- WindowLifecycleAtom, ApplicationLifecycleMonitor and MainWindowController;
- WorkspaceSurfaceCoordinator lifecycle/restore wiring;
- BridgePaneActivity model/coordinator and deterministic tests;
- AppDelegate+WorkspaceBoot composition.

Proof:

- deterministic full fact table and every independent fact transition;
- app/window/workspace integration;
- hidden restored pane remains uninstantiated/dormant;
- loaded pane never demotes to dormant.

Dependencies: S2.

Checkpoint: native activity fact-mint commit. It does not complete R68 alone.

Split trigger: if shared window ingress expands outside current lifecycle
owners, split and prove that ingress without approximating key-window state.

Shared composition rule for S3b, S4 and S6:

- `AppDelegate+WorkspaceBoot.swift` and `WorkspaceSurfaceCoordinator.swift` are
  exclusive parent-owned integration surfaces;
- any additional App/workspace initializer or dependency-injection owner found
  to be shared by two of these slices is added to this lease before either
  slice edits it;
- disjoint model, actor, extension, command and provider files may be prepared
  in parallel, but shared composition lands and is verified in the fixed order
  S3b -> S4 -> S6; and
- no lane edits a leased owner while another lane has an unjoined change there.

### S3b — Hidden Dirty Coalescing And Position Retention

Purpose:

- make loaded-hidden admit no body, prefetch or refresh work;
- collapse invalidation storms to one dirty fact;
- paint retained state immediately on foreground return and launch at most one
  latest refresh;
- show only the active surface inline updating state;
- retain independent File and Review selection/tree/content positions;
- close and discard late work through S1/S2 epochs.

Likely writes:

- BridgePaneController and +DiffCommands;
- workspace filesystem event routing;
- worker presentation/activity inputs that suppress demand without minting
  authority;
- focused lifecycle, dirty-state and two-surface tests.

Permanent RED:

- hidden event storm starts zero Git/body/refresh work;
- exactly one dirty fact and one foreground refresh;
- foreground/hidden flip and close-while-dirty cannot publish late output;
- no mode switch or inactive-surface updating chrome;
- dormant cold activation starts defaults, loaded-hidden retains positions.

Proof: unit transition tests, workspace integration and, after S8a, the hosted
two-pane journey.

Dependencies: S3a and S2.

Shared-owner integration: first holder of the S3b -> S4 -> S6 composition
lease. Commit and verify its shared-owner changes before S4 integrates.

Checkpoint: hidden admission/dirty coalescing commit.

### S4 — Attendance And State-Aware Four-Command Hard Cut

Purpose:

- add runtime monotonic BridgePaneAttendanceAtom;
- resolve the deterministically most recently attended matching worktree pane;
- make showBridgeReview/showBridgeFiles reuse or create and select the named
  surface;
- make openBridgeReviewInNewTab/openBridgeFilesInNewTab always duplicate;
- resolve Open versus Go to from the same resolver;
- preserve independent authority/query/presentation for duplicates.

Likely writes:

- attendance atom, AtomRegistry and resolver;
- PaneTabViewController, WorkspaceActionExecutor and
  WorkspaceSurfaceCoordinator+BridgeReviewOpening;
- AppCommand/catalog/shortcut/shell routing;
- CommandBar and RepoExplorer worktree actions;
- native-to-worker named-surface request/receipt;
- AgentStudioIPCBridgeAdapter and startup diagnostics.

Permanent RED:

- attendance changes only after successful activation, focus, default jump or
  new-tab creation;
- passive visibility and refresh do not change ordinals;
- current-active then stable restored tie-breaks are deterministic;
- matching show selects named surface; no match creates; explicit new-tab always
  duplicates;
- File/Review positions survive repeated switches.

Proof: resolver/unit, workspace/command integration, worker receipt and, after
S8a, the hosted multi-pane journey.

Dependencies: S3a. May run in parallel with S6 after S3a.

Shared-owner integration: second holder of the S3b -> S4 -> S6 composition
lease. Resolver/command work in disjoint files may proceed earlier, but shared
composition waits for the S3b checkpoint and commits before S6 integrates.

Checkpoint: state-aware commands and attendance commit.

Split trigger: if public semantic IPC open behavior is not explicit-new-tab,
reconverge that API rather than silently changing it.

### S5a — Reachable agentstudio-git Blocking Executor

Purpose:

- fetch the remote W3 discovery branch immediately before integration and
  record its full remote ref and head SHA; the planning-time expected head is
  97b73a6ba01e78bd1dd2aeea241c68119c55d499, but if the fetched head differs,
  the fetched head becomes the integration and ancestry target;
- merge that freshly recorded W3 discovery head into the existing
  bridge-libgit2-blocking-executor branch without squashing or rebasing;
- preserve and verify the blocking-executor commit
  b9e019fecd6475730c700bf55d589d19a5ab761a plus discovery commits 75fbf97,
  a50dedf, 96aeb47 and 97b73a6 and the existing merge 3c375b2;
- make the resulting merge head remotely reachable without squashing;
- prove the package blocking executor and compatibility before pinning.

Allowed writes:

- only the sibling agentstudio-git worktree/branch for push or reviewed
  package-side remediation.

Proof:

- the fetch output, remote ref and recorded W3 head are preserved in the
  checkpoint evidence;
- that freshly recorded W3 head is an ancestor of the resulting merge head;
- remote reachability of that resulting merge SHA;
- focused executor 5/5;
- discovery filesystem-mutation and incomplete-snapshot suites introduced by
  96aeb47/97b73a6;
- package sequential suites, build, format and lint;
- source audit that mutations/fetch/checkout owners did not move.

Checkpoint: pushed/reachable package commit. Keep its repo history separate.

Dependencies: none. May run in parallel with S0a and S1.

Split trigger: API or discovery regression requires package-side remediation and
fresh proof before S5b.

### S5b — Agent Studio Package Pin And Provider Compatibility

Purpose:

- advance Package.swift/Package.resolved to the reachable proven package SHA;
- verify dependency resolution, production build and Bridge provider behavior;
- change no scheduler policy yet.

Allowed writes:

- Package.swift and Package.resolved, plus only required compatibility fixes
  inside current Bridge provider surfaces.

Proof:

- resolved revision equals remote SHA;
- Swift build, focused provider/content/diff/tree/status tests and lint;
- no CLI Git or Worktrunk production path.

Dependencies: S5a.

Checkpoint: Agent Studio package-pin commit.

### S6 — Worktree-Keyed Git Admission And True Draining Custody

Purpose:

- add one application-scoped BridgeGitReadScheduler;
- key admission and coalescing by worktree;
- keep Review metadata and selected/visible content in separate operation
  classes;
- own logical deadlines, bounded queued/running/draining counts and priority;
- keep a started native call consuming capacity with no backfill until true
  package return;
- discard late output through S1/S2/S3 epochs before mutation;
- hard-cut the detached BridgeGitDataPlaneTimeout owner.

Likely writes:

- scheduler models/actor/tests and scrubbed telemetry;
- AppDelegate/workspace composition and provider injection;
- BridgeReviewSourceProviderFactory and AgentStudioGitBridgeReviewDataClient
  Git I/O;
- timeout implementation/tests.

Permanent RED:

- blocked native read logically times out but remains draining;
- no replacement/backfill before true return;
- selected content progresses while metadata class is blocked;
- one slow worktree does not starve another;
- release causes exact slot release, late discard and zero residue.

Proof: deterministic scheduler unit, provider integration and focused blocked-
read native tests. Numeric capacities remain symbolic until S10b.

Dependencies: S1, S3a and S5b. May run in parallel with S4.

Shared-owner integration: third holder of the S3b -> S4 -> S6 composition
lease. Scheduler/provider work in disjoint files may proceed earlier, but App/
workspace composition waits for the committed S4 integration.

Checkpoint: bounded scheduler/draining-custody commit.

Split trigger: if custody cannot survive logical caller completion, return to
design; detached replacement is not an alternative.

### S0b — Remaining Behavior-Neutral Structure

Purpose:

- split the remaining eight files over the architecture cap by current
  responsibility after S2 stabilizes product owners;
- preserve behavior and test meaning.

Allowed writes:

- app-asset-contract.ts;
- bridge-comm-worker-command-handler.unit.test.ts;
- bridge-main-render-snapshot-store.ts;
- bridge-telemetry-worker-runtime.unit.test.ts;
- bridge-file-viewer-app.browser.refresh-demand-suite.tsx;
- bridge-code-view-metadata-apply.unit.test.ts;
- bridge-code-view-panel.tsx;
- bridge-viewer-browser.recovery-witness.test-support.tsx;
- adjacent behavior-neutral extracts.

Proof: focused parity before/after, line-cap architecture gate, typecheck, lint,
format and affected Browser/unit tests.

Dependencies: S2. May run in parallel with S3a and S7.

Checkpoint: remaining structure commit.

### S7 — BridgeWeb Static And Aggregate Regression Recovery

Purpose:

- remove only the false static prohibition on public worker whole-item parsing;
- preserve private-Pierre, legacy-owner, package-diff and forbidden-carrier
  negatives;
- after S2, freshly rerun the full unit, architecture and static gates, record
  the exact failing-file/test manifest at that source identity, and classify
  every survivor against the final S2 owners;
- fix real behavior red-first and stale fixtures without weakening contracts.

Allowed writes:

- only the freshly derived in-scope failing test/source owners and S0 extracts;
- no unrelated UI/product expansion.

Required local result:

- freshly derived focused manifest: every selected test passes, with exact
  file/test counts recorded and no zero-selection command;
- full BridgeWeb unit: 1,445/1,445 or a freshly increased exact count;
- zero architecture/static violations;
- typecheck, product-contract typecheck, type-aware lint, format, build and
  asset audit pass.

Dependencies: S0a and S2. Run with S0b after shared manifests are disjoint.

Checkpoint: BridgeWeb aggregate-green commit.

Scope guard: a survivor outside Bridge scope stops edits and is reported.

### S8b — Packaged LaunchServices WKWebView Product Journey

Purpose:

- generate and launch the current-worktree app through the standard debug
  LaunchServices/observability path;
- use real agentstudio-git, semantic AgentStudio IPC, the custom-scheme worker
  streams and restored UI;
- prove File/Review deep traversal, final source correlation and disposition;
- prove S2 publication replay, S3 activity/dirty behavior, S4 command reuse/
  duplication, S6 timeout/late discard, reset/reconnect/cancel, two panes and
  telemetry off/on/failure.

Permanent RED:

- packaged journey is absent or cannot bind selection -> descriptor -> role ->
  request -> live source -> readable DOM -> painted disposition;
- missing lifecycle/authority/zero-residue proof fails the journey.

Proof:

- hosted WebKit lower gate;
- visible document and live RAF from the running LaunchServices application;
- generated bundle source/asset/executable audit;
- LaunchServices PID/bundle/launch-method identity;
- semantic IPC journey;
- Victoria marker-scoped logs/metrics;
- Peekaboo visual and momentum proof targeted to the candidate PID.

Dependencies: S8a and S2-S7.

Checkpoint: packaged WKWebView product-journey commit.

Scope guard: LaunchServices, signing or shared observability failure outside the
agreed code path is reported, not repaired by expanding scope.

### S9 — One Dedicated Vite Product E2E Owner

Purpose:

- add exactly one BridgeWeb/vitest.e2e.config.ts;
- run deterministic and disposable live-worktree sources through the existing
  Vite provider, real pane worker, restored UI, Pierre and disposition path;
- prove hierarchy, continuous early/middle/final Review traversal, complete File
  final bytes/deep scroll, reset/reconnect and honest source correlation.

Allowed writes:

- vitest.e2e.config.ts;
- tests/e2e/bridge-viewer-vite-product.e2e.test.tsx;
- smallest shared fixture/helper;
- one package script.

Proof:

- absence/product-journey RED before creation;
- deterministic fixture E2E;
- disposable live-worktree E2E with independent source checksum/oracle;
- server/provider/browser/Pierre/worker/source-generation freshness.

Dependencies: S8b by explicit product decision.

Checkpoint: dedicated Vite E2E commit.

Split trigger: consolidate if a second provider/config/runtime appears.

### S10a — Immutable 84-Cell Product Correctness And p99 Matrix

Purpose:

- correct stale package-first/mock benchmark scaffolds;
- close 21 product rows x browser/packaged runtimes x telemetry off/on;
- keep correctness, memory/main-thread work and p99 in the same immutable
  candidate matrix.

Starting policy freeze before the first measured launch:

- admission lanes are `selected > visible > nearby > speculative > background`
  from `bridge-demand-models.ts` and `bridge-content-demand-policy.ts`;
- eviction is byte-bounded LRU for offscreen, unprotected complete items only;
  selected/visible items and publications awaiting a terminal disposition stay
  protected, with the body registry and its admission owner recorded;
- reset uses Swift `sourceGeneration` plus per-surface worker derivation epochs,
  discards stale generation/epoch/sequence/instance work before mutation, and
  re-derives demand instead of parking membership; and
- anchor protection retains same-identity layout, uses Pierre `scrollTo` as the
  sole programmatic viewport writer, vetoes reveal during momentum, never
  re-arms a settled reveal from hydration, and verifies the post-settle anchor.

The immutable evidence records the exact owning modules and numeric starting
constants. A stale File prefix cap, unprotected selected/visible eviction, or
different reset/anchor behavior blocks measurement and returns to its owning
slice; S10a cannot measure first and back-fit the policy afterward.

Proof contract:

- exactly 84 valid cells;
- three fresh launches per runtime/telemetry cohort;
- first launch is warm-up and excluded;
- at least 100 attempted measured actions per measured launch;
- per-launch and pooled nearest-rank p95/p99, with release evaluation against
  the maximum measured-launch percentile for each cell/cohort; never average
  launch percentiles or let a pooled percentile hide one bad launch;
- every correctness/telemetry failure retained numerically;
- complete manifest, final real hunk/File bytes, stable tree/CodeView, heap and
  main-thread stop lines.

Freshness:

- candidate SHA/diff, fixture/oracle digest, machine, viewport, browser/WebKit/
  Pierre/worker versions, process/marker, telemetry mode, launch/cell/attempt.

Dependencies: S8b and S9.

Checkpoint: immutable product matrix commit/evidence.

Reconverge on missing/invalid cells, lossy required telemetry, whole-item
physics failure or any stop-line miss. Do not weaken the matrix or add a File
cap.

### S10b — Five-Repo Blocked-Read Workload And Capacity Calibration

Purpose:

- exercise five repositories, several worktrees, duplicate panes, one
  deliberately blocked native read, background invalidation storms and selected
  foreground work;
- prove operation-class and worktree isolation;
- measure and then bind only stable scheduler capacity/rank constants.

Proof:

- logical timeout/cancel with unchanged physical/draining occupancy;
- no backfill before true return;
- selected content progress while metadata is blocked;
- queue/running/draining bounds, MainActor/event-loop heartbeat, slow-worktree
  isolation, applicable foreground p95/p99 and zero residue;
- late output discarded and exact slot release after the seam opens.

Freshness:

- candidate/package pin, fixture repo/worktree identities, scheduler config,
  class/slot/draining ids, machine/process/marker.

Dependencies: S6 and S8b.

Checkpoint: blocked-read workload and measured-policy commit.

Reconverge if capacities are unstable or workload cannot observe physical
custody. Discovery/status capacities cannot be copied.

### S11a — Final Local Hard Cut And Quality

Purpose:

- compile-delete any remaining rejected authority/carrier;
- rebuild and audit BridgeWeb assets;
- prove no Pierre diff/private API/local dependency;
- prove no production CLI Git/Worktrunk, old projection worker, package-first
  bootstrap, resource GET or duplicate owner;
- rerun every affected lower gate and the full local pyramid at the final SHA.

Required gates:

- BridgeWeb check, unit, Browser, E2E, build, asset/dependency audit and
  benchmark validators;
- Swift format/lint, build, focused and full test layers, hosted WebKit,
  packaged journey and observability verifiers;
- S10a and S10b freshness at the final candidate;
- git diff/check/status, dependency/Pierre/static source audits.

Checkpoint: final local-green hard-cut commit.

### S11b — Implementation Review And One Remediation

Use implementation-review-swarm with bounded lanes for native authority,
worker/web behavior, concurrency/reliability, security/static cut and proof
honesty. Parent validates every finding. Apply one remediation pass, rerun every
affected local/packaged/performance gate and commit the accepted fixes. No second
external loop.

Dependencies: S11a.

Checkpoint: accepted implementation-review remediation commit.

### S11c — CI And PR Readiness

Use implementation-pr-wrapup:

- push scoped commits;
- create/update the PR without merge;
- bind all evidence to the exact PR head;
- watch checks with the repository-approved blocking interval;
- inspect comments and unresolved review threads;
- answer or remediate valid findings and rerun affected gates;
- prove checks green, threads resolved or evidence-dispositioned,
  mergeability clean and artifact identities current.

Terminal: PR ready, not merged.

## 8. Execution DAG And Join Ownership

    Gate A: re-anchor HEAD/status/spec and freeze manifests
      |
      +-- S0a Review runtime structure
      +-- S8a SwiftPM WebKit transport/lifecycle lower gate
      +-- S1 synchronous admission lower layers
      +-- S5a package reachability/verification -> S5b pin
      |
    Join A: parent verifies four disjoint checkpoints; S8a gates in-process
            WebKit transport proof from S1 onward
      |
    S2 transactional native/worker Review publication
      |
      +-- S3a activity facts
      +-- S0b remaining structure
      +-- S7 BridgeWeb aggregate/static recovery
      |
    Join B: no browser activity authority; worker/unit/check green
      |
      +-- S3b hidden dirty behavior
      +-- S4 attendance/four commands
      +-- S6 Git scheduler/draining custody
      |
    Join C: close/activity/late-output/multi-pane integration
      |
    S8b packaged LaunchServices journey
      |
    S9 dedicated Vite E2E
      |
      +-- S10a immutable 84-cell matrix
      +-- S10b blocked-read/capacity workload
      |
    Join D: final measured candidate
      |
    S11a local hard cut -> S11b review/remediation -> S11c PR readiness

Parallel lanes receive disjoint write manifests. Shared owners are serialized at
parent joins. S2 sublanes may prepare independently but have one integration
claim and checkpoint. S8 through S11 are serial by runtime/evidence identity.

## 9. Requirements / Proof Matrix

| Requirement / claim | Source | Owning slice | Proof modality and layer | Evidence source | Freshness guard | RED/GREEN | Fits slice |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Complete File streaming and deep-scroll stability | R42-R49, R61, R65 | achieved checkpoints; S8b, S9, S10a, S11a freshness | unit, Browser, packaged, E2E, matrix | parent-run checksum/DOM/disposition and runtime evidence | final source, selected path, file identity, bundle/server/process | existing regression plus final green | yes |
| Hierarchical Review and continuous complete order | R41-R46, R56, R61 | achieved checkpoints; S8b, S9, S10a, S11a freshness | unit, Browser, packaged, E2E, matrix | parent traversal/tree/header/content evidence | source/manifest/layout/Pierre/runtime identity | existing regression plus final green | yes |
| One pane worker and no legacy owner | R42, R49, R54-R57, R61 | S2, S7, S11a | unit, integration, static, packaged | parent source/asset/trace audit | final diff, worker, bundle assets | permanent static red/green | yes |
| Synchronous close and post-await suppression | R67 | S1 | unit, fault injection, hosted native, static | parent gate/mutation/residue snapshots | pane/gate epoch and request identity | permanent RED required | yes |
| Transactional A-to-B publication and replay | R67 | S2 | native/worker unit, integration, hosted WebKit | parent A/B phase, DOM/disposition, replay and residue | publication/source/stream/lease identities | permanent matrix RED | yes, one vertical join |
| Native activity and dirty return | R68 | S3a, S3b | state table, workspace integration, hosted/packaged | parent native facts, work counts, positions and UI state | activity facts, pane/window/app identity | permanent RED required | yes after split |
| Deterministic reuse and explicit duplicates | R68 | S4 | resolver unit, workspace/worker/packaged | parent command result, attendance and receipt | workspace order, ordinal, pane authority | permanent RED required | yes |
| Blocking libgit2 boundary is reachable and pinned | R69 | S5a, S5b | package tests/build/lint and provider compatibility | parent package/remote/pin/build evidence | remote SHA and Package.resolved | existing package red/green reverified | yes after repo split |
| Worktree/class admission and physical draining | R69 | S6, S10b | scheduler unit, blocked-read integration/workload | parent queue/running/draining/heartbeat/residue | pin, class, worktree, slot, process/marker | permanent RED required | yes |
| Current BridgeWeb regressions and structure | repo gates | S0a, S0b, S7 | focused/full unit, architecture, static, check/build | parent exact counts and command exits | HEAD, lock/config/source hashes | current 23 RED to zero | yes after split |
| Full packaged product behavior | R41-R69, WebKit constraints | S8a, S8b | SwiftPM WebKit transport/lifecycle, packaged LaunchServices paint, IPC, Victoria, visual | parent bundle/PID/source/DOM/disposition evidence | source/assets/executable/PID/launch/marker | missing journey RED | yes after proof-owner split |
| One honest Vite E2E owner | R61, R65 | S9 | deterministic and disposable live-worktree E2E | parent independent source oracle and readable DOM | config/server/provider/browser/source generation | absent owner RED | yes |
| Whole-item correctness, memory and p99 | R41, R57, R61, R62 | S10a | immutable 84-cell matrix | parent completeness validator and numeric results | candidate/fixture/machine/runtime/marker | invalid/missing cell RED | yes after workload split |
| No Pierre modification/private path | non-goal, R57/R61 | S7, S11a | dependency/source/asset audit and static negative | parent final diff and package audit | final diff, lockfile, Pierre version | static RED to green | yes |
| Full quality, review, CI and PR readiness | terminal | S11a-c | full pyramid, review and PR gates | parent commands, review reduction and GitHub state | final PR head/check SHA | administrative gates plus product reds | yes |

No row may use telemetry as its own correctness oracle. Required telemetry loss
makes proof ineligible but remains product-fail-open.

## 10. Validation Commands And Gate Order

The executor confirms exact current script/filter names before use. Expected
gate families from repo root:

BridgeWeb lower gates:

    pnpm -C BridgeWeb exec vitest run <focused paths> --reporter=dot
    pnpm -C BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser <focused paths>
    pnpm -C BridgeWeb run typecheck
    pnpm -C BridgeWeb run check:product-contract
    pnpm -C BridgeWeb run lint:types
    pnpm -C BridgeWeb run fmt:check

BridgeWeb aggregate:

    pnpm -C BridgeWeb run test
    pnpm -C BridgeWeb run check
    pnpm -C BridgeWeb run test:browser
    pnpm -C BridgeWeb run build
    pnpm -C BridgeWeb run audit:assets

S9 adds one package script for:

    pnpm -C BridgeWeb run test:e2e

Swift lower and aggregate:

    mise run test-fast -- --filter <focused suite>
    mise run test-webkit -- --filter WebKitSerializedTests/BridgeProductRealGitFileAndReviewWebKitTests
    mise run lint
    mise run build
    mise run test

Every focused Swift filter must report a nonzero executed suite/test count in
its receipt. Exit zero with zero selected tests fails the gate. Keep canonical
slash-qualified WebKit filters; do not rewrite them to dot qualification.

Packaged/observability:

    mise run observability:up
    mise run run-debug-observability -- --detach
    mise run verify-debug-observability
    mise run verify-bridge-product-paint-correlation
    mise run verify-bridge-review-journey-smoke
    mise run verify-bridge-mode-idle-smoke
    mise run verify-bridge-review-momentum-scroll-state-probe

Benchmark and workload:

    mise run bridge-viewer-benchmark
    mise run verify-bridge-headless-manifest
    <new immutable 84-cell verifier from S10a>
    <new blocked-read multi-worktree verifier from S10b>

Final repository checks:

    git status --short
    git diff --check
    git diff --stat <accepted-base>...HEAD
    <TS and Swift hard-cut static filters>
    <Pierre/dependency/asset/production-CLI-Git audit>

Gate order is focused unit -> integration -> Browser/hosted WebKit -> build/
static -> packaged LaunchServices -> Vite E2E -> performance/workload -> full
quality -> implementation review -> CI/PR. Higher layers never replace lower
ones.

## 11. Security And Reliability Rules

- Capability admission remains before body reading/decoding. A closed request
  cannot reveal pane lifecycle to unauthenticated input.
- Gate locks are short and never span await.
- Every suspended operation rechecks admission/activity/publication currentness
  before mutation.
- Close order is synchronous gate/epoch -> activity closed -> stop new
  admission -> cancel logical work -> retire streams/producers -> await nested
  coordinator/source tasks -> settle package leases -> clear cache/presentation.
- A blocked native call is not reported clean until true return releases its
  physical slot.
- Metadata source, session, scheme, coordinator and observation tasks all enter
  residue accounting.
- Telemetry exports only closed enums, counts, durations and safe deterministic
  hashes. Never export raw paths, content, payloads, capabilities, UUIDs or
  source-bearing errors.
- Rollback is whole-slice source reversion only. No runtime fallback, dual
  publication authority, browser-activity fallback or detached replacement path.
- No wall-clock sleeps in tests. Use exact event/state waits, injected clocks
  and deterministic failure seams.

## 12. Checkpoint, Recovery And Dirty-Tree Discipline

- Before every slice record HEAD, status, allowed write manifest and proof
  witness.
- Preserve unrelated paths. Never broad restore, checkout, reset or clean.
- Stage only the verified slice and inspect the staged diff before commit.
- Commit each named checkpoint; do not accumulate multi-slice dirty state.
- Package and Agent Studio commits stay in their respective repos.
- A failed checkpoint remains uncommitted and is diagnosed; no weakening or
  unrelated infrastructure edit is authorized by the failure.
- If reality contradicts the accepted spec, stop code edits and reconverge the
  model with source evidence.

## 13. Split And Reconvergence Triggers

Return to planning/spec discussion when:

- a product route cannot participate in synchronous admission;
- pending complete B cannot be represented without a second authority;
- native window/activity facts cannot be captured by existing lifecycle owners;
- the package executor cannot become reachable/compatible;
- true-return physical custody cannot be preserved;
- required producer/task residue cannot be observed;
- packaged worker-initiated custom-scheme streaming fails;
- the immutable matrix is incomplete/lossy or whole-item physics misses a stop
  line;
- scheduler capacities are unstable;
- a File cap or Pierre change appears necessary; or
- a failing validation layer belongs outside the approved code path.

The response is evidence and reconvergence, never a hidden fallback or weaker
gate.

## 14. Review Cap And Workflow Transition

Plan review policy:

- one persistent ACPX Claude Fable high-effort read-only Advisor;
- approve reads only, no terminal, fail non-interactive permissions;
- one initial plan review and one same-relationship remediation verification;
- parent validates every candidate finding;
- no Opus output and no second external loop.

After accepted remediation:

1. run plan structural/source/proof/diff checks;
2. commit the accepted plan checkpoint;
3. orchestrator records plan-creation -> plan-review -> implementation-execute
   transitions in the goal event log;
4. begin Gate A immediately and continue through PR-ready terminal without
   stopping at phase boundaries.

## 15. Plan Review Receipt

phase_result: complete

evidence:

- accepted spec commit df38a5fb
- four parent-verified first-batch lane artifacts
- parent-synthesized vertical slices, execution DAG and scope/proof fit
- fresh 13-file BridgeWeb failure run: 23 failed, 105 passed, exit 1
- fresh package remote reachability check: b9e019f absent
- corrected current Swift/WebKit evidence; historical failures excluded
- one persistent ACPX Fable high-effort review: needs revision through eight
  bounded plan edits
- one parent remediation: eight accepted findings applied and the invalid
  dot-qualified WebKit filter suggestion rejected
- one same-relationship remediation verification: READY, no contradiction
  introduced

recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan

recommended_transition_reason: The replacement plan covers only remaining work,
maps every accepted requirement to a provable vertical slice, preserves
completed browser recovery, and passed its single Fable review/remediation
cycle; Gate A implementation may begin.
