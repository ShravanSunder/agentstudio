# Bridge CodeView, Trees, And Shiki Review Viewer

Planned at: `luna-338-pierreshikitrees-review-viewer`
Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
Status: implementation in progress; IPC merge follow-up added after `origin/main`
Linear: `LUNA-338`

## Goal

Implement the first package-backed Bridge review viewer on top of the
`LUNA-337` review foundation. The viewer renders read-only files, diffs, and
docs/plan files with Pierre CodeView, Pierre Trees, worker-backed Shiki
highlighting, Bridge-owned projections, on-demand content hydration, debug
observability, and benchmarkable large-diff/tree proof.

The implementation must keep the Bridge data model intact: Swift pushes compact
metadata and validates privileged reads; BridgeWeb owns projection, selection,
renderer adapters, and visible-content hydration; Pierre owns rendering and
syntax-highlighting primitives only.

After the merge of the AgentStudio IPC foundation from `origin/main`, LUNA-338
also needs a semantic Bridge IPC/e2e lane. IPC must integrate with Bridge as a
product capability through typed app-level methods and ports. It must not expose
BridgeWeb/WebKit transport internals, drive command-palette UI, publish command
events, or bypass Bridge's content-handle and telemetry boundaries.

## Source Coverage

Design source read end to end:

- `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md`
  - line count: 1,878
  - chunks read by planner: 1-260, 261-620, 621-980, 981-1340, 1341-1845,
    1840-1878 after review fixes

Related live repo evidence inspected:

- `BridgeWeb/package.json`
- `BridgeWeb/tsconfig.json`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/vitest.config.ts`
- `BridgeWeb/.oxlintrc.json`
- `BridgeWeb/.oxfmtrc.json`
- `BridgeWeb/scripts/normalize-build-output.mjs`
- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/bridge/*`
- `BridgeWeb/src/foundation/**`
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- `.mise.toml` BridgeWeb, WebKit, benchmark, and observability tasks
- `Sources/AgentStudio/Features/Bridge/**`
- `Tests/AgentStudioTests/Features/Bridge/**`
- `Sources/AgentStudioProgrammaticControl/IPC*.swift`
- `Sources/AgentStudioAppIPC/**`
- `Sources/AgentStudio/App/IPCComposition/**`
- `docs/architecture/agentstudio_ipc_architecture.md`
- Pierre local reference files under
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre`

Pierre reference anchors:

- `apps/diffshub/app/_components/CodeViewWrapper.tsx`
- `apps/diffshub/app/_components/usePatchLoader.ts`
- `apps/diffshub/app/_components/codeViewDataAccumulator.ts`
- `apps/diffshub/app/_components/CodeViewFileTree.tsx`
- `apps/diffshub/app/_components/WorkerPoolContext.tsx`
- `apps/diffshub/app/_components/WorkerPoolStatus.tsx`
- `packages/diffs/benchmarks/CSS_PERFORMANCE_BENCHMARK.md`
- `apps/docs/app/(diffs)/docs/WorkerPool/content.mdx`
- `apps/docs/app/(diffs)/docs/CodeView/content.mdx`
- `apps/docs/app/(trees)/docs/Guides/HandleLargeTreesEfficiently/content.mdx`

## Current Evidence

- BridgeWeb is still a minimal Vite/React/Zod app. `package.json` has no
  Pierre, Zustand, or tsdown dependencies.
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` is the only
  current viewer surface. It renders a plain package/file/content shell.
- `BridgeWeb/src/foundation/review-package/*` already owns package/delta
  contracts, registry, adapters, fixtures, and tests.
- `BridgeWeb/src/foundation/content/*` already owns content-resource loading
  and a small review content cache.
- `BridgeWeb/src/foundation/telemetry/*` already owns web telemetry recording,
  trace context, taxonomy, and tests.
- `.mise.toml` already defines `bridge-web-check`, `bridge-web-test`,
  `bridge-web-build`, `test-webkit`, `test-benchmark`, observability launch,
  and bridge observability verification tasks.
- Swift Bridge foundation files and tests are present under
  `Sources/AgentStudio/Features/Bridge` and
  `Tests/AgentStudioTests/Features/Bridge`.
- Existing `test-benchmark` is Swift push benchmark oriented; this plan must
  extend benchmark proof for the viewer rather than relabeling that gate.
- After the `origin/main` merge, phase-one AgentStudio IPC exists with typed
  JSON-RPC contracts, method definitions, privilege/data scopes, event
  subscriptions, command/UI separation, and app composition adapters. The
  current method catalog does not yet expose `bridge.*` methods. Bridge IPC must
  be added as a new product capability port rather than by calling raw WebKit,
  command-bar presentation, or EventBus command routing.

## Non-Goals

- No source editing, Monaco, patch apply, approve/reject, or accept-agent-change
  UI.
- No durable annotation/comment-body persistence.
- No rich markdown preview in slice 1; markdown renders as source text.
- No general endpoint tree browser UI in slice 1.
- No direct BridgeWeb OTLP exporter. Browser-originated telemetry still flows
  through Swift's existing debug telemetry path.
- No package-private Pierre imports, including local checkout paths,
  `@pierre/*/dist/**`, and type-only private imports.
- No runtime benchmark fixture generation in packaged app code.
- No replacement of `BridgeReviewPackage`, `BridgeReviewDelta`, or content
  handle contracts with Pierre-specific DTOs.
- No public IPC methods such as `webview.evaluateJavaScript`,
  `bridge.rawPostMessage`, `bridge.rawPush`, `eventBus.publish`, or `zmx.*`.
  IPC can call only semantic Bridge capability methods whose params/results are
  typed in `AgentStudioProgrammaticControl`.

## Requirements / Proof Matrix

Requirement / claim:
BridgeWeb pins Pierre, Zustand, and packaged-build tooling without importing
from the local Pierre monorepo.
Proof source:
`BridgeWeb/package.json`, `BridgeWeb/pnpm-lock.yaml`, dependency/export smoke
tests, `mise run bridge-web-audit`, license artifact, bundle-size artifact.
Proof owner:
implementation parent and BridgeWeb unit tests.
Stale-proof guard:
verify installed package exports in the current lockfile before using them.
Proof layer:
unit, build, size/license artifact.
Red/green:
not required for dependency installation; export smoke must fail before deps
are installed.

Requirement / claim:
BridgeWeb architecture boundaries are enforceable, especially that Zustand
state does not own effects.
Proof source:
BridgeWeb architecture boundary checker through `bridge-web-check`, negative
fixtures/tests for forbidden imports/calls, selector tests.
Proof owner:
implementation parent and BridgeWeb unit tests.
Stale-proof guard:
checker runs against the current `BridgeWeb/src` tree in CI/local gates.
Proof layer:
unit, lint/check.
Red/green:
required for at least one forbidden `review-viewer/state` effect import/call.

Requirement / claim:
AgentStudio IPC exposes Bridge only through semantic capability methods and
typed ports, not through BridgeWeb/WebKit internals or command-palette UI.
Proof source:
`AgentStudioProgrammaticControl` Bridge IPC DTOs and method definitions,
`AgentStudioAppIPC` registry/routing tests, `AgentStudio/App/IPCComposition`
Bridge adapter tests, IPC permission tests, and debug IPC e2e proof.
Proof owner:
Swift IPC/Bridge tests and implementation parent.
Stale-proof guard:
capabilities query from the current debug app must list the implemented
`bridge.*` methods; negative tests prove generic WebKit/raw-post/event-bus
methods are absent.
Proof layer:
unit, integration, IPC e2e/smoke.
Red/green:
required for unsupported-target, unauthorized cross-pane content, and
command-bar-not-opened behavior.

Requirement / claim:
New LUNA-338 viewer-local TypeScript contracts follow Zod model conventions:
`xxxSchema` value, `Xxx` derived type, descriptive generics, no duplicate
hand-written schema shadows. This applies to viewer-local schemas,
worker/RPC envelopes, and shared contract files touched by this implementation;
it is not an implicit rewrite of unrelated LUNA-337 foundation contracts.
Proof source:
schema/type tests and architecture boundary checker scoped to intended paths.
Proof owner:
BridgeWeb unit tests.
Stale-proof guard:
test scans current LUNA-338 viewer source, worker/RPC envelopes, fixtures, and
any explicitly touched shared contracts.
Proof layer:
unit/type.
Red/green:
required for one invalid duplicate type or naming fixture in the scoped paths.

Requirement / claim:
Projection modes and refinements can render all, changed, guided, change-set,
docs/plans, tests, source, Git-status, file-class, extension/language, and
folder-scoped views from one active package without content fetches.
Proof source:
projection builder tests using `bridge_viewer_medium_review_v1`.
Proof owner:
BridgeWeb unit and integration tests.
Stale-proof guard:
fixture builder is deterministic and package metadata only.
Proof layer:
unit, integration.
Red/green:
required for projection/filter behavior.

Requirement / claim:
Tree identity and row decoration handle renames, duplicate display paths,
base/head candidate paths, and primary/secondary item mapping.
Proof source:
navigation projection tests and Trees controller tests.
Proof owner:
BridgeWeb unit tests.
Stale-proof guard:
fixture includes renamed and duplicate-display-path cases.
Proof layer:
unit.
Red/green:
required.

Requirement / claim:
Pierre Trees integration uses public exports, prepared/presorted input outside
React render, and controller-owned imperative mutations.
Proof source:
dependency export smoke, Trees controller tests, architecture boundary check.
Proof owner:
BridgeWeb unit/integration tests.
Stale-proof guard:
installed `@pierre/trees` exports are checked from current lockfile.
Proof layer:
unit, integration, build.
Red/green:
required for boundary and controller tests.

Requirement / claim:
Pierre CodeView integration uses uncontrolled/imperative production ownership,
stable item IDs, version bumps, and typed render/materialization cases.
Proof source:
CodeView adapter tests, `expectTypeOf` compatibility tests against Pierre
types, integration test rendering a mixed file/diff package.
Proof owner:
BridgeWeb unit/integration tests.
Stale-proof guard:
installed `@pierre/diffs/react` types are imported in tests.
Proof layer:
unit, type, integration.
Red/green:
required.

Requirement / claim:
Shiki highlighting runs through Pierre's worker pool from packaged WKWebView
assets, not from React render paths or dev-only Vite worker URLs.
Proof source:
worker factory tests, packaged build manifest, WKWebView smoke, worker stats
telemetry.
Proof owner:
BridgeWeb tests, Swift WebKit tests, parent smoke verification.
Stale-proof guard:
smoke reads the generated packaged app assets under
`Sources/AgentStudio/Resources/BridgeWeb/app`.
Proof layer:
unit, build, WKWebView smoke.
Red/green:
required for worker factory and packaged smoke.

Requirement / claim:
Content hydration stays on-demand and source-scoped through Swift-issued
content handles.
Proof source:
content queue/cache tests, integration package push test, Swift handler tests
if handle-resolution RPC is added.
Proof owner:
BridgeWeb and Swift Bridge tests.
Stale-proof guard:
active package id, review generation, item id, handle id, endpoint, role, and
candidate path are checked in tests.
Proof layer:
unit, integration, WebKit.
Red/green:
required.

Requirement / claim:
Viewer observability is debug-only, low-cardinality, source-scrubbed, and flows
BridgeWeb -> Swift -> OTLP/Victoria through the existing telemetry path.
Proof source:
BridgeWeb telemetry tests, Swift validator tests,
`mise run verify-bridge-observability`, no-direct-OTLP scan.
Proof owner:
BridgeWeb tests, Swift tests, parent observability proof.
Stale-proof guard:
debug run marker and Victoria query marker from the current worktree.
Proof layer:
unit, integration, smoke/observability.
Red/green:
required for validator allowlist additions.

Requirement / claim:
Large-tree and large-diff behavior is benchmarkable with Pierre-style fixed
workload, viewport, warmup, kept runs, scroll checksum, and raw metrics.
Proof source:
benchmark fixture builders, `mise run bridge-viewer-benchmark`, and viewer
benchmark artifacts for `bridge_viewer_large_tree_v1` and
`bridge_viewer_large_diff_scroll_v1`.
Proof owner:
implementation parent and benchmark verifier.
Stale-proof guard:
benchmark artifact names workload id, viewport, commit, package generation,
and trace/checksum fields.
Proof layer:
benchmark/manual performance gate.
Red/green:
deterministic fixture invariants are required; noisy browser trace timing is
reported as measured baselines, not used as a brittle CI wall-clock gate.

Requirement / claim:
The viewer opens docs/plan markdown files read-only as source text.
Proof source:
docs/plans fixture selection and CodeView/File render integration test.
Proof owner:
BridgeWeb integration tests.
Stale-proof guard:
fixture includes `.md` and plan/spec-like paths.
Proof layer:
integration.
Red/green:
required.

## Task Sequence

### Task 0: Plan And Spec Revalidation

Purpose:
confirm that the implementation begins from the current spec and current repo,
not stale BridgeWeb assumptions.

Work:

- Read the spec and this plan end to end before implementation.
- Confirm `BridgeWeb/package.json`, `.mise.toml`, `BridgeWeb/src`, and Swift
  Bridge tests still match the evidence above.
- Confirm installed Pierre package versions and public exports before importing
  them.
- Confirm whether the final spec-review lane has open blocker findings.

Proof:

- no code changes in this task
- implementation log records spec line count and repo evidence checked

Stop/replan:

- stop if LUNA-337 contracts are no longer present or renamed
- stop if BridgeWeb package layout has materially changed since this plan

### Task 1: BridgeWeb Dependency And Packaged Build Boundary

Purpose:
make the renderer dependencies and packaged asset path real before building UI.

Likely write surfaces:

- `BridgeWeb/package.json`
- `BridgeWeb/pnpm-lock.yaml`
- `BridgeWeb/tsconfig.json`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/vitest.config.ts`
- `BridgeWeb/index.html` or a generated HTML template that emits it
- `BridgeWeb/scripts/normalize-build-output.mjs`
- new `BridgeWeb/scripts/build-app-assets.mjs`
- new `BridgeWeb/scripts/write-app-asset-manifest.mjs`
- new `BridgeWeb/scripts/audit-dependencies-and-assets.mjs`
- `Sources/AgentStudio/Resources/BridgeWeb/app/**`
- `.mise.toml` for `bridge-web-build` and `bridge-web-audit`

Work:

1. Add pinned dependencies for `@pierre/diffs`, `@pierre/trees`, `zustand`, and
   `tsdown`.
2. Add export smoke tests for the installed public entrypoints:
   `@pierre/diffs`, `@pierre/diffs/react`, `@pierre/diffs/worker`,
   `@pierre/trees`, and `@pierre/trees/react`.
3. Spike the packaged build path first:
   - preferred: `tsdown` emits deterministic app JS, CSS if present, worker
     assets, and an asset manifest consumed by `agentstudio://app/*`
   - keep Vite only for dev/test if useful
   - prove `index.html`, asset paths, worker asset paths, and MIME expectations
     against `BridgeSchemeHandler`
   - preserve the runtime invariant that the pane loads
     `agentstudio://app/index.html`
   - rewrite the emitted app HTML script/style references from the asset
     manifest so packaged `index.html` points at built bundle assets, not
     `/src/app/bridge-app-bootstrap.tsx`
4. If tsdown cannot satisfy the packaged WKWebView requirements without a
   brittle custom pipeline, stop and replan the packaged build decision rather
   than silently reverting to dev-only Vite behavior.
5. Add a reproducible dependency and asset audit command:
   - records installed package versions and detected licenses from the current
     lockfile
   - records main JS/CSS asset sizes and worker asset sizes
   - writes an implementation proof artifact under `tmp/` or `docs/wip/`
   - fails on missing license metadata or missing packaged worker asset

Proof:

- `mise run bridge-web-check`
- `mise run bridge-web-test`
- `mise run bridge-web-build`
- `mise run bridge-web-audit`
- bundle/worker asset manifest exists and is normalized
- emitted `Sources/AgentStudio/Resources/BridgeWeb/app/index.html` exists,
  preserves the `agentstudio://app/index.html` entrypoint invariant, and points
  at built bundle assets
- `BridgeTransportIntegrationTests.test_schemeHandler_servesAppHtml`
- dependency export smoke tests pass
- license and bundle-size artifact records package versions, detected licenses,
  and pre/post build size totals

### Task 2: Architecture Boundary Discipline

Purpose:
make the state/effect/controller split enforceable before adding more code.

Likely write surfaces:

- `BridgeWeb/scripts/`
- `BridgeWeb/package.json`
- `BridgeWeb/.oxlintrc.json` if custom Oxlint JS plugins are viable
- `BridgeWeb/src/**/__fixtures__` or test fixtures for boundary violations
- `BridgeWeb/src/**/*.unit.test.ts`

Work:

1. Choose the enforcement mechanism after a small local spike:
   - custom Oxlint JS plugin rules if the installed Oxlint API is stable enough
   - otherwise a repo-local architecture checker script wired into
     `bridge-web-check`
   - do not make the implementation depend on an unstable alpha API without a
     fallback
2. Enforce these boundaries:
   - no Swift/RPC/content/worker/Pierre/telemetry effects from
     `review-viewer/state`
   - no `Worker` or `postMessage` outside `review-viewer/workers/rpc` or the
     Pierre worker factory
   - no `@pierre/trees` runtime imports outside `review-viewer/trees`
   - no CodeView runtime imports or imperative calls outside
     `review-viewer/code-view` and worker-pool setup
   - no `@pierre/*/dist/**`, non-exported Pierre subpaths, absolute local
     Pierre checkout paths, or type-only private Pierre imports anywhere in
     BridgeWeb
   - no telemetry emit calls outside `foundation/telemetry`
   - no raw loaded file bodies in Zustand slices
3. Add source fixtures or focused negative tests proving violations fail,
   including a negative fixture mirroring DiffsHub's private
   `packages/trees/dist/model/publicTypes` import pattern.

Proof:

- `mise run bridge-web-check`
- negative boundary test or script fixture fails before the checker is enabled
  and passes after the checker is wired
- no product code needs to import the checker

Commands:

- `mise run bridge-web-check`
- `mise run bridge-web-test`

### Task 3: Schema, Fixture, Projection, And Zustand Foundation

Purpose:
create the pure data layer that all renderer work uses.

Likely write surfaces:

- `BridgeWeb/src/review-viewer/state/**`
- `BridgeWeb/src/review-viewer/navigation/**`
- `BridgeWeb/src/review-viewer/workers/rpc/**`
- `BridgeWeb/src/review-viewer/test-support/**`
- `BridgeWeb/src/foundation/review-package/**` only for shared fixture helpers

Work:

1. Add Zod schemas and derived types for projection modes, refinements, facet
   counts, projection results, worker RPC envelopes, and materialization
   requests. Follow `xxxSchema`/`Xxx` naming.
2. Add deterministic fixture builders:
   - `tiny`
   - `bridge_viewer_medium_review_v1`
   - rename and duplicate-display-path cases
   - binary/large placeholder cases
   - docs/plans, tests, source, generated/vendor mix
3. Add the Zustand store with pure actions/selectors only. Store IDs, status,
   projection mode, refinement state, queue status, mounted IDs, worker status,
   and telemetry context. Do not store raw bodies or Pierre model instances.
4. Add projection builders for all base modes and refinements.
5. Add Bridge-owned worker RPC schemas and a projection worker client. Runtime
   worker methods produce production projection/filter/facet results only.
   Fixture generation remains test support. Requests must carry the full
   projection request, refinements, visible item IDs, optional `abortKey`, and
   stale-result identifiers; success responses must return ordered paths, item
   IDs, primary/secondary maps, and facet counts through a method-specific
   result schema.
6. Ship the worker lane in LUNA-338 with this required cutover rule:
   - sync path is allowed only when changed item count is <= 32, projected tree
     path count is <= 500, and no active search/filter/facet refinement is
     running over more than 500 paths
   - worker path is mandatory when changed item count is > 32, projected tree
     path count is > 500, any active search/filter/facet refinement runs over
     more than 500 paths, or the workload is `bridge_viewer_medium_review_v1`,
     `bridge_viewer_large_tree_v1`, or `bridge_viewer_large_diff_scroll_v1`
   - both paths must use the same schemas, cancellation/stale-result semantics,
     and telemetry context
7. Add deterministic worker-client stale-result tests:
   - request B replacing request A aborts or supersedes A by `abortKey`
   - out-of-order completion for stale `packageId`, `reviewGeneration`,
     `requestId`, or projection request fingerprint is ignored
   - ignored worker results do not overwrite Zustand projection state
8. Add selector tests that prove worker-stat/content-cache/hydration updates do
   not rerender the root shell subscription.

Proof:

- `mise run bridge-web-test`
- `mise run bridge-web-check`
- projection unit tests cover all modes and refinements
- worker RPC schemas accept valid projection requests and reject invalid
  responses without `z.unknown()` success payloads; tests include refinements
  and optional `abortKey`
- projection cutover tests cover both sides of the sync/worker threshold
- stale worker completions are discarded by current request identity before
  reaching Zustand state
- medium-review or large-tree proof exercises the worker path and emits worker
  measurement context through `foundation/telemetry`
- selector tests prove narrow subscriptions

Commands:

- `mise run bridge-web-check`
- `mise run bridge-web-test`

### Task 4: Trees Controller And Sidebar Review Controls

Purpose:
make the left review-control surface fast and projection-aware.

Likely write surfaces:

- `BridgeWeb/src/review-viewer/trees/**`
- `BridgeWeb/src/review-viewer/shell/**`
- `BridgeWeb/src/review-viewer/navigation/**`
- `BridgeWeb/src/review-viewer/state/**`

Work:

1. Implement `BridgeTreesController` over Pierre Trees public APIs.
2. Use `preparePresortedFileTreeInput(...)` outside React render after receiving
   ordered paths/maps from projections. For medium and large workloads, the
   expensive projection/search/facet shaping must already be in the Bridge-owned
   worker from Task 3. Treat worker-prepared `FileTreePreparedInput` as a later
   optimization unless the installed public Pierre API is proven structured
   clone safe in this implementation.
3. Add projection buttons: all, changed, guided, change set, docs/plans, tests,
   source.
4. Add tree search, Git-status filter menu, secondary facet menu, and compare
   selector display.
5. Implement reset/batch/status update policy:
   - hard package/generation/projection reorder: reset paths
   - proven append-only delta: batch add paths
   - status-only changes: status patch
6. Keep row selection mapped through `primaryItemIdByTreePath` and
   `secondaryItemIdsByTreePath`.

Proof:

- unit tests for reset/batch/status path decisions
- integration test for medium review fixture controls with no content fetch and
  no projection/search/facet shaping in React render
- large-tree fixture test proves raw bodies are not stored in Zustand
- architecture boundary checker rejects direct FileTree mutation elsewhere

Commands:

- `mise run bridge-web-check`
- `mise run bridge-web-test`

### Task 5: CodeView Controller, Materialization, And Content Hydration

Purpose:
make the right pane render mixed files/diffs without turning React state into
the data plane.

Likely write surfaces:

- `BridgeWeb/src/review-viewer/code-view/**`
- `BridgeWeb/src/review-viewer/content/**`
- `BridgeWeb/src/review-viewer/markdown/**`
- `BridgeWeb/src/review-viewer/shell/**`
- `BridgeWeb/src/foundation/content/**` if cache API needs extension

Work:

1. Implement `BridgeCodeViewController` with uncontrolled/imperative CodeView
   ownership: `initialItems`, `addItems`, `updateItem`, `updateItemId`,
   `setSelectedLines`, and `scrollTo`.
2. Add type tests proving Bridge render/materialization models are compatible
   with Pierre exported types.
3. Implement content hydration priorities:
   selected, visible, hovered, near-visible, guided-next.
4. Verify installed CodeView visible-range signals. Prefer public APIs. If no
   stable public signal is available, slice 1 hydrates selected/hover/guided
   first and records a follow-up for viewport-driven hydration.
5. Materialize file, patch diff, side-by-side diff, added/deleted, binary,
   large, and placeholder items with version/cache-key rules.
6. Render markdown/docs/plan files as source text through CodeView/File.
7. Preserve selected line/range only when the item and range still exist.

Proof:

- adapter unit/type tests
- content queue/cache unit tests
- integration test for selecting a file and fetching exactly once through
  `agentstudio://resource/content/{handleId}?generation=...`
- integration test for mixed file/diff package, added/deleted files, markdown
  source text, and placeholders
- large-diff fixture can select, scroll, collapse, expand, and update without
  pixel-offset hacks

Commands:

- `mise run bridge-web-check`
- `mise run bridge-web-test`

### Task 6: Shiki Worker Pool And Packaged WKWebView Proof

Purpose:
move syntax highlighting off the main thread and prove it in the packaged app,
not only in dev server.

Likely write surfaces:

- `BridgeWeb/src/review-viewer/workers/pierre/**`
- packaged build scripts/manifests from Task 1
- `Tests/AgentStudioTests/Features/Bridge/BridgeSchemeHandlerTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`

Work:

1. Add Pierre `WorkerPoolContextProvider` setup with render options and worker
   factory owned by `review-viewer/workers/pierre`.
2. Use `@pierre/diffs/worker/worker-portable.js` first.
3. Resolve packaged worker URL through the app asset manifest and
   `agentstudio://app/*`.
4. The worker manifest must record:
   - `assetPath`
   - resolved `agentstudio://app/*` URL
   - `workerKind`: `moduleWorker` or `classicWorker`
   - `source`: `packagedAppAsset`
   - `sha256` and byte size for the exact packaged asset
5. Add a blob fallback only for the vetted packaged worker asset if WKWebView
   rejects direct custom-scheme worker construction. The fallback may load bytes
   only from the manifest-resolved `agentstudio://app/*` worker asset. It must
   reject inline worker strings, external `http(s)` URLs,
   `agentstudio://resource/*`, repository content, markdown content, and
   telemetry payloads.
6. Add worker stats sampling in debug telemetry without making telemetry a
   hot-path dependency.
7. Treat Pierre's Shiki worker pool as page-local to each Bridge pane. Prove
   two mounted panes are isolated: tearing down pane A does not break pane B.
   Do not add cross-pane worker-pool singletons in Swift or BridgeWeb.

Proof:

- `mise run bridge-web-build`
- worker factory unit tests
- manifest parser tests prove `workerKind`, `source`, hash, and size are
  present
- fallback source-guard tests reject non-manifest, content, remote, and inline
  worker sources
- WKWebView smoke: packaged JS/CSS/worker assets load and a real highlight
  completes through both direct custom-scheme construction and forced fallback
- two-pane WebKit isolation test:
  pane A highlight succeeds, pane B highlight succeeds, pane A tears down, pane
  B completes another highlight and follow-up item update

Commands:

- `mise run bridge-web-check`
- `mise run bridge-web-test`
- `mise run bridge-web-build`
- `mise run test-webkit`

### Task 7: Swift Boundary, Handle Resolution, And Telemetry Validator

Purpose:
keep privileged source access and telemetry validation on the Swift side.

Likely write surfaces:

- `Sources/AgentStudio/Features/Bridge/Transport/Methods/ReviewMethods.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/**`
- `Tests/AgentStudioTests/Features/Bridge/**`
- `scripts/verify-bridge-observability.sh`

Work:

1. Start with existing content handles from `BridgeReviewItemDescriptor`.
2. Prove package descriptors' per-role handles are sufficient for slice 1. Do
   not add `review.resolveContentHandle` unless a concrete failing fixture shows
   a selectable package-backed row with no usable handle.
3. If that fixture exists, add `review.resolveContentHandle` as a contained
   sub-slice and validate package id, review generation, item id, endpoint,
   role, and candidate path. If the needed scope is broader than active-package
   descriptor validation, stop and replan.
   Required red/green: the fixture must fail without the RPC because the
   descriptor is selectable but has no usable handle, then pass with the minimal
   active-package-scoped RPC. Without that red fixture, the RPC is out of scope.
4. Add/extend Swift tests rejecting stale generations, unknown endpoints,
   arbitrary refs, raw filesystem paths, out-of-scope paths, and invalid roles
   only if the RPC is added.
5. Extend telemetry validator allowlists for viewer event names and attributes:
   projection build, prepared input, mode switch, search/filter, content queue,
   content cache, CodeView item update, scroll target, virtualized range, Shiki
   highlight, and worker task.
6. Extend closed telemetry vocabularies in
   `BridgeTelemetrySlice`, `BridgeTelemetryBatchValidator`, the BridgeWeb Zod
   telemetry schemas, and matching tests. This is a hard allowlist expansion,
   not a generic telemetry passthrough.
7. Keep the existing smoke scenario string
   `package_apply_content_fetch_v1` unless the observability spec is explicitly
   revised. The viewer adds required events under that scenario so existing
   marker-scoped Victoria queries stay comparable.
8. Add this LUNA-338 telemetry contract:

   - `performance.bridge.trees.projection_build`
     - verifier-required: yes
     - phase/data: `projection_build` / `data`
     - priority/slice/transport: `warm` / `review_projection` / `worker`
     - required bounded attrs: `fixture_class`, `item_count_bucket`,
       `tree_path_count_bucket`, `projection_kind`, `worker_lane`, `result`
   - `performance.bridge.trees.prepare_input`
     - verifier-required: unit/benchmark only until smoke exercises it
     - phase/data: `prepare_input` / `data`
     - priority/slice/transport: `warm` / `tree_prepare_input` / `swift`
     - required bounded attrs: `fixture_class`, `tree_path_count_bucket`,
       `projection_kind`, `result`
   - `performance.bridge.trees.mode_switch`
     - verifier-required: unit/integration only
     - phase/data: `mode_switch` / `control`
     - priority/slice/transport: `warm` / `review_projection` / `swift`
     - required bounded attrs: `projection_kind`, `result`
   - `performance.bridge.trees.search_filter`
     - verifier-required: unit/benchmark only
     - phase/data: `search_filter` / `data`
     - priority/slice/transport: `warm` / `review_projection` / `worker`
     - required bounded attrs: `fixture_class`, `query_class`,
       `tree_path_count_bucket`, `result`
   - `performance.bridge.viewer.content_queue`
     - verifier-required: yes
     - phase/data: `content_queue` / `data`
     - priority/slice/transport: `hot` / `content_fetch` / `content`
     - required bounded attrs: `content_priority`, `content_role`,
       `queue_depth_bucket`, `result`
   - `performance.bridge.viewer.content_cache`
     - verifier-required: unit/integration only
     - phase/data: `content_cache` / `data`
     - priority/slice/transport: `hot` / `content_fetch` / `content`
     - required bounded attrs: `cache_result`, `content_role`,
       `content_bytes_bucket`, `result`
   - `performance.bridge.pierre.item_update`
     - verifier-required: yes
     - phase/data: `item_update` / `data`
     - priority/slice/transport: `hot` / `code_view_item` / `swift`
     - required bounded attrs: `item_update_kind`, `item_count_bucket`,
       `result`
   - `performance.bridge.pierre.scroll_target`
     - verifier-required: unit/benchmark only
     - phase/data: `scroll_target` / `control`
     - priority/slice/transport: `hot` / `code_view_scroll` / `swift`
     - required bounded attrs: `scroll_target_kind`, `result`
   - `performance.bridge.pierre.virtualized_range`
     - verifier-required: benchmark only
     - phase/data: `virtualized_range` / `data`
     - priority/slice/transport: `hot` / `code_view_virtual_range` / `swift`
     - required bounded attrs: `diff_row_count_bucket`, `visible_row_bucket`,
       `result`
   - `performance.bridge.shiki.highlight`
     - verifier-required: yes
     - phase/data: `highlight` / `data`
     - priority/slice/transport: `hot` / `shiki_highlight` / `worker`
     - required bounded attrs: `language_class`, `content_bytes_bucket`,
       `worker_lane`, `result`
   - `performance.bridge.worker.task`
     - verifier-required: yes
     - phase/data: `worker_task` / `data`
     - priority/slice/transport: `warm` / `worker_task` / `worker`
     - required bounded attrs: `worker_task_kind`, `worker_lane`,
       `item_count_bucket`, `result`

   Every viewer event must still include the common required attributes
   `agentstudio.bridge.phase`, `agentstudio.bridge.plane`,
   `agentstudio.bridge.priority`, `agentstudio.bridge.slice`, and
   `agentstudio.bridge.transport`. Viewer-specific attrs must be closed
   vocabularies or numeric buckets only. Raw paths, item IDs, handle IDs,
   request IDs, hashes, source text, prompts, and raw errors remain forbidden.
9. Extend observability verifier to require the four smoke-visible viewer
   events marked above: `projection_build`, `content_queue`, `item_update`,
   `shiki.highlight`, and `worker.task`.
10. Keep `verify-bridge-web-no-direct-otlp.sh` passing.

Proof:

- `mise run test -- --filter BridgeTelemetryBatchValidator`
- focused Swift tests for handle resolution if added
- `mise run verify-bridge-observability` after debug launch
- no raw path/content/prompt/error strings in OTLP samples

Commands:

- `mise run test -- --filter BridgeTelemetryBatchValidator`
- `mise run test -- --filter BridgeSchemeHandler`
- `mise run bridge-web-check`
- `mise run verify-bridge-observability` after the env-prefixed debug launch in
  Task 9

### Task 8: Viewer Benchmark And Performance Proof

Purpose:
prove the viewer can scale beyond demos and capture useful baselines.

Likely write surfaces:

- `BridgeWeb/src/review-viewer/test-support/**`
- `BridgeWeb/src/review-viewer/**/*.benchmark.*` if used
- `.mise.toml`
- new `scripts/verify-bridge-viewer-benchmark.sh`
- `Tests/AgentStudioTests/Features/Bridge/**` or benchmark tests if the harness
  is Swift/WebKit-owned
- `tmp/` or `docs/wip/` proof artifacts generated by the run

Work:

1. Add deterministic workload builders:
   - `bridge_viewer_medium_review_v1`
   - `bridge_viewer_large_tree_v1`
   - `bridge_viewer_large_diff_scroll_v1`
2. CI-safe tests assert bounded behavior and invariants, not flaky wall-clock
   browser timing.
3. Add a benchmark route/harness only after the relevant UI surface exists.
4. Follow Pierre's DiffsHub benchmark runbook shape:
   fixed workload, fixed viewport, stable-page checks, one warmup, three kept
   runs, deterministic scroll writes, checksum, raw metrics, and machine-state
   notes.
5. Add `mise run bridge-viewer-benchmark` as the named viewer benchmark gate.
   It may call existing Swift/WebKit benchmark infrastructure internally, but it
   must emit viewer-owned artifacts for `bridge_viewer_large_tree_v1` and
   `bridge_viewer_large_diff_scroll_v1`.
6. Report large-tree and large-diff performance targets as measured baselines
   in the first implementation PR. Do not invent hard pass/fail numbers before
   the packaged WKWebView route and variance policy exist.

Proof:

- CI-safe medium-review tests
- benchmark artifact with workload id, viewport, runs, checksum, raw metrics,
  and commit/worktree identity
- `mise run bridge-viewer-benchmark`

Commands:

- `mise run bridge-web-test`
- `mise run bridge-viewer-benchmark`

### Task 9: App Integration, Visual/WKWebView Smoke, And Final Gates

Purpose:
cut over the existing minimal Bridge shell to the real viewer and prove it in
the app runtime.

Likely write surfaces:

- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/app/**.integration.test.tsx`
- `BridgeWeb/src/review-viewer/shell/**`
- `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
- `Tests/AgentStudioTests/Features/Bridge/WebKitSerializedTests.swift`
- docs/proof artifact under `docs/wip/` or `tmp/`

Work:

1. Replace the minimal app-local state with the viewer store/controllers.
2. Preserve handshake, push receiver, RPC client, telemetry recorder, and
   content loader behavior.
3. Ensure package pushes do not include file bodies.
4. Ensure selection/content fetch still works through resource URLs.
5. Add a package-backed viewer smoke scenario with:
   - projection buttons visible
   - tree controls visible
   - selectable file tree
   - CodeView rendering
   - markdown source rendering
   - worker-backed highlight proof
   - telemetry proof
6. Visually verify the launched debug app pane if UI changes land in this
   implementation slice.

Proof:

- `mise run bridge-web-check`
- `mise run bridge-web-test`
- `mise run bridge-web-build`
- `mise run test -- --filter Bridge`
- `mise run test-webkit`
- `mise run lint`
- `mise run observability:up`
- env-prefixed debug launch:

```bash
AGENTSTUDIO_TRACE_TAGS=app.startup,terminal.startup,runtime,surface,persistence.recovery,bridge.performance.* \
AGENTSTUDIO_TRACE_BACKEND=both \
AGENTSTUDIO_TRACE_NAME=bridge-viewer-$(date +%s) \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO=package_apply_content_fetch_v1 \
mise run run-debug-observability -- --detach
```

- `mise run verify-bridge-observability`
- `mise run bridge-viewer-benchmark`

### Task 10: Semantic Bridge IPC Capability And E2E Proof

Purpose:
use the merged AgentStudio IPC foundation for headless Bridge testing and future
agent control without turning BridgeWeb into the IPC subsystem.

Likely write surfaces:

- `Sources/AgentStudioProgrammaticControl/IPCBridgeContracts.swift` or adjacent
  IPC contract files
- `Sources/AgentStudioProgrammaticControl/IPCContracts.swift`
- `Sources/AgentStudioProgrammaticControl/IPCEventContracts.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift` only for port
  shape if needed
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCBridgeAdapter.swift`
- `Sources/AgentStudio/Features/Bridge/**` only for explicit capability ports
  and runtime/controller seams
- `Sources/AgentStudioIPCClientCore/**` only if the CLI needs first-class
  bridge verbs for e2e proof
- `Tests/AgentStudioAppIPCTests/**`
- `Tests/AgentStudioProgrammaticControlTests/**`
- `Tests/AgentStudioTests/App/IPC/**`
- `Tests/AgentStudioTests/Features/Bridge/**`
- `docs/architecture/agentstudio_ipc_architecture.md` after implementation

Work:

1. Keep BridgeWeb as a pane renderer. IPC targets Bridge the product
   capability, then the Bridge owner decides whether to push WebKit state,
   refresh package state, read cached metadata, or resolve content handles.
2. Add a Bridge capability port under `AgentStudioAppIPC` and a concrete
   `AgentStudioIPCBridgeAdapter` under app IPC composition. The reusable IPC
   target owns policy and port protocols only; concrete Bridge controller,
   pane, runtime, and app-state imports belong in the app composition adapter or
   Bridge feature owners.
3. Add typed public IPC contracts for the first semantic methods. Preferred
   initial surface:
   - `bridge.review.open`
   - `bridge.review.refresh`
   - `bridge.review.getPackage`
   - `bridge.review.selectFile`
   - `bridge.review.markViewed`
   - `bridge.content.get`
   - `bridge.telemetry.flush`

   If a method lacks a real product owner in this slice, do not stub it as a
   fake success. Leave it out of the method catalog and record the follow-up.
4. Extend capability-scoped authorization with closed privilege/data scopes for
   Bridge, for example:
   - `bridgeRead` for review package metadata, selected item, and status
   - `bridgeContentRead` for content-handle reads
   - `bridgeControl` for refresh, select file, mark viewed, and open
   - `bridgeTelemetryRead` for Bridge health summaries
   - `bridgeTelemetryFlush` for explicit telemetry flush

   Use the repo's actual `IPCPrivilegeClass`, `IPCDataScope`, and
   `IPCPermissionScope` model. Do not implement stringly permission atoms
   outside those closed enums.
5. Resolve targets through IPC handles before touching Bridge:
   - active/current pane when the IPC target model supports it
   - `pane:<id>` and friendly pane handles
   - optional `surface:<id>` only if the IPC handle model is explicitly extended

   The resolver must prove the target is a live Bridge pane. Non-Bridge panes
   fail with a typed unsupported-target error, not fallback magic.
6. Prefer stable Bridge content handles over raw paths. `bridge.review.getPackage`
   may return package item metadata and handles; `bridge.content.get` validates
   the handle, package id, review generation, role, and content bounds before
   returning content. Raw filesystem paths, arbitrary refs, and private hashes
   must not cross IPC.
7. Add Bridge IPC events as notifications only, not command routing:
   - `bridge.review.updated`
   - `bridge.file.selected`
   - `bridge.content.ready`
   - `bridge.telemetry.sampled`

   Events describe facts after Bridge owners mutate state. IPC requests must
   still go through method registry, authorization, target resolution, and
   capability ports.
8. Keep command/UI separation:
   - do not make `command.execute` open Bridge through command-bar UI
   - do not make Bridge IPC call `ui.commandBar.open`
   - if `bridge.review.open` is added, it routes to the same semantic owner as
     `ActionExecutor.openBridgeReview()` or a narrower Bridge pane-opening port
9. Add app/IPC tests proving:
   - method catalog lists only the implemented `bridge.*` semantic methods
   - generic WebKit/raw-post/event-bus methods are not present
   - target resolution accepts Bridge panes and rejects terminal/webview panes
   - pane-bound principals can access their own Bridge pane only by default
   - unauthorized pane agents cannot read another pane's Bridge content
   - `command.execute` does not present command-bar UI for Bridge behavior
10. Add debug IPC e2e proof after the viewer surface is mounted:
   - create/open a Bridge pane
   - refresh or load a review package
   - list current package/files
   - select a file headlessly
   - fetch selected file/diff content through a content handle
   - observe a Bridge update/selection/content event
   - verify no command-bar UI was opened
   - verify unauthorized cross-pane Bridge content read is rejected

Proof:

- `mise run test -- --filter IPCContracts`
- `mise run test -- --filter AgentStudioAppIPC`
- `mise run test -- --filter AgentStudioIPCBridge`
- debug IPC e2e/smoke command once the CLI or JSON-RPC harness has Bridge verbs
- `mise run lint`

Commands:

- `mise run test -- --filter IPCContracts`
- `mise run test -- --filter AgentStudioAppIPC`
- `mise run test -- --filter AgentStudioIPCBridge`
- `mise run lint`

## Validation Pyramid

Unit:

- projection builders
- schema decode/encode and Zod naming
- worker RPC request/response parsing
- content queue/cache
- CodeView materialization/version/cache keys
- Trees controller update decisions
- architecture boundary checker
- telemetry validator allowlist
- Bridge IPC contract DTOs and method definitions
- Bridge IPC authorization scopes and target resolver unsupported-target cases

Integration:

- BridgeWeb package push -> projection controls -> tree -> selection
- content fetch exactly once for selected item
- mixed file/diff CodeView render
- docs/plan markdown source render
- medium-review fixture projections/filters with no eager content fetch
- large-tree projection/Tree model without raw bodies in Zustand
- multi-pane worker-pool isolation
- Bridge IPC adapter resolves Bridge panes and rejects non-Bridge panes
- Bridge IPC content reads validate handles instead of raw paths
- Bridge IPC event notifications are emitted only after Bridge-owned state
  changes

Smoke / WebKit:

- packaged BridgeWeb app assets load from `agentstudio://app/*`
- packaged Pierre worker loads and highlights inside WKWebView
- selected resource content loads from `agentstudio://resource/content/...`
- debug app smoke shows the viewer without breaking existing Bridge shell
- debug IPC e2e opens/targets Bridge, selects a file, fetches content, observes
  Bridge events, and proves command-bar UI was not used

Benchmark:

- deterministic medium-review CI-safe invariants
- large-tree and large-diff benchmark baselines with Pierre-style trace shape
- `mise run bridge-viewer-benchmark`

Observability:

- BridgeWeb `.web` viewer samples flow through Swift `system.bridgeTelemetry`
- Swift validator rejects high-cardinality/raw samples
- Victoria proof queries current debug run marker and viewer signals

## Stop Conditions

- Stop if the installed Pierre package exports differ from the spec assumptions.
- Stop if tsdown cannot produce a packaged worker/app asset shape that works in
  WKWebView; return to spec/plan before coding around it.
- Stop if CodeView has no public visible-range signal and the implementation
  would require brittle DOM scraping; narrow slice 1 hydration and record the
  follow-up instead.
- Stop if handle resolution requires broader source-provider APIs than active
  package item/endpoint/path validation.
- Stop if Bridge IPC would require exposing raw WebKit evaluation/post-message,
  EventBus command routing, raw filesystem paths, or command-palette UI
  automation. Return to spec/design and add a semantic Bridge capability port
  instead.
- Stop if benchmark proof cannot be wired at the task size; split benchmark
  route/harness work rather than weakening the proof gate.
- Stop before any source mutation, annotation persistence, editor behavior, or
  general endpoint tree browser work.

## Risks And Mitigations

- Risk: Zustand becomes the hot data plane.
  Mitigation: pure store actions, controller-owned effects, selector tests,
  raw-body boundary checks, debug write/rerender counters.
- Risk: worker path works in dev but fails in packaged WKWebView.
  Mitigation: packaged asset manifest and WKWebView smoke before completion.
- Risk: Pierre internals leak into Bridge contracts.
  Mitigation: public export smoke tests and `expectTypeOf` adapter tests only.
- Risk: large-diff performance is asserted from small fixtures.
  Mitigation: explicit medium/large fixture ladder plus benchmark artifacts.
- Risk: telemetry steals resources or leaks source data.
  Mitigation: debug-only batching, closed validator, no direct OTLP, no raw
  paths/content/errors/prompts. Viewer modules produce measurement context;
  `foundation/telemetry` is the only BridgeWeb telemetry emitter.
- Risk: plan becomes too large to prove in one PR.
  Mitigation: implementation may land as stacked PRs only if each task preserves
  the hard cutover inside its owned boundary and has independent proof.

## Open Questions For Implementation

- Does the installed Pierre package expose a stable visible-range signal good
  enough for selected/visible hydration in slice 1?
- Can local `oxlint` support custom JS rules reliably enough, or should the
  first implementation use a repo-local architecture checker script and leave
  Oxlint plugin migration as a follow-up?
- Should the viewer benchmark route be BridgeWeb-only, WKWebView-owned, or
  driven through the existing Swift `test-benchmark` lane?
- Are existing descriptor content roles sufficient for slice 1, or is
  `review.resolveContentHandle` required?
- Should Bridge IPC extend the handle model with an explicit active/current
  pane target and/or `surface:<id>`, or should slice 1 accept only existing
  `pane:<id>` and friendly pane handles?
- Which initial `bridge.*` methods have real product owners in this slice, and
  which should remain out of the method catalog until the owner exists?

## Next Workflow

Run `shravan-dev-workflow:implementation-execute-plan` under
`shravan-dev-workflow:orchestrator-goal`. Start with Task 0, then execute the
tasks in order. Do not skip the dependency/export, packaged WKWebView,
observability, benchmark, semantic IPC, and boundary-check proof gates.

## Handoff Prompt

```text
Required workflow skill: shravan-dev-workflow:orchestrator-goal
Next workflow: shravan-dev-workflow:implementation-execute-plan

Goal: Execute the reviewed LUNA-338 implementation plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start
Plan: docs/plans/2026-06-15-bridge-codeview-trees-shiki-review-viewer.md
Spec: docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md

Required reading:
- docs/plans/2026-06-15-bridge-codeview-trees-shiki-review-viewer.md
- docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md
- BridgeWeb/package.json
- BridgeWeb/src/app/bridge-app.tsx
- BridgeWeb/src/foundation/**
- BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx
- Sources/AgentStudioProgrammaticControl/IPC*.swift
- Sources/AgentStudioAppIPC/**
- Sources/AgentStudio/App/IPCComposition/**
- docs/architecture/agentstudio_ipc_architecture.md
- .mise.toml BridgeWeb/test-webkit/test-benchmark/observability tasks
- Pierre reference files listed in the plan's Source Coverage section

Execution gates:
- start with Task 0 revalidation
- keep BridgeReviewPackage / BridgeReviewDelta / content handles Bridge-owned
- use installed public Pierre package exports only
- preserve agentstudio://app/index.html packaged entrypoint
- enforce Zustand/effect/controller boundaries
- keep package pushes metadata-only and content hydration on demand
- prove packaged Shiki worker loading in WKWebView
- expand debug-only telemetry through Swift validator and Victoria proof
- add and run bridge-viewer-benchmark before closing implementation
- after the merged IPC foundation is present, add semantic Bridge IPC methods
  through typed ProgrammaticControl contracts, AppIPC ports, and app composition
  adapters; do not expose raw WebKit/postMessage/EventBus command routes
- prove Bridge IPC e2e can open/target Bridge, select/fetch content, observe
  Bridge events, and reject unauthorized cross-pane reads without opening
  command-bar UI

Do not add source editing, patch apply, annotation persistence, direct browser
OTLP, cross-pane worker-pool singletons, package-private Pierre imports, or
parallel old/new Bridge contract models. Do not expose generic IPC methods such
as `webview.evaluateJavaScript`, `bridge.rawPostMessage`, `eventBus.publish`, or
`zmx.*`.
```
