# Bridge Transport Review PR-Ready Goal Details

Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: active
Current workflow: implementation-execute-plan Gate 0.a shared BridgeViewer/FileViewer correction active
Next workflow: `shravan-dev-workflow:implementation-execute-plan`

## Durable Objective

Finish the full Bridge transport/review epic to PR-ready state. Gate 0 is the
first mandatory prerequisite, not the final PR objective.

The main product focus is a functional, performant Review app on the accepted
Bridge transport/materialization/scheduler architecture. Worktree/File Gate 0
exists to restore trustworthy product proof and prevent raw/mock/minimal routes
from passing, but it must not become the destination. Gates 1-3 are the path to
the Review/Pierre app that works smoothly for large static diffs, live updates,
and change-set comparison.

The work is complete only when:

- Gate 0.a proves the Worktree/File dev-server route renders FileViewer inside
  the shared BridgeViewer shell.
- The full Bridge transport/protocol/scheduler spec is implemented.
- Worktree/File and Review app protocols are implemented against the accepted
  contracts.
- Pierre/Review renderer integration is rewritten onto the new
  transport/materialization/scheduler model.
- The branch is PR-ready but not merged.

## Gates

### Gate 0.a: Shared FileViewer/Pierre Dev-Server Product Proof

Exact URL:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Must prove:

- FileViewer inside the shared BridgeViewer shell, not Review mock route and
  not standalone `WorktreeFileApp`
- primary Pierre CodeView/File canvas on the left
- Pierre FileTree/right rail on the right
- Shiki-highlighted file content
- worker-backed highlighting path when `workers=on`
- provenance/source assertions
- file click/open
- content render
- open-file invalidation shows stale/update state
- refresh is user-invoked and returns content to ready
- search input
- regex toggle
- filter/status controls
- large tree scroll stability
- large file scroll stability
- screenshot artifacts
- JSON proof artifact
- negative assertions against mock/raw/minimal/second-app substitutes,
  including `WorktreeFileApp`, route-local custom shells, custom tree rendering,
  raw `<pre>` body rendering, and DOM-only content-ready markers

Gate 0 starts with Vite/dev-server proof because that is the fastest loop for
the broken Worktree/File product surface. It does not replace native proof for
PR-ready. Before the epic can close, the same protocol behavior must also be
proven through Agent Studio's app-hosted Bridge/WKWebView path with
marker-correlated evidence.

Gate 0 is reopened. The earlier Ticket 00 proof cannot close this gate because
it made the worktree route more usable while preserving the wrong application
boundary. The current target is not "make WorktreeFileApp look better"; it is
"remove/bypass the second app path and prove FileViewer uses the shared
BridgeViewer shell with Pierre FileTree + Pierre CodeView/File + Shiki workers."
The UX contract is one Bridge Viewer App with two modes:

```text
Bridge Viewer App
  ReviewViewer: diffs / changesets / review package
  FileViewer: worktree file browsing / single file / live file view

Shared UX:
  left  = primary Pierre CodeView/File canvas
  right = Pierre FileTree/right rail
  renderer = Pierre + Shiki + workers when enabled
```

The user's latest live-dev-server observation shows the FileViewer surface still
presenting the file tree/search area on the left and file content on the right.
That means the next checkpoint must revalidate the current live dev server and
fix the layout/composition if the observed page still violates the shared UX
contract. Do not advance to Gate 1 from a mock route, a stale Vite process, a
raw/minimal surface, or a proof artifact that was not tied to the exact live
URL after this correction.

Gate 0 source plan:

- [worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)

### Gate 1: Generic Bridge Transport/Core

Implement generic Bridge carriers and runtime primitives only:

- Bridge host/core boundaries
- stream and RPC contracts
- Zod/TypeScript schemas
- resource descriptors
- generic lane vocabulary and scheduling primitives
- backpressure
- descriptor registry and resource executor
- shared validation and telemetry
- telemetry
- Victoria proof where required

Gate 1 must not own Review or Worktree semantics. Concrete projection
materializers and app demand policies belong to Gate 2.

### Gate 2: App Protocols

Implement Worktree/File and Review application protocols:

- live worktree stream semantics
- change-set semantics
- source/version/provenance contracts
- descriptor/content separation
- app-specific projection materializers
- app-specific demand policies that map protocol interest to generic lanes
- large-data-out-of-Zustand invariant
- bounded stream/request behavior

### Gate 3: Pierre/Review Renderer Integration

Complete the Review viewer rewrite/integration:

- Review viewer uses new transport/materialization/scheduler model.
- Static diffs are DiffsHub-like in smoothness and scroll stability.
- Live updates and change-set comparisons are first-class.
- Renderer does not regress markdown click/reveal, filters, or search behavior.

### Gate 4: PR-Ready Non-Merge Terminal

PR-ready means:

- implementation complete
- required proof pyramid passing or explicitly not applicable
- dev-server/browser E2E and visual proof captured
- Agent Studio Bridge/WKWebView runtime proof captured for the relevant product
  path, not only Vite/dev-server proof
- performance/observability proof captured where required
- implementation review findings addressed or explicitly rejected
- lint/typecheck/tests green for agreed scope
- PR opened or updated
- PR checks, review comments, and mergeability freshly reported

Merge is out of scope unless explicitly authorized.

## Reviewer Critical Context

Every reviewer packet for this goal must include this section or an equivalent
summary. Reviewers must not receive only the latest happy-path artifact.

### Why Review Must Be Adversarial

Earlier artifacts incorrectly implied readiness because proof was too narrow.
The route could pass a verifier while the user-visible dev-server page still
rendered the wrong or insufficient surface. The lesson is that green lower-level
proof is not enough when the user asked for product behavior.

Reviewers must attack:

- whether the artifact proves the real product surface
- whether the proof can pass against a mock, raw dump, or minimal route
- whether the contract preserves full PR-ready scope rather than shrinking back
  to Gate 0 only
- whether the plan has real vertical slices with proof gates
- whether proof artifacts include screenshots and browser-visible state
- whether reviewers have enough prior failure context to critique honestly

### Prior Failure Modes To Include In Review Packets

1. The worktree dev URL previously showed raw/gibberish path text in the browser.
2. A narrow verifier could pass while the product surface remained insufficient.
3. Historical Worktree/File proofs could load data and render tree/content
   through a standalone `WorktreeFileApp` mini-app and raw `<pre>` content path
   instead of the shared BridgeViewer/FileViewer/Pierre path.
   Current code routes `worktree-file` through `BridgeApp viewerMode="file"`,
   so current review must focus on the live visible surface: wrong left/right
   composition, stale Vite output, custom non-Pierre substitutes, or proof that
   can pass while the user-visible product is still wrong.
4. Prior spec/review docs used readiness language that was too strong.
5. Subagent review attempts failed due local process/file-descriptor issues and
   must not be counted as completed review.
6. Signed commit failed once because the 1Password signing socket was
   unavailable; the checkpoint was committed unsigned under repo preference.
7. Playwright bundled Chromium was missing; installed Chrome was used for
   browser evidence.

### Current Evidence Split

Old narrow green proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Passed on 2026-06-24.
- Latest artifact observed:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`
- This proves route/data/scroll/text behavior only.
- It does not satisfy Gate 0.

Former product red proof:

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`
- Backend returned 432 frames and 431 rows.
- Browser protocol attribute was `worktree-file`.
- Tree/content rendered after wait.
- Required product controls were absent:
  - search input: 0
  - regex toggle: 0
  - filter/status controls: 0

Superseded product recovery checkpoint:

- Commits:
  - `0efbec01 Add worktree devserver product controls proof`
  - `9371d635 Prove worktree devserver stale refresh`
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Passed on 2026-06-24.
- Proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T23-21-47-787Z/worktree-dev-server-proof.json`
- Screenshots:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-24T23-21-47-787Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-24T23-21-47-787Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-24T23-21-47-787Z/worktree-file-stale-refresh.png`
- This proof is superseded. It proves useful route/data/control behavior, but it
  does not prove Gate 0.a because it predates the shared BridgeViewer/FileViewer
  correction and did not prove the visible shared-shell/Pierre layout contract.

Former Gate 0.a red proof:

- Exact worktree URL:
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
- Worktree route renders `.worktree-file-tree` on the left and
  `.worktree-file-content` on the right.
- Mock/root route renders the intended Bridge/Pierre shell with CodeView on the
  left and right rail on the right.
- `BridgeWeb/src/app/bridge-app-protocol-router.tsx` routes `worktree-file` to
  `WorktreeFileApp`.
- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx` maps `fixture=worktree` to
  protocol `worktree-file`.
- `BridgeWeb/src/worktree-file-surface/worktree-file-app.tsx` owns a custom
  file list/search/filter surface and renders opened content in raw `<pre>`.
- Local Pierre source proof confirms Pierre supports the desired path:
  `CodeViewItem` includes file and diff items; CodeView renders file items;
  file rendering uses Shiki; worker pool support exists through
  `WorkerPoolContextProvider`.

Superseded Vite/dev-server Gate 0.a green proof history:

These proof blocks are historical evidence only. They are superseded by
`gate0a_shared_viewer_shell_correction_active` because the active blocker is
the live visible shared-shell FileViewer contract, including left/right layout.
They must not authorize Gate 1 or PR-ready progress until a fresh exact-URL
browser proof is captured after the correction.

- The exact URL proof row is green as of 2026-06-25 02:49 -04:00 after the
  shared-app boundary proof pass, implementation-review reduction fixes,
  split reset/replacement false-green fixes, forced split-reset lineage proof,
  and duplicate replacement-frame retry fixes.
- Canonical proof command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-dev-server-proof.json`
- Screenshots:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-stale-refresh.png`
- Focused reviewer-fix proof:
  - `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose`
    passed: 4 files, 27 tests
- Focused force-lineage/retry proof:
  - `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
    passed: 3 files, 24 tests
- Type proof:
  - `pnpm --dir BridgeWeb exec tsc --noEmit` passed
- Focused supporting proof:
  - `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.unit.test.tsx`
    passed: 1 file, 3 tests
- `pnpm --dir BridgeWeb run check` passed with existing
    `no-await-in-loop` verifier warnings only
- The proof now asserts shared BridgeViewer FileViewer ownership, Pierre
  FileTree/right rail, Pierre CodeView/File ownership, Shiki rendering,
  worker-backed highlighting request plus ready worker pool/theme state,
  product controls against actual rendered Pierre rows, provider-backed top-level
  tree visual extent facts, nontrivial descriptor-backed available/unavailable
  filter results, stale/refresh, scroll extent canaries, and negative substitute
  guards against
  `WorktreeFileApp`, route-local custom tree/shell, and raw `<pre>` content.
- The prior `2026-06-25T01-45-02-791Z` proof is superseded: implementation
  reviewers found it could pass with disabled workers, status-text-only
  controls, and locally synthesized tree extents.
- The prior `2026-06-25T02-16-36-219Z` proof is superseded: implementation
  reviewers found additional false-green gaps around failed refresh state and
  verifier-created worktree mutations.
- The prior `2026-06-25T02-49-34-424Z` proof is superseded: implementation
  reviewers found the verifier still needed observed URL proof, explicit
  shared-shell DOM containment, tracked-file restore fail-closed behavior,
  worker file-success baseline proof, and retry-after-refresh-failure proof.
- The prior `2026-06-25T03-25-29-946Z` proof is superseded: the shared
  application boundary needed to be made explicit in code and proof. The router
  must dispatch worktree-file to `BridgeApp viewerMode="file"` instead of owning
  a direct file-app shell, and the proof must record `appOwner=BridgeApp`.
- Latest reviewer finding fixes:
  - exact browser URL and `window.location.href` are observed and recorded
    rather than self-reported from the configured constant
  - FileViewer shell must be a direct child of shared `BridgeViewerAppShell`
  - `worktree-file` protocol routing now enters `BridgeApp` file mode; the
    protocol router no longer mounts a direct FileViewer app/shell path
  - shared-shell proof records `appOwner=BridgeApp`
  - provider-backed top-level tree extent source is asserted instead of accepting
    local `pathCount * rowHeight` synthesis
  - product controls prove actual rendered Pierre rows, invalid regex state,
    source labels, and nontrivial available/unavailable filter results
  - unavailable filter proof deletes and restores `.github/workflows/ci.yml` as
    a tracked metadata-only descriptor and verifies content request rejection
  - worker proof requires actual Pierre worker file success/cache state, a
    post-selection increment over the pre-selection baseline, and the selected
    descriptor cache key
  - stale refresh proof mutates and restores an existing tracked file instead
    of creating an untracked verifier file
  - stale refresh verifier writes reject absolute, parent-directory, and
    symlink-escape paths before mutation
  - failed explicit refresh keeps stale body visible and retryable instead of
    blanking into failed state; the runtime state machine now keeps failed
    explicit refresh sessions stale so a second refresh can succeed
  - stale refresh proof records content-route hit counts before first refresh,
    after failed refresh, and after successful retry as `0 -> 1 -> 2`
  - router contract proof now spies on `BridgeApp` and asserts
    `worktree-file -> viewerMode="file"` directly instead of relying only on
    DOM markers
  - selected file proof records a dev-server
    `/__bridge-worktree/file-content` hit for the selected descriptor content
    handle
  - visible provenance proof records the rendered
    `worktree-file-provenance` text and visible rect, not just hidden shell
    attributes
  - unavailable descriptor proof clicks `.github/workflows/ci.yml`, reaches
    `selectedContentState="unavailable"`, and records zero content-route hits
  - unavailable deleted text descriptors are no longer mislabeled as binary;
    `virtualizedExtentKind="unavailable"` carries availability
  - source reset plus replacement file descriptor updates the open session's
    latest descriptor so explicit refresh remains possible
  - source reset plus unrelated post-reset descriptor does not unblock a stale
    pre-reset descriptor for another file
  - split reset/replacement callbacks preserve the open file as stale instead of
    hiding the old body as unavailable
  - Pierre FileTree selected-path synchronization no longer reopens the file
    when replacement descriptors arrive; only user selection opens files
  - source-less reset frames mark open sessions stale and matching replacement
    descriptors make them refreshable, matching the optional-source protocol
    schema
  - unavailable-file proof now probes the entire dev-server file-content front
    door, so any body request during unavailable open fails the proof
  - forced split-reset proof now waits for the explicit force request to deliver
    `worktree.reset -> worktree.snapshot` and the expected source cursor instead
    of letting an ordinary poll reload satisfy the proof
  - stale refresh proof now isolates normal incremental invalidation from forced
    split-reset lineage, so retry behavior is proved without reset-stream races
  - duplicate replacement descriptors with the same content version no longer
    regress an already refreshed file back to stale during retry
- Independent browser subagent visual/DOM proof passed on the exact URL and
  produced `tmp/bridge-viewer-worktree-dev-server/2026-06-25T04-40-15-000Z/worktree-dev-server-proof.json`
  with `standaloneWorktreeFileAppCount=0`,
  `shellOwner=BridgeViewerApp.FileViewer`, `codeOwner=CodeView.file`,
  `treeOwner=FileTree`, `sidebarIsRight=true`, visible provenance, search/regex
  controls, and unavailable zero-fetch behavior.
- Vite dev server remained live on `127.0.0.1:5173` with node PID `65785`
  during this proof.
- Prior 2026-06-24 proof remains lower-level regression evidence only.
- Native Agent Studio Bridge/WKWebView proof is still not satisfied by this and
  remains required before PR-ready.
- Gate 1 work should not begin until Gate 0.a implementation re-review is
  complete or explicitly accepted after the force-lineage/retry fixes.

## Required Reviewer Packet Contents

Each spec, plan, implementation, or PR reviewer must receive:

- goal id and current gate
- exact URL for Gate 0 when relevant
- source specs and current plan paths
- the old green proof versus current red proof distinction
- prior failure modes above
- explicit question: "Can this proof pass while the user-visible product is
  still wrong?"
- expected output format: P0-P3 findings with file/line references, or an
  explicit "no findings" plus residual risk

## Source Artifacts

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)
- [reconciliation-plan-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/reconciliation-plan-2026-06-24.md:1)
- [reconciliation-review-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/reconciliation-review-2026-06-24.md:1)

## Review Packets

- Current Gate 0.a implementation re-review packet:
  [implementation-review-packet-gate0a-reset-lineage-quiescence-2026-06-25.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-packet-gate0a-reset-lineage-quiescence-2026-06-25.md:1)
- Previous Gate 0.a implementation re-review packet:
  [implementation-review-packet-gate0a-force-reset-authority-2026-06-25.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-packet-gate0a-force-reset-authority-2026-06-25.md:1)
- Historical Gate 0.a force-lineage packet:
  [implementation-review-packet-gate0a-force-lineage-retry-2026-06-25.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-packet-gate0a-force-lineage-retry-2026-06-25.md:1)
- Historical Gate 0.a second split-reset packet:
  [implementation-review-packet-gate0a-second-split-reset-2026-06-25.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-packet-gate0a-second-split-reset-2026-06-25.md:1)
- Historical shared-app boundary packet:
  [implementation-review-packet-gate0a-shared-app-2026-06-25.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/implementation-review-packet-gate0a-shared-app-2026-06-25.md:1)
- Current Gate 0.a packet:
  [spec-review-packet-gate0a-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/spec-review-packet-gate0a-2026-06-24.md:1)
- Historical pre-reopen packet:
  [spec-review-packet-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/spec-review-packet-2026-06-24.md:1)

## Implementation Plans

- [implementation-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/implementation-plan.md:1)
- [00-gate0-worktree-product-e2e.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/00-gate0-worktree-product-e2e.md:1)
- [01-gate1-bridge-transport-core.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/01-gate1-bridge-transport-core.md:1)
- [02-gate2-app-protocols.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/02-gate2-app-protocols.md:1)
- [03-gate3-pierre-review-renderer-cutover.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/03-gate3-pierre-review-renderer-cutover.md:1)
- [04-gate4-pr-ready-wrapup.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-24-bridge-transport-review-pr-ready-implementation-plan/tickets/04-gate4-pr-ready-wrapup.md:1)

## Transition Rules

- `events.jsonl` owns official workflow transitions after the goal text.
- Phase skills may recommend transitions but must not silently advance the goal.
- Accepted spec findings route back to spec creation.
- Accepted plan findings route back to plan creation.
- Accepted implementation findings route back to implementation execution.
- Gate 0 must close before downstream Gate 1-4 implementation claims.

## 2026-06-25 Second Split Reset Reduction

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green again after the second re-review reduction. Gate 1
remains blocked.

Accepted findings addressed:

1. Exact URL proof still did not prove replacement handles after source-less
   split reset.
   - Fixed the dev provider so changed file content handles include a content
     hash slice.
   - Added exact URL proof fields for old handle, replacement handle/hash,
     source cursor, zero pre-refresh body-route hits, and one replacement body
     route hit after explicit refresh.

2. Source-less reset admitted later descriptors too broadly.
   - Fixed runtime reset scope so source-less reset descriptors are trusted only
     after a post-reset `worktree.snapshot` source anchor.
   - Added negative runtime proof that an old-stream descriptor remains blocked,
     plus positive proof that anchored descriptors can refresh/open.

3. Matching replacement descriptors could update the visible source while an
   open file stayed `ready`.
   - Fixed `BridgeFileViewerApp` so a matching `worktree.fileDescriptor` marks
     the open file stale and preserves the old body until user refresh.
   - Added UI proof for descriptor replacement without invalidation.

4. Force split reset proof could be lost behind the dev poller.
   - Fixed the dev backend so `bridge-worktree-dev-force-split-reset-reload`
     is sticky if a poll reload is already in flight.
   - Added dev diagnostics for reload frame count/kinds/source cursor used by
     the verifier failure payload.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 21 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-53-31-358Z/worktree-dev-server-proof.json`
  - key artifact facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - descriptor count: 456
    - shared shell owner: `BridgeViewerAppShell`
    - app owner: `BridgeApp`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - split reset proof path: `.mise.toml`
    - split reset body route hits: `0 -> 0 -> 1`
    - stale retry proof path: `.gitignore`
    - stale retry body route hits: `0 -> 1 -> 2`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-53-31-358Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-53-31-358Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-53-31-358Z/worktree-file-stale-refresh.png`
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:browser:integration -- src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx -t "large fixture programmatic file reveal uses bounded CodeView motion"`
  - exit: 0
  - result: 2 files passed, 34 tests passed
- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, AgentStudio architecture
    lint OK, release script verification passed
- `git diff --check`
  - exit: 0

## 2026-06-25 Force-Lineage And Retry Reduction

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green again after fixing the latest force-lineage and
stale-retry issues. Gate 1 remains blocked.

Accepted findings addressed:

1. Forced split-reset proof could still be satisfied by an ordinary poll reload.
   - Fixed the verifier to wait for force-specific delivery diagnostics:
     request `force-split-reset`, status `delivered`, and the expected source
     cursor.
   - The exact URL proof now records forced frame kinds beginning with
     `worktree.reset` and `worktree.snapshot`.

2. Stale refresh retry could race against forced split-reset streams.
   - Fixed the stale-refresh verifier path to use ordinary incremental reloads
     while keeping forced split-reset proof separate.
   - The stale retry proof still records body-route hits `0 -> 1 -> 2` and
     visible stale body preservation.

3. Duplicate replacement frames could regress a successful retry back to stale.
   - Fixed `BridgeFileViewerApp` to keep the latest known descriptor during
     explicit refresh and ignore duplicate invalidation/replacement frames for
     the same content version.
   - Added regression proof that a duplicate same-version replacement after a
     successful retry does not discard the ready state.

4. BridgeWeb type-aware lint failed on Base UI menu namespace prop aliases.
   - Fixed `DropdownMenu` prop typing to derive props from the actual React
     components with `ComponentProps<typeof ...>` instead of `.Props` namespace
     aliases. No casts were added.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 24 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-dev-server-proof.json`
  - key artifact facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - descriptor count: 456
    - selected file: `BridgeWeb/pnpm-lock.yaml`
    - selected line count: 6658
    - shared shell owner: `BridgeViewerAppShell`
    - app owner: `BridgeApp`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - worker file success count: 2
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - split reset proof path: `.mise.toml`
    - forced split reset status: `delivered`
    - forced frame lineage begins with `worktree.reset` then
      `worktree.snapshot`
    - split reset body route hits: `0 -> 0 -> 1`
    - stale retry proof path: `.gitignore`
    - stale retry body route hits: `0 -> 1 -> 2`
  - screenshots:
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-ready.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-search-result.png`
    - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T06-49-27-224Z/worktree-file-stale-refresh.png`

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Vite remains live at `127.0.0.1:5173` for human inspection.

## 2026-06-25 Reset Lineage Re-Review Follow-Up

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green after addressing the latest implementation re-review
blockers. Gate 1 remains blocked.

Accepted findings addressed:

1. Selected-content route proof accepted duplicate content-route traffic.
   - The verifier now requires exactly one content-route hit for the selected
     target file.
   - The only hit must use the selected content handle through the dev-server
     front door.

2. Shared-shell proof could pass against hidden correct markers while a visible
   wrong app rendered.
   - The verifier now requires exactly one app root, FileViewer shell, code
     canvas, and sidebar.
   - The app root, shell, code canvas, and sidebar must each own their visible
     center point.

3. Malformed reset diagnostic tokens could be coerced with `parseInt`.
   - Reset generation, sequence, and count diagnostics now use strict integer
     parsing before numeric validation.
   - Tokens such as `2oops`, `1e3`, or whitespace-suffixed values fail instead
     of coercing.

4. Accepted reset lineage was discarded after the first forced reset.
   - The dev backend now keeps raw provider frames for descriptor comparison and
     accepted emitted frames for lineage continuation.
   - Added a unit regression for force reset, second force reset, then normal
     reload with continuous sequence/generation lineage.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 28 tests passed
- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/bridge-worktree-dev-reload-diagnostics.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 4 files passed, 31 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T08-25-40-405Z/worktree-dev-server-proof.json`
  - key facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - selected file: `BridgeWeb/pnpm-lock.yaml`
    - shared shell owner: `BridgeViewerAppShell`
    - app owner: `BridgeApp`
    - app root count / owns center point: `1 / true`
    - shell owner: `BridgeViewerApp.FileViewer`
    - shell count / owns center point: `1 / true`
    - code owner: `CodeView.file`
    - code canvas count / owns center point: `1 / true`
    - tree owner: `FileTree`
    - sidebar count / right / owns center point: `1 / true / true`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - forced split reset status: `delivered`
    - forced frame generation sample: `2,2,2,2,2,2,2,2`
    - forced frame stream id sample:
      `worktree-file:bridge-worktree-dev-pane`
    - forced frame sequence head: `460,461,462,463,464,465,466,467`
    - forced frame sequence tail: `913,914,915,916,917,918,919,920`
    - stale Refresh disabled before replacement readiness: true
    - stale Refresh enabled after replacement readiness: true
    - split reset body route hits: `0 -> 0 -> 1`

Focused re-review follow-up:

- Removal-triggered reset now uses accepted emitted lineage after repeated
  forced resets.
- Strict reset diagnostic parsing now rejects malformed comma lists such as
  `2,,3`, `2,`, and `,2`.
- The stale-refresh proof now waits for Refresh to become enabled before the
  retry click after the intentionally failed first refresh.

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Re-review is required before Gate 1 unless the human explicitly accepts this
  checkpoint.

## 2026-06-25 Stale-Refresh Route Observer Follow-Up

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green after accepting Feynman's focused re-review finding
that stale-refresh still observed only the replacement handle and could miss
foreign-origin traffic for other handles. Gate 1 remains blocked.

Accepted findings addressed:

1. Stale-refresh origin guard missed foreign file-content traffic for other
   handles.
   - Stale-refresh now installs the all-file-content route observer.
   - The verifier still force-fails only the first replacement-handle refresh
     request, preserving the retry proof while observing other content traffic.
   - The stale-refresh proof asserts zero foreign-origin file-content hits and
     still records retry body hits `0 -> 1 -> 2`.

2. The re-review packet metadata was stale.
   - The packet now describes the current Gate 0.a checkpoint shape, including
     the diagnostics helper files, origin-aware route proof, and the latest
     proof artifact.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run scripts/bridge-worktree-dev-reload-diagnostics.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 1 file passed, 3 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/bridge-worktree-dev-reload-diagnostics.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 4 files passed, 32 tests passed
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T08-57-29-240Z/worktree-dev-server-proof.json`
  - key facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - selected file: `BridgeWeb/pnpm-lock.yaml`
    - selected line count: 6658
    - app owner: `BridgeApp`
    - shared shell owner: `BridgeViewerAppShell`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - selected-content route hit count: 1
    - selected-content foreign-origin hit count: 0
    - split-reset foreign-origin hit count: 0
    - stale-refresh foreign-origin hit count: 0
    - unavailable-open foreign-origin hit count: 0
    - split reset body route hits: `0 -> 0 -> 1`
    - stale retry body route hits: `0 -> 1 -> 2`

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Re-review is required before Gate 1 unless the human explicitly accepts this
  checkpoint.

## 2026-06-25 Origin-Aware Route Proof Follow-Up

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green after accepting Plato's focused re-review finding that
file-content route proof was still origin-blind. Gate 1 remains blocked.

Accepted finding addressed:

1. File-content route proof was origin-blind.
   - The Playwright route gate now counts only file-content requests whose URL
     origin matches the exact dev-server origin.
   - Foreign-origin file-content route matches are recorded separately, fulfilled
     as proof failures, and asserted as zero in selected-content, unavailable,
     stale-refresh, and split-reset proof paths.
   - Diagnostic unit coverage rejects foreign-origin and malformed route URLs.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run scripts/bridge-worktree-dev-reload-diagnostics.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 1 file passed, 3 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/bridge-worktree-dev-reload-diagnostics.unit.test.ts --reporter verbose`
  - exit: 0
  - result: 4 files passed, 32 tests passed
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T08-47-08-058Z/worktree-dev-server-proof.json`
  - key facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - selected file: `BridgeWeb/pnpm-lock.yaml`
    - selected line count: 6658
    - app owner: `BridgeApp`
    - shared shell owner: `BridgeViewerAppShell`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - selected-content route hit count: 1
    - selected-content route uses dev-server front door: true
    - forced split reset status: `delivered`
    - split reset body route hits: `0 -> 0 -> 1`
    - stale retry body route hits: `0 -> 1 -> 2`

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Re-review is required before Gate 1 unless the human explicitly accepts this
  checkpoint.

## 2026-06-25 Force-Reset Lineage And Quiescence Follow-Up

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green after addressing the latest implementation re-review
findings from Russell, Nash, Schrodinger, and Turing. Gate 1 remains blocked.

Accepted findings addressed:

1. Pause ack was not a quiescent barrier.
   - The dev worktree backend now reports `pausing` while a reload is in flight
     and only reports `paused` after the in-flight reload settles.
   - Added unit proof for pausing during an active poll reload.
   - The exact URL verifier waits for `paused` before mutating the proof file.

2. Forced reset frames did not preserve the current accepted lineage.
   - Reset frames now derive `streamId`, next generation, and next sequence from
     the previous accepted surface.
   - Replacement snapshot/descriptor frames are rebased onto the same reset
     lineage.
   - The exact URL verifier now records and asserts one generation lineage, one
     stream lineage, and strictly increasing sequence lineage.

3. Sequence parsing could false-green malformed values.
   - The verifier now rejects non-safe-integer sequence/generation values.

4. The exact URL proof did not prove the intermediate stale-disabled state.
   - Added a dev-only split-reset replacement delay knob used only by the
     verifier.
   - The exact URL proof now observes stale content with Refresh disabled before
     replacement readiness, then Refresh enabled after the replacement descriptor
     arrives.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 27 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T07-45-56-933Z/worktree-dev-server-proof.json`
  - key facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - app owner: `BridgeApp`
    - shared shell owner: `BridgeViewerAppShell`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - forced split reset status: `delivered`
    - forced frame generation sample: `2,2,2,2,2,2,2,2`
    - forced frame stream id sample:
      `worktree-file:bridge-worktree-dev-pane`
    - forced frame sequence head: `459,460,461,462,463,464,465,466`
    - forced frame sequence tail: `911,912,913,914,915,916,917,918`
    - stale Refresh disabled before replacement readiness: true
    - stale Refresh enabled after replacement readiness: true
    - split reset body route hits: `0 -> 0 -> 1`

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Re-review is required before Gate 1 unless the human explicitly accepts this
  checkpoint.

## 2026-06-25 Force-Lineage Review Reduction Follow-Up

Historical status, superseded by
`gate0a_shared_viewer_shell_correction_active`: Gate 0.a Vite/dev-server
product proof was green after addressing the latest implementation re-review
findings around forced split-reset proof authority and refresh readiness. Gate
1 remains blocked.

Accepted findings addressed:

1. Forced split-reset frames were protocol-invalid after a source-less reset.
   - Fixed normal and forced reset paths to rebase replacement frame sequences
     after the reset frame.
   - Added unit proof that reset/snapshot/descriptor sequence lineage is
     strictly increasing for replacement surfaces.

2. Forced split-reset proof could still be satisfied by the ordinary dev
   poller.
   - Added dev-server pause/resume proof controls around the forced split-reset
     verifier path.
   - The verifier now pauses polling before mutating the proof file and resumes
     it in `finally`.

3. Stale refresh could be clicked before the replacement descriptor was
   refreshable.
   - FileViewer still shows the stale notification immediately, but disables
     Refresh until the latest descriptor for the open file is materialized.
   - The exact URL verifier waits for the Refresh button to become enabled
     before clicking it.

4. Dev-server proof output was too large for quick review.
   - The result no longer leaks full rendered file text through the verifier
     result object.
   - Console output now reports bounded frame-kind and sequence samples; the
     full artifact remains on disk for detailed review.

Fresh proof:

- `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-dev-worktree.unit.test.ts src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts --reporter verbose`
  - exit: 0
  - result: 3 files passed, 25 tests passed
- `pnpm --dir BridgeWeb exec tsc --noEmit`
  - exit: 0
- `pnpm --dir BridgeWeb run check`
  - exit: 0
  - note: existing verifier `no-await-in-loop` warnings remain warnings only
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
  - exit: 0
  - artifact:
    `tmp/bridge-viewer-worktree-dev-server/2026-06-25T07-21-13-935Z/worktree-dev-server-proof.json`
  - key facts:
    - exact URL:
      `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
    - selected file: `BridgeWeb/pnpm-lock.yaml`
    - selected line count: 6658
    - shared shell owner: `BridgeViewerAppShell`
    - app owner: `BridgeApp`
    - shell owner: `BridgeViewerApp.FileViewer`
    - code owner: `CodeView.file`
    - tree owner: `FileTree`
    - Shiki rendering: `pierre`
    - worker pool state: `ready`
    - standalone `WorktreeFileApp` count: 0
    - review empty shell count: 0
    - forced split reset status: `delivered`
    - forced frame lineage sample starts with
      `worktree.reset`, `worktree.snapshot`
    - forced frame sequence head: `458,459,460,461,462,463,464,465`
    - forced frame sequence tail: `909,910,911,912,913,914,915,916`
    - split reset body route hits: `0 -> 0 -> 1`
- `mise run lint`
  - exit: 0
  - result: swift-format OK, SwiftLint 0 violations, AgentStudio architecture
    lint OK, release script verification passed

Proof surface contract:

- This remains Vite/dev-server product proof only.
- Native Agent Studio Bridge/WKWebView proof is still required before PR-ready.
- Vite remains live at `127.0.0.1:5173` for human inspection.
