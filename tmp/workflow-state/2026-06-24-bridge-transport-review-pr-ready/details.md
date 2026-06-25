# Bridge Transport Review PR-Ready Goal Details

Goal id: `2026-06-24-bridge-transport-review-pr-ready`
Status: active
Current workflow: implementation-execute-plan Gate 0.a split-reset review fixes complete
Next workflow: `shravan-dev-workflow:implementation-review-swarm`

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
3. The current route can load Worktree/File data and render tree/content, yet it
   can do so through a standalone `WorktreeFileApp` mini-app and raw `<pre>`
   content path instead of the shared BridgeViewer/FileViewer/Pierre path.
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
  does not prove Gate 0.a because the worktree route still reaches
  `WorktreeFileApp`, a standalone shell that owns a custom file list and raw
  `<pre>` content path.

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

Vite/dev-server Gate 0.a status:

- The exact URL proof row is green as of 2026-06-25 01:16 -04:00 after the
  shared-app boundary proof pass, implementation-review reduction fixes, and
  split reset/replacement false-green fixes.
- Canonical proof command:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-dev-server-proof.json`
- Screenshots:
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-ready.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-search-result.png`
  - `tmp/bridge-viewer-worktree-dev-server/2026-06-25T05-16-01-036Z/worktree-file-stale-refresh.png`
- Focused reviewer-fix proof:
  - `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app-protocol-router.contract.unit.test.tsx src/file-viewer/bridge-file-viewer-app.unit.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts --reporter verbose`
    passed: 4 files, 27 tests
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
  complete or explicitly accepted after the split reset/replacement fixes.

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

Status: Gate 0.a Vite/dev-server product proof is green again after the second
re-review reduction. Gate 1 remains blocked on implementation re-review or
explicit human acceptance.

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
