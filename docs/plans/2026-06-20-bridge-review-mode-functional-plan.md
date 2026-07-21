# Bridge Review Mode Functional Plan

Status: reviewed plan for implementation-execute-plan
Goal id: 2026-06-20-bridge-review-mode
Created: 2026-06-20

## Goal

Deliver a PR-ready, read-only AgentStudio Review pane that can review the
current large Bridge worktree with a DiffsHub-class experience, AgentStudio
styling, typed resource loading, worker-backed rendering, semantic IPC control,
Victoria-backed performance proof, and a clean BridgeWeb/Swift separation.

The terminal condition is PR-ready, not merged:

- implementation complete for the scoped vertical slice
- unit, integration, browser, dev-server, native, performance, lint, typecheck,
  build, implementation-review, and PR-readiness gates pass or are explicitly
  scoped with evidence
- implementation review findings are addressed or explicitly rejected with
  rationale
- a PR is opened or updated and current checks, review threads, and mergeability
  are reported
- no merge is performed by this plan

## Non-Goals

- no source mutation, patch apply, approve/reject, or write-back review actions
- no Monaco/editor surface
- no new SQLite/persistence store work
- no broad repo explorer beyond the review/file-tree/file-view contracts
- no generic WebKit evaluation, raw postMessage, or command-palette-driving IPC
- no IPC-returned hot file, diff, or markdown bodies
- no generated app resource bundles checked into source control

## Source Coverage

The plan is based on whole-artifact review of the accepted specs and supporting
plan:

| Source | Lines | Role |
| --- | ---: | --- |
| `docs/superpowers/specs/2026-06-20-bridge-resource-data-plane.md` | 636 | Canonical resource data-plane, cache, Zustand, worker, and security contract |
| `docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md` | 2068 | Canonical Review viewer, Pierre CodeView/Trees, IPC, markdown, proof contract |
| `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md` | 648 | Canonical DiffsHub/shadcn/Catppuccin fast-loop UX and proof contract |
| `docs/plans/2026-06-18-bridgeweb-large-diff-fast-loop-remediation.md` | 1349 | Supporting historical remediation notes and known partial implementation state |

This file supersedes the old remediation plan as the execution contract for the
goal. Keep the older plan as historical evidence unless this plan explicitly
points to it.

## Current Repo Evidence

Observed current state before implementation:

- BridgeWeb already has a substantial partial implementation under
  `BridgeWeb/src/review-viewer`.
- Current folder names still include `BridgeWeb/src/review-viewer/runtime` and
  `BridgeWeb/src/review-viewer/workers/rpc`. The accepted spec rejects vague
  `runtime` ownership and says feature-owned workers live under named feature
  lane folders such as `workers/projection`, `workers/markdown`,
  `workers/pierre`, and `workers/shared-rpc`.
- Large files already need responsibility splits before more behavior is added:
  - `BridgeWeb/src/app/bridge-app.tsx`: 1248 lines
  - `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`: 929 lines
  - `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx`: 1069 lines
- BridgeWeb package scripts already include check, build, browser, benchmark,
  dev-server, worktree-dev-server, visual-proof, and asset-audit commands.
- `.mise.toml` already exposes `bridge-web-install`, `bridge-web-check`,
  `bridge-web-test`, `bridge-web-browser-test`,
  `bridge-web-browser-benchmark`, `bridge-web-build`, and
  `bridge-web-audit`.
- The current working tree has uncommitted diagnostic changes:
  - `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`
  - `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
  - `BridgeWeb/vitest.browser.config.ts`
  - `BridgeWeb/scripts/bridge-viewer-hydration-diagnostics.ts`
  - `BridgeWeb/scripts/bridge-viewer-hydration-diagnostics.unit.test.ts`
  These must be inspected and either incorporated, reshaped, or discarded
  deliberately before implementation commits.
- The current dev-server worktree path is looser than the accepted spec:
  `BridgeWeb/src/app/bridge-app-dev-worktree.ts` and
  `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts` accept
  request URL `worktree`, `repo`, and `base` style overrides. The accepted
  contract requires named, allowlisted local scenarios for reproducible
  real-worktree proof.
- The current [Bridge Viewer](../architecture/bridge_viewer_architecture.md),
  [native runtime](../architecture/bridge_native_runtime_architecture.md), and
  [web runtime](../architecture/bridge_web_runtime_architecture.md) architecture
  docs must stay aligned as resource windows and feature-owned registries evolve.
- Current IPC surfaces still include older or transitional Bridge content body
  methods such as `bridge.fileView.getContent` and markdown body helpers. The
  Review viewer must not expand those as a hot body path. This PR removes that
  path for Review instead of keeping backward compatibility: control IPC belongs
  under the Review/Bridge capability, and all hot Review bodies move through
  `agentstudio://resource/*`.
- Current visual proof tooling is useful but not yet authoritative enough by
  itself: `BridgeWeb/scripts/capture-bridge-viewer-dev-visual-proof.ts` still
  uses fixed waits in places. Replace those with event/DOM waits before
  `proof:visual:dev-server` is treated as a hard visual acceptance gate.
- Current CodeView motion still differs from DiffsHub for large diffs. Video
  review of DiffsHub versus the Bridge dev server showed Bridge can issue
  multiple scroll/reveal operations for one selected file: an app-level
  pre-scroll, a selected-item CodeView reveal, a hydration-time re-scroll, and
  layout correction frames. DiffsHub performs one item reveal for the selection,
  then lets CodeView keep the sticky header stable. Task 5 must remove duplicate
  scroll authority, prevent content hydration from re-scrolling an already
  revealed selected header, and add browser proof that file selection, visible
  hydration, and collapse/expand do not produce jumpy motion.
- Current markdown-file selection has a separate click-vs-scroll bug. Manual
  dev-server proof showed that scrolling to a new markdown file can stay in the
  expected DiffsHub-style CodeView, while clicking the markdown file from the
  tree can jump the viewer to a file/markdown-render path and a surprising
  scroll position. Task 5/6 must keep CodeView as the primary review surface
  during file selection, and markdown preview must be an explicit render-mode
  request or review mode, not an accidental side effect of tree selection.
- Markdown-click root-cause checkpoint: source review and browser proof showed
  normal file/tree selection does not enter markdown preview on its own; only
  the explicit `bridge.fileView.showMarkdownPreview` command flips render mode.
  The observed docs-click bug was a reveal/anchor bug. Current implementation
  keeps app-owned reveal for normal file selection, but narrows it to one
  CodeView control call using Pierre's `smooth-auto` behavior. Explicit markdown
  preview selection suppresses CodeView reveal so the preview mode does not race
  a stale CodeView scroll. Live dev-server proof after the fix measured selected
  source tree-click offset at `-4px`, source command-reveal offset at `-4px`,
  and docs command-reveal offset at `+4px` on the large DiffHub fixture, with no
  markdown preview flip and no CodeView unknown-item warnings. DiffsHub motion
  polish and full visual comparison remain open until the visual proof gate.
- Loading skeleton correction checkpoint: manual video proof showed detached
  skeletons floating outside CodeView row geometry during scroll/hydration. The
  active direction is now row-owned loading materialization only: loading content
  must occupy the same CodeView item body slot that later renders the real
  file/diff content, with no absolute overlay path reintroduced.
- Smooth selection-motion checkpoint: unit proof now covers the specific
  DiffsHub mismatch where an interactive file-tree reveal asked CodeView for a
  smooth item scroll but Bridge immediately scheduled its own repeated
  `requestAnimationFrame` header-top correction. Smooth reveals must delegate
  motion to Pierre CodeView; Bridge's direct header correction stays limited to
  instant recovery and initial-selection paths.
- Motion-proof checkpoint: the large dev-server verifier now samples CodeView
  `scrollTop` over animation frames after a file-tree click and emits
  `selectedScrollMotion` in the proof JSON. The gate rejects zero movement,
  too-few scrollTop values, large single-frame top-snap jumps for long moves,
  and unstable direction changes, so future visual work has a numeric guardrail
  before screenshot/manual comparison.
- Collapse-anchor checkpoint: file-header collapse/expand now settles any
  in-flight Pierre smooth scroll at the current scroll position before applying
  the item layout update, then restores the header anchor across layout frames.
  The large dev-server verifier must keep the selected header within the pinned
  top band after both collapsed and expanded states.
- 2026-06-22 reveal/markdown checkpoint: the current patch changes normal
  Review file selection to use one Pierre CodeView `smooth` item reveal instead
  of Bridge-owned top-snap correction, adds a dev-server verifier gate for
  direct markdown selection motion, and fixes explicit
  `bridge.fileView.showMarkdownPreview` so one command can select an
  off-selection docs item and keep the pending render mode as markdown preview
  while content/worker output arrives. Focused unit/integration/browser proof is
  green for this slice, but this is not final Review completion.
- 2026-06-22 filter/mode gap: production still has the old facet/menu shape and
  does not yet implement the accepted compact review-mode segmented control,
  unified Git/file/scope/search/regex filter popover, or semantic control
  command coverage for those facets. This remains Task 3/4 work and must not be
  counted as done because the dev-server UI happens to render.
- Current Victoria verifier coverage is strong for the existing Bridge telemetry
  taxonomy, but the new resource data-plane names
  `performance.bridge.resource.fetch/cache/range`,
  `performance.bridge.viewer.visible_window`, and
  `performance.bridge.controller.apply` must be added only after those emitters
  exist. Verifier churn should follow product telemetry, not lead it.
- 2026-06-22 live worktree checkpoint: the dev server was listening on
  `127.0.0.1:5173`, and both the worktree URL
  `/?fixture=worktree&workers=on&scenario=current-worktree` and the mock URL
  `/?fixture=large-diffshub&workers=on&scenario=scroll` returned HTTP 200.
  This only proves the server is reachable; it does not prove the selected
  viewer state is correct.
- 2026-06-22 worktree content-unavailable fix: headless browser proof showed
  the failure was global for worktree content, not limited to one file. The
  browser forwarded `scenario=current-worktree` on
  `/__bridge-worktree/content/*` requests, while the Vite content route only
  accepted `generation` and `revision`, so every scenario-qualified content
  request returned 400 before reaching the provider. The route now allows
  optional `scenario` as routing context while keeping `generation` and
  `revision` required. Proof is green for
  `scripts/bridge-worktree-vite-route.unit.test.ts` and
  `pnpm --dir BridgeWeb run test:dev-server:worktree`, which reports selected
  content `ready`.
- 2026-06-22 search/regex blocker: the visible search and regex controls are
  still not functionally complete in the live dev-server UI. Headless proof can
  toggle the regex button from `Use regex search` to `Use text search`, but
  clicking `Search files` does not reveal a visible/editable search input, so
  filtering cannot be driven from the current chrome. Add browser reproduction
  for clickability, facet state changes, regex-mode behavior, and
  worker/projection output before claiming Task 3/4 filter completion.
- 2026-06-22 resource item-window boundary: TypeScript-side parsing, window
  budgeting, and registry code exist for
  `agentstudio://resource/review-items`, but native AgentStudio scheme-handler
  proof and semantic `bridge.review.prepareWindow` RPC proof are not yet green.
  Do not describe item-range/resource-window work as fully implemented until
  both the native route and RPC path are exercised through real Bridge IPC.
- 2026-06-22 scroll-boundary wording: specs and code discuss hydration/tree
  overscan and CSS overscroll containment. The separate underscroll/edge-blank
  behavior is not yet a named proof gate. Add a scroll-boundary proof that
  checks top/bottom edge anchoring, no blank underfill, and no duplicate
  Bridge-owned correction loops before marking DiffsHub parity complete.
- 2026-06-22 delegated proof note: the requested headless-browser and
  Vitest/Playwright subagent lanes failed before running because the subagent
  access token could not be refreshed after an account/session change. The main
  executor must run those local proof gates directly until delegation is
  available again.

## 2026-06-22 Major Blockers And Fix Order

- [x] 1. Restore local proof visibility: keep the dev server reachable at the
  worktree and mock URLs, then run the browser investigation locally while
  subagent delegation is unavailable.
- [x] 2. Reproduce and fix worktree `Content unavailable`. Root cause was the
  Vite worktree content route rejecting scenario-qualified content requests.
  Proof: route unit test, route-level curl 200, headless page
  `unavailableCount: 0`, and `test:dev-server:worktree` selected content
  `ready`.
- [ ] 3. Reproduce and fix search/regex controls. Prove input, regex toggle,
  invalid-regex handling, worker/projection output, and visible UI state on the
  large fixture.
- [ ] 4. Finish Task 5 scroll/motion parity only after the two functional
  blockers above are isolated. Preserve the current `smooth-auto` far-reveal
  gate, then add explicit top/bottom no-underfill scroll-boundary proof.
- [ ] 5. Close the resource-window contract: native
  `agentstudio://resource/review-items` handling plus
  `bridge.review.prepareWindow` RPC proof through real Bridge IPC.
- [ ] 6. Re-run the full BridgeWeb proof floor:
  `pnpm --dir BridgeWeb run test:browser:integration`,
  `pnpm --dir BridgeWeb run test:dev-server`, and
  `pnpm --dir BridgeWeb run test:dev-server:worktree`. Extend the worktree gate
  to cover the failing added TypeScript path before using it as closing proof.
- [ ] 7. Continue native AgentStudio blank-pane and Victoria metrics proof only
  after the browser/worktree surface is no longer functionally broken.

## Product Requirements

R1. Review pane modes are task modes, not file filters:

- `normalReview`
- `guidedReview`
- `plansAndSpecs`

Git status, file kind, docs/plans, tests, source, folder/path, extension,
language, search, regex, visibility, and change-set scope are facets over the
selected mode.

R2. The browser/dev-server surface must be visually close to DiffsHub on
Catppuccin Mocha, with AgentStudio/shadcn/Base UI control primitives:

- right-side file tree rail
- compact icon-first controls
- no detached black mode strip
- no native-looking selects
- no bespoke one-off Tailwind controls when a shadcn/Base UI primitive applies
- Catppuccin Mocha tokens mapped through shadcn/Tailwind v4 CSS variables
- Pierre CodeView and Trees themed to the same dark review grammar

R3. Large real-worktree review must be fast enough to be usable:

- file click scrolls quickly to the selected file header
- selection does not cause blank content
- collapse/expand does not jump unexpectedly
- sticky file headers behave like DiffsHub
- added files show full content, not empty rows
- markdown docs/plans render sanitized read-only preview
- large projection/search/facet work stays off the main thread

R4. Data loading uses the Bridge resource data plane:

- all hot package window, tree, file, diff, and markdown body reads go through
  `agentstudio://resource/*`
- IPC/control commands can prepare windows and expose resource handles, but do
  not return hot bodies
- item windows use Swift-issued cursor tokens when Swift owns order, or explicit
  bounded item-id lists when BridgeWeb owns the projected order
- unknown, duplicate, mixed-family, or non-canonical resource query keys fail
  closed
- already cached current-generation content is not requested again

R5. Zustand is the typed UI index, not the content store:

- Zustand may keep selected package refs, revision, mode, facets, selected item,
  mounted item IDs, worker status, cache keys, request IDs, and render status
- raw file bodies, markdown HTML, prepared Pierre items, tree prepared input,
  CodeView handles, FileTree handles, and worker manager instances live in
  feature-owned closure registries/controllers with explicit reset/eviction
- Zustand actions remain pure: no Swift calls, fetches, worker posts, Pierre
  mutation, telemetry emission, or heavy parse work

R6. Feature-owned workers live under the feature:

- `BridgeWeb/src/review-viewer/workers/pierre`
- `BridgeWeb/src/review-viewer/workers/projection`
- `BridgeWeb/src/review-viewer/workers/markdown`
- `BridgeWeb/src/review-viewer/workers/shared-rpc` only for generic typed
  transport used by at least two review-viewer lanes

Do not add app-wide worker managers or generic `runtime` folders for this
feature.

R7. Semantic IPC controls Review as a product capability:

- `bridge.review.*` for load, refresh, package metadata, selection/reveal, and
  prepare-window control
- `bridge.fileTree.*` for tree search, facets, expansion, and reveal
- `bridge.fileView.*` for source/markdown render-mode requests
- `bridge.telemetry.*` for debug flush/snapshot proof

IPC target resolution must land on a Bridge/Review pane and fail typed
unsupported-target for other panes. IPC does not expose raw WebKit or raw
content-body shortcuts.

`bridge.review.*` is a hard namespace cutover for Review control in this
slice. Old `bridge.diff.*` review-control names and old direct body-returning
Review IPC methods are removed, not aliased.

R8. Observability is a first-class proof path:

- dev-server debug mode may emit OTLP/Victoria metrics when configured
- native proof must emit Victoria metrics/logs for package push, resource fetch,
  cache hit/miss, worker task, tree render/search/reveal, file select,
  CodeView hydration/render, markdown render, scroll responsiveness, and IPC
  actions
- telemetry must be low-cardinality and source-scrubbed

## Requirements And Proof Matrix

| Req | Owning tasks | Proof owner | Gate | Layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| R1 modes vs facets | 3, 4, 8 | executor | component/unit + browser mode assertions | unit + browser | test asserts modes are only normal/guided/plans and filters are facets | yes |
| R2 DiffsHub-class shadcn/Catppuccin UI | 4, 7 | executor + reviewer | visual proof side-by-side, component tests, bbox probes | unit + browser + visual | fresh DiffsHub reference crop and current dev-server screenshot in artifact | yes |
| Visual proof is event-driven | 7 | executor | visual script proof transcript or integration test | browser + visual | fixed waits are removed or non-authoritative; DOM/events gate capture timing | yes |
| R3 large real-worktree usability | 2, 5, 7, 9 | executor | dev-server worktree verifier, browser benchmark, native debug proof | browser + performance + native | uses current branch worktree scenario and records package fingerprint/fixture id | yes |
| R3 file click scrolls to header | 5, 7 | executor | Vitest Browser Mode click-to-file test | browser | selected path visible at sticky threshold, not merely selected in tree | yes |
| R3 collapse stability | 5, 7 | executor | Vitest Browser Mode collapse geometry test | browser | scroll position delta bounded for pinned and mid-screen headers | yes |
| R3 added files show content | 2, 5, 7, 9 | executor | fixture unit + browser + native screenshot/state | unit + browser + native | added-file fixture has non-empty body and assertions inspect rendered text | yes |
| R3 markdown preview | 5, 6, 7, 9 | executor + reviewer | sanitizer unit, worker unit, browser integration, native proof | unit + browser + native | source text fallback cannot satisfy preview acceptance | yes |
| R4 resource parser/canonicalization | 2, 9 | executor | Swift + TS unit tests | unit | unknown/duplicate/mixed selectors and non-canonical URLs rejected | yes |
| R4 item windows and cache-before-fetch | 2, 5, 7, 9 | executor | TS integration + native resource ledger | integration + native | proves repeated current-generation content is not refetched and stale generation URLs fail closed | yes |
| R5 Zustand index discipline | 1, 2, 5 | executor | unit + architecture lint | unit + lint | no raw bodies/fetch/postWorker/Pierre mutation in store actions | yes |
| R6 feature worker placement | 1, 6 | executor | architecture lint + build audit | lint + build | rejects `review-viewer/runtime` and feature worker code outside lane folders | yes |
| R7 semantic IPC | 8, 9 | executor | Swift IPC tests + debug transcript | integration + e2e | commands drive Bridge ports, not command palette or raw WebKit; old names are absent | yes |
| Dev-server scenario allowlist | 7 | executor | provider unit/integration negative tests | unit + integration | raw path/query/env selection fails in shareable routes | yes |
| R8 Victoria-backed performance | 7, 9 | executor | Victoria query artifact | observability + performance | marker-scoped query correlates IPC/actions/screenshots with metrics | no, green proof required |
| Native render proof | 8, 9, 10 | executor | semantic IPC-driven native render verifier | native + e2e | fails on blank pane, missing added content, source fallback for markdown, bad scroll/collapse state | yes |
| No generated app assets in source | 1, 10 | executor | asset audit + git status review | build + review | generated `Sources/.../Resources/BridgeWeb/app` is reproducible, ignored if generated | no |

## Task Sequence

### Task 0: Reconcile Branch And Existing Partial Work

Purpose: start implementation from a clean, intentional branch state.

Steps:

1. Verify `git status --short` and record uncommitted files.
2. Inspect existing uncommitted diagnostics and decide whether each file is:
   - kept and integrated into this plan
   - renamed/split to match current architecture
   - discarded because it duplicates a stronger proof path
3. Fetch current `origin/main`.
4. Merge `origin/main` only if the user directive is still active for this
   execution pass or the user re-confirms. If conflicts touch Bridge, IPC,
   command specs, or app resources, pause implementation and report evidence
   before resolving beyond mechanical rename/import fixes.

Proof:

- `git status --short` before and after
- no untracked generated assets staged
- conflict notes if any

### Task 1: Architecture And Folder Boundary Cutover

Purpose: make the code layout reflect the accepted mental model before adding
more behavior.

Write surfaces:

- `BridgeWeb/src/app/*`
- `BridgeWeb/src/review-viewer/app/*`
- `BridgeWeb/src/review-viewer/state/*`
- `BridgeWeb/src/review-viewer/projections/*`
- `BridgeWeb/src/review-viewer/content/*`
- `BridgeWeb/src/review-viewer/code-view/*`
- `BridgeWeb/src/review-viewer/trees/*`
- `BridgeWeb/src/review-viewer/markdown/*`
- `BridgeWeb/src/review-viewer/workers/{projection,markdown,pierre,shared-rpc}/*`
- `BridgeWeb/scripts/check-bridgeweb-architecture.ts`

Steps:

1. Split `BridgeWeb/src/app/bridge-app.tsx` by responsibility into app
   bootstrap/composition and review-viewer-owned coordinators.
2. Move `review-viewer/runtime/review-content-loader.ts` into
   `review-viewer/content`.
3. Move `review-viewer/runtime/use-review-projection-coordinator.ts` into
   `review-viewer/projections` or a more specific controller folder.
4. Move `review-viewer/workers/rpc` into `workers/projection` and
   `workers/shared-rpc`, keeping generic transport separate from
   projection-specific schema/planning.
5. Add or tighten architecture checks:
   - no `review-viewer/runtime`
   - no feature worker code outside `review-viewer/workers/*`
   - no Swift/content fetch/worker post/Pierre mutation in Zustand actions
   - no broad raw bodies in Zustand state
6. Add focused red tests for the architecture rules before making them pass.

Proof:

- architecture rule tests fail before cutover where feasible
- `pnpm --dir BridgeWeb run check`
- `mise run bridge-web-check`

### Task 2: Resource Data Plane And Registries

Purpose: make resource loading robust enough for large packages and visible
windows.

Write surfaces:

- `BridgeWeb/src/bridge/bridge-resource-url.ts`
- `BridgeWeb/src/foundation/content/*`
- `BridgeWeb/src/foundation/review-package/*`
- `BridgeWeb/src/review-viewer/content/*`
- `BridgeWeb/src/review-viewer/projections/*`
- `BridgeWeb/src/review-viewer/state/*`
- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/*`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/*`
- Bridge resource tests under `Tests/AgentStudioTests/Features/Bridge/*`

Steps:

1. Define Zod v4 schemas with camelCase `xxxSchema` constants and PascalCase
   inferred types for every TS boundary payload.
2. Freeze item-window authority before implementing registry semantics:
   - Swift-owned order -> cursor token resource windows
   - BridgeWeb-owned order/search/facet -> bounded explicit item-id lists
   - no `review-items` cache key or fetch semantics land until this authority
     is encoded in schemas/tests
3. Define the adaptive item-window budget policy:
   - inputs: measured visible row count, overscan, resource cache hit rate,
     worker latency, fetch latency, and current package size
   - output: bounded item count per request plus hard ceilings for item-id
     lists and cursor windows
   - location: shared review-viewer policy module consumed by parser,
     registry, dev-server verifier, and benchmark proof
   - initial constants are seed values only; benchmark/Victoria evidence must
     tune them before PR-ready proof
4. Expand resource URL parsing to the accepted kinds:
   - `review-package`
   - `review-items`
   - `content`
   - `tree`
5. Enforce query allowlists, duplicate rejection, mixed selector rejection,
   canonical serialization, generation/revision checks, and typed failures.
   Required negative cases:
   - unknown resource kinds
   - duplicate singleton query keys
   - mixed selector families such as `cursor` plus `itemIds`
   - double-encoded traversal and path-like injection
   - stale generation, revision, or cursor combinations
   - over-budget windows/lists before provider reads
6. Implement closure-owned registries:
   - package snapshot/window registry
   - item window registry
   - content body registry with LRU/eviction
   - tree segment registry with generation invalidation
   - in-flight request registry keyed by canonical resource key
7. Wire Zustand to hold refs/status/cache keys/request IDs, not raw bodies.
8. Implement cache-before-fetch semantics with generation invalidation.
9. Add Swift resource classifier/handler support for the needed route subset.
   If Swift support exceeds current scope, split route support so browser/dev
   server can prove the model first and native proof owns the remaining route.
10. Update or add shared Swift/TS fixtures so parser semantics stay paired.

Proof:

- TS parser unit tests
- Swift parser/handler unit tests
- content registry unit tests
- budget-calculation unit tests seeded by benchmark/Victoria inputs
- tree registry unit tests
- TS/Swift route tests for `review-package`, `review-items`, `content`, and
  `tree`
- one transport/integration fetch per resource kind
- one negative mixed-selector/cursor-budget case per resource kind
- integration test: visible item window hydrates without duplicate current
  generation fetches
- no source mutation routes

### Task 3: Review Modes, Facets, And Projection Requests

Purpose: make the UX model coherent before polishing the UI.

Write surfaces:

- `BridgeWeb/src/review-viewer/models/*`
- `BridgeWeb/src/review-viewer/navigation/*`
- `BridgeWeb/src/review-viewer/state/*`
- `BridgeWeb/src/review-viewer/projections/*`
- `BridgeWeb/src/review-viewer/workers/projection/*`

Steps:

1. Replace old filter-mode vocabulary with:
   - `normalReview`
   - `guidedReview`
   - `plansAndSpecs`
2. Model Git/file/search/path/extension/language/change-set as facets.
3. Define projection request schemas as discriminated unions where variants are
   real variants, not loose string bags.
4. Pin first-slice mode semantics:
   - `normalReview`: deterministic changed-file review order from the active
     package/projection
   - `guidedReview`: AI-ranked or heuristic-ranked review order using explicit
     ordering fields, falling back to normal order when no ranking is present
   - `plansAndSpecs`: docs/plans/specs-focused projection by path, basename,
     and markdown-like extension rules
5. Carry the mode/facet vocabulary through telemetry validators and
   allowlists; old filter-mode names are rejected.
6. Reject cursor reuse after facet/filter/order changes, package generation
   changes, or revision changes. Reject item-id lists outside active package
   membership.
7. Move projection/search/facet work above the large threshold into the
   projection worker lane.

Proof:

- unit tests for projection request schemas and mode/facet classification
- worker unit tests for large projection/filter/search
- store unit tests proving narrow updates and no body storage

### Task 4: shadcn/Base UI And Review Chrome

Purpose: make the top-level review controls understandable, compact, and aligned
with AgentStudio and DiffsHub.

Write surfaces:

- `BridgeWeb/components.json`
- `BridgeWeb/src/components/ui/*`
- `BridgeWeb/src/app/bridge-app.css`
- `BridgeWeb/src/review-viewer/chrome/*`
- `BridgeWeb/src/review-viewer/shell/*`
- `BridgeWeb/src/review-viewer/trees/*`

Steps:

1. Verify or regenerate package-local shadcn/Base UI components using the Mira
   style, small radius, and lucide icon library.
2. Map Catppuccin Mocha into shadcn semantic CSS variables.
3. Configure Pierre CodeView/Trees theme variables to match the same dark
   review grammar.
4. Replace bespoke controls with composed shadcn/Base UI primitives:
   - compact segmented control for review mode
   - one filter popover with columns/sections for Git, file kind, and scope
   - compact search control with regex affordance
   - icon-first toolbar buttons with hover/focus states
5. Remove the detached top strip. Header becomes one compact row.
6. Keep file stats in the right rail bottom/status chip area rather than a
   duplicated top banner.

Proof:

- component tests for generated primitive composition
- browser assertions for roles/labels/aria state
- visual proof comparing current dev-server against DiffsHub reference crop
- bbox probes for rail/search/filter/button dimensions

### Task 5: CodeView Hydration, File Click, Collapse, Added Files

Purpose: make the main review surface feel like DiffsHub and work on the large
real worktree.

Write surfaces:

- `BridgeWeb/src/review-viewer/code-view/*`
- `BridgeWeb/src/review-viewer/content/*`
- `BridgeWeb/src/review-viewer/projections/*`
- `BridgeWeb/src/review-viewer/trees/*`
- `BridgeWeb/src/review-viewer/test-support/*`

Steps:

1. Use Pierre CodeView item ownership correctly:
   - production uses uncontrolled/imperative CodeView ownership for large and
     streaming surfaces
   - controlled React-array ownership is allowed only in bounded tests or tiny
     fixtures
   - do not route huge item updates through React arrays
2. Ensure selected/visible windows hydrate content through resource URLs and
   registries.
3. Render added files with full content.
4. Implement file-tree click -> CodeView scroll alignment to the sticky header
   threshold.
5. Make collapse/expand preserve scroll position:
   - mid-screen collapse keeps the header visually stable and content below
     moves up
   - pinned-top collapse keeps the pinned header stable and content below moves
     up
6. Make selected-file navigation a single-authority motion path:
   - one file-tree click produces one CodeView reveal intent
   - hydration of the same selected item updates content without issuing a
     second scroll-to-item
   - user-initiated file selection uses DiffsHub-like smooth reveal where
     practical; forced instant correction is reserved for deterministic recovery
     paths
   - visible-window hydration must overscan and materialize the selected item,
     but it must not prune/recreate the selected body in a way that causes the
     header to jump
7. Keep markdown selection inside the Review CodeView unless the user or IPC
   explicitly switches render mode:
   - tree-click selection must not accidentally replace the main CodeView with a
     markdown/file-view pane
   - scroll-only and click-to-file paths must render the same selected markdown
     item shape
   - markdown preview remains a typed explicit view/mode handled by Task 6
8. Fix visible-content loading placeholders so they are anchored to CodeView
   item geometry:
   - loading skeletons must not float as free canvas overlays while scrolling
   - placeholder height must be stable enough that hydration does not move the
     header unexpectedly
   - placeholder and final content must share the same CodeView item ownership
     path or an explicitly tested row-local fallback
9. Remove duplicate file names in headers and use Pierre/lucide-compatible
   icon discipline.
10. Use stable dimensions and layout constraints so hover, selected, and collapsed
   states do not resize rows unexpectedly.

Proof:

- unit regression: selected-content hydration after initial reveal does not call
  CodeView scroll again
- browser proof: one tree click yields one selected-file reveal and no second
  scroll jump when content hydrates
- browser proof: clicking a markdown file and scrolling to that markdown file
  leave the same CodeView review surface unless render mode was explicitly
  changed
- browser/visual proof: loading skeletons remain inside the selected or visible
  file row geometry while scrolling and disappear without a layout jump when
  content hydrates
- browser test for file click scroll-to-header
- browser test for collapse stability in pinned and mid-screen states
- browser test for added full-content rendering
- proof that production CodeView does not drive the full item list through
  React state updates
- screenshot with scrolled CodeView and right rail
- benchmark rows for selection and scroll responsiveness

### Task 6: Markdown Preview Worker

Purpose: make docs/plans useful in the review surface.

Write surfaces:

- `BridgeWeb/src/review-viewer/markdown/*`
- `BridgeWeb/src/review-viewer/workers/markdown/*`
- `BridgeWeb/src/review-viewer/content/*`
- markdown tests and dev fixtures

Steps:

1. Keep markdown rendering in the markdown worker lane.
2. Use Shiki/markdown-exit path where appropriate, but sanitize before DOM
   insertion.
3. Keep images, active links, scripts, remote subresources, and custom-scheme
   loads inert or blocked by policy.
4. Make source text a typed fallback/unavailable state only.
5. Add package/build audit coverage for markdown worker assets.

Proof:

- markdown worker schema unit tests
- sanitizer unit tests
- browser markdown preview integration
- native packaged markdown preview proof in Task 9

### Task 7: Dev-Server Real Worktree Loop And Browser Proof

Purpose: give us a fast, realistic loop before native proof.

Write surfaces:

- `BridgeWeb/scripts/dev-server/*`
- `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/scripts/capture-bridge-viewer-dev-visual-proof.ts`
- `BridgeWeb/scripts/bridge-viewer-browser-benchmark-runner.ts`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/vitest.browser.config.ts`
- browser/integration test files under `BridgeWeb/src/review-viewer/test-support`

Steps:

1. Keep scenario selection named and allowlisted; do not accept arbitrary raw
   paths from query strings or environment variables.
2. Replace or gate the current request URL `worktree`, `repo`, and `base`
   overrides in `BridgeWeb/src/app/bridge-app-dev-worktree.ts` and
   `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`.
3. Replace raw `BRIDGE_WEB_DEV_WORKTREE`, `BRIDGE_WEB_DEV_REPO`, and
   `BRIDGE_WEB_DEV_BASE` selectors with named scenario input only. If raw
   selectors are retained for local-only diagnostics, they must be unreachable
   from shareable routes and excluded from acceptance proof.
4. Carry generation/revision through the dev-server resource path. A content
   URL with a stale generation or revision must fail closed in the fast-loop
   path just as it does in native.
5. Ensure the allowlisted real-worktree scenario points at this checkout and
   current branch only for local debug.
6. Add negative tests for:
   - traversal and symlink/root escape
   - unknown scenario names
   - non-loopback host
   - remote URL
   - raw absolute path injection
   - raw env path/base injection
   - non-git-root and non-allowlisted repository roots
   - stale generation/revision resource URLs
7. Mirror native `review-package`, `review-items`, `content`, and `tree`
   resource parsing/fetch semantics in the dev harness through the same
   canonical TS resource interfaces.
8. Use Browser Mode with Playwright for DOM, CSS, click, scroll, workers, and
   CodeView/FileTree behavior.
9. Capture DiffsHub reference screenshots and Bridge dev-server screenshots in
   a proof artifact.
10. Replace fixed sleep waits in visual proof scripts with event/DOM waits before
   treating the visual proof command as a hard acceptance gate. Screenshots from
   sleep-based capture may remain diagnostic but cannot close the gate.
11. Run benchmark scenarios for:
   - cold large package
   - warm package
   - file click/scroll
   - filter/search
   - added file content
   - markdown preview
   - collapse/expand
12. If the benchmark is used as markdown-worker performance proof, add a
   non-mocked markdown-worker scenario. Otherwise, state in the benchmark
   artifact that browser/native integration closes markdown-worker proof.
13. Add optional dev-server OTLP/Victoria config guarded to local debug use.
   This telemetry must stay outside the packaged BridgeWeb browser bundle/app
   assets and must keep `verify-bridge-web-no-direct-otlp.sh` green.

Proof:

- `pnpm --dir BridgeWeb run test:dev-server`
- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- `pnpm --dir BridgeWeb run test:browser`
- `pnpm --dir BridgeWeb run test:benchmark:browser`
- `pnpm --dir BridgeWeb run proof:visual:dev-server` only after the script waits
  on DOM/events instead of fixed sleeps
- proof artifact contains current screenshots, DiffsHub reference, metrics, and
  scenario fingerprint
- verifier artifact records scenario name, repo/worktree identity, current HEAD,
  package id, revision/generation, and pinned target path(s)

### Task 8: Semantic Review IPC

Purpose: enable deterministic native/e2e control without driving UI chrome.

Write surfaces:

- `Sources/AgentStudio/App/IPCComposition/*`
- `Sources/AgentStudio/App/IPCComposition/Bridge/*` if a Bridge-specific
  contribution folder is introduced
- `Sources/AgentStudio/Features/Bridge/*`
- `Tests/AgentStudioAppIPCTests/**`
- BridgeWeb command/control schemas if needed
- docs updates for command catalog if commands are public programmatic controls

Steps:

1. Rebase the design on current main's typed command/tooltip/source contract.
2. Add semantic methods:
   - `bridge.review.load`
   - `bridge.review.refresh`
   - `bridge.review.getPackage`
   - `bridge.review.setMode`
   - `bridge.review.setFacets`
   - `bridge.review.selectFile`
   - `bridge.review.revealFile`
   - `bridge.review.scrollToFile`
   - `bridge.review.expandFile`
   - `bridge.review.collapseFile`
   - `bridge.review.prepareWindow`
   - `bridge.fileTree.setSearch`
   - `bridge.fileTree.setFacets`
   - `bridge.fileTree.revealPath`
   - `bridge.fileView.setRenderMode`
   - `bridge.telemetry.flush`
   - `bridge.telemetry.snapshot`
3. Keep pane creation as an app-owned/open-review-pane capability. Review IPC
   methods operate on a resolved Bridge/Review pane target; `bridge.review.load`
   does not bypass app-owned pane creation or target resolution.
4. App IPC composition owns method definitions, public IPC projections, and
   security contracts. `Features/Bridge` owns narrow ports/controller behavior
   behind those definitions.
5. Route through pane target resolution and Bridge capability ports.
6. Reject unsupported pane targets with typed errors.
7. Do not return hot file/diff/markdown bodies.
8. Remove existing Review body-returning IPC seams such as direct content or
   markdown body methods. No backward compatibility layer is kept for this
   Review path; if a programmatic client needs content, it receives or prepares
   a scoped resource handle and fetches the resource URL.
9. Remove old `bridge.diff.*` Review-control aliases from the registry and
   routing tests in this slice. The accepted public Review namespace is
   `bridge.review.*`.
10. Emit notification events after Bridge-owned state changes.
11. Add negative registry/routing tests for raw WebKit eval, raw postMessage,
   EventBus command routing, `zmx.*`, source mutation, cross-pane access, and
   presentation-only command-bar success.

Proof:

- Swift IPC unit/integration tests
- registry tests asserting new method presence and removed method absence,
  including rejection of `bridge.fileView.getContent` and old `bridge.diff.*`
  Review-control names
- permission/target negative tests
- debug IPC transcript driving a Bridge pane without command palette UI
- debug IPC transcript drives mode switch, facets, scroll-to-file, collapse,
  and expand without raw WebKit/page control
- content proof still goes through `agentstudio://resource/*`

### Task 9: Native AgentStudio Large Worktree Proof

Purpose: prove the packaged app path, not just the dev server.

Write surfaces:

- `Sources/AgentStudio/Features/Bridge/*`
- native debug/observability scripts if a named proof command is missing
- `BridgeWeb` packaged assets via build task only
- proof scripts/artifacts under repo-local `tmp/` or `docs/wip/` as appropriate

Steps:

1. Build packaged BridgeWeb assets through `mise run bridge-web-build`.
2. Launch debug observability app through the repo runner, not ad hoc env.
3. Use semantic IPC to open/target a Review pane, load package, set mode/facets,
   select/reveal a file, open markdown preview, and exercise collapse/search.
4. Verify packaged assets, resource URLs, worker lanes, content hydration, and
   markdown preview.
5. Query Victoria metrics/logs with a marker-scoped proof.
6. Use the existing debug/observability runner and verifier path for
   real-worktree proof, extending it with a Bridge review diagnostic action
   rather than adding a separate top-level proof command unless implementation
   shows the existing runner cannot express the scenario cleanly.
7. Extend `scripts/verify-bridge-observability.sh` for new resource-plane
   metric names only after those emitters exist, preserving the existing
   marker-scoped, unsafe-field, and unlabeled-series guards.
8. Add or extend a named native render verifier on the existing
   debug/observability path. It must fail on:
   - blank Review pane
   - selected path not reflected in rendered state
   - selected-content-ready missing
   - added-file text missing
   - markdown preview falling back to plain source when preview was requested
   - file-click scroll-to-header misalignment
   - collapse/expand anchor instability

Proof:

- `mise run observability:up`
- `mise run bridge-web-build`
- `mise run run-debug-observability -- --detach` with Bridge review diagnostic
- `mise run verify-debug-observability`
- semantic IPC-driven native render verifier on the existing
  debug/observability path
- `mise run verify-bridge-observability`
- `mise run test-webkit` unless it fails outside this slice with a recorded
  harness blocker
- screenshot/render-state evidence from the actual AgentStudio debug app as
  supporting evidence, not the only verifier
- Victoria metrics for resource fetch/cache/worker/controller/scroll stages

### Task 10: Broad Validation, Review, PR Wrapup

Purpose: prove the branch and prepare it for merge review.

Steps:

1. Run lower-layer and broad gates in order.
2. Fix scoped failures only. If unrelated infrastructure/test failures appear,
   stop edits and report slice proof separately from unrelated blockers.
3. Run implementation-review-swarm and address accepted findings.
4. Commit logical checkpoints.
5. Open/update PR and run implementation-pr-wrapup.

Proof commands:

```bash
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run test:browser
pnpm --dir BridgeWeb run test:dev-server
pnpm --dir BridgeWeb run test:dev-server:worktree
pnpm --dir BridgeWeb run test:benchmark:browser
pnpm --dir BridgeWeb run proof:visual:dev-server
mise run bridge-web-build
mise run bridge-web-audit
mise run bridge-viewer-benchmark
mise run verify-bridge-observability
mise run test -- --filter Bridge
mise run test -- --filter AgentStudioIPC
mise run test-webkit
mise run lint
git diff --check
```

If `mise run test-webkit` fails outside this slice with the known WebKit harness
crash, report that as an outside-scope blocker and do not edit infrastructure
without approval.

## Execution DAG

```text
gate 0: repo state, origin/main decision, existing uncommitted diagnostics
  |
  +-- lane A: architecture/data-plane foundations
  |     task 1 -> task 2 -> task 3
  |     proof: check, parser/store/worker unit tests
  |
  +-- lane B1: chrome-only UI/DiffsHub visual surface
  |     task 4
  |     proof: component tests, screenshots, bbox probes
  |
  +-- lane C: dev-server/worktree/browser proof harness
  |     task 7
  |     proof: named scenario, negative tests, visual proof, browser benchmark
  |
  integration gate 1:
    parent reviews lanes A/B1/C, resolves imports, validates no duplicated
    runtime/worker/store concepts, and runs BridgeWeb check/test/browser gates
  |
  +-- lane B2: data-plane-dependent CodeView/markdown hydration
  |     task 5 -> task 6
  |     proof: browser tests, screenshots, bbox probes, markdown worker proof
  |
  integration gate 1b:
    parent integrates Task 5/6 with Task 2/3 data-plane contracts and reruns
    BridgeWeb check/test/browser gates
  |
  +-- lane D: semantic IPC/native control
  |     task 8
  |     proof: Swift IPC tests, target/permission negative tests
  |
  +-- lane E: native packaged observability proof
        task 9
        proof: debug app, resource URLs, workers, markdown, Victoria metrics
  |
  integration gate 2:
    browser and native behavior match enough to trust the packaged path
  |
  task 10: broad validation, implementation-review-swarm, PR wrapup
```

Parallelism rule:

- Lanes A, B1, and C can run in parallel only when their write scopes are kept
  disjoint and a parent integrates.
- Task 5 and Task 6 do not run in parallel with Task 2/3 because they depend on
  resource URL, registry, projection, and state contracts and share
  `review-viewer/content`, `review-viewer/projections`, and
  `review-viewer/state` seams.
- Lane D can start after the command catalog and target data needed for IPC are
  stable enough.
- Lane E waits for browser/dev-server behavior and packaged worker/resource
  paths to be stable.

## Write Surface Summary

BridgeWeb:

- `BridgeWeb/src/app/*`
- `BridgeWeb/src/components/ui/*`
- `BridgeWeb/src/foundation/{content,review-package,review-query,telemetry}/*`
- `BridgeWeb/src/review-viewer/{app,chrome,state,projections,content,code-view,trees,markdown,shell,theme,telemetry,test-support}/*`
- `BridgeWeb/src/review-viewer/workers/{projection,markdown,pierre,shared-rpc}/*`
- `BridgeWeb/scripts/*.ts`
- `BridgeWeb/scripts/dev-server/*.ts`
- `BridgeWeb/vitest*.config.ts`
- `BridgeWeb/package.json`, lockfile, `components.json`, PostCSS/Tailwind config

Swift:

- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/*`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/*`
- `Sources/AgentStudio/Features/Bridge/Transport/*`
- `Sources/AgentStudio/Features/Bridge/Views/*`
- IPC registry/service surfaces if Bridge commands are added
- Bridge-focused tests under `Tests/AgentStudioTests`

Docs/proof:

- update this plan if implementation reality changes the model
- update the source specs only for accepted spec-level changes, not ordinary
  task progress
- update the [Bridge Viewer](../architecture/bridge_viewer_architecture.md),
  [native runtime](../architecture/bridge_native_runtime_architecture.md), and
  [web runtime](../architecture/bridge_web_runtime_architecture.md) docs after
  resource windows and registries change
- proof artifacts under `tmp/` or `docs/wip/` per repo convention

## Validation Gates By Layer

Unit:

- TS schemas/parsers/stores/workers/chrome/materialization
- Swift resource classifiers and IPC DTOs

Integration:

- TS content registry + mocked resource fetch + projection worker
- Swift Bridge resource/content store and IPC command routing

Browser:

- Vitest Browser Mode with Playwright for actual DOM/CSS/click/scroll/workers
- dev-server real-worktree verifier
- visual proof against fresh DiffsHub reference

Smoke/native:

- packaged BridgeWeb in AgentStudio debug app
- Bridge pane package load, file select/reveal, markdown preview, added file
  content, collapse/search/facets

Performance/observability:

- BridgeWeb browser benchmark
- Victoria metrics/logs for native real-worktree proof

PR readiness:

- lint/typecheck/build/audit
- implementation-review-swarm
- PR checks/review threads/mergeability via implementation-pr-wrapup

## Security And Reliability Requirements

- Dev server accepts only named local scenarios; arbitrary absolute paths,
  traversal, remote URLs, non-loopback hosts, and unknown scenarios fail closed.
- Dev server rejects non-git-root, non-allowlisted roots, and symlink/root
  escapes, not only obviously malformed paths.
- Resource URLs are capabilities scoped to the active pane/package/generation.
- Item-window cursors are server-issued authority tokens; naked index windows
  are not authority.
- Markdown is sanitized before DOM insertion; links/images/subresources remain
  inert or blocked by policy.
- Worker messages use Zod schemas on both sides and drop stale generation
  results.
- Telemetry is debug/proof scoped, low-cardinality, and source-scrubbed.
- IPC permissions are capability-scoped and pane-targeted.
- No source mutation is exposed by this slice.

## Split Or Replan Triggers

Pause implementation and reconverge if:

- Pierre CodeView or Trees public APIs cannot support DiffsHub-class sticky,
  collapse, or scroll behavior without private API assumptions.
- WKWebView cannot load the packaged Pierre portable worker or markdown worker
  through the accepted asset/resource path.
- Direct worker fetch of `agentstudio://resource/*` is needed to meet latency
  and WebKit proves it is unsupported; first implementation should transfer
  DTOs to workers from a main-thread resource authority.
- The large real worktree remains blank or unusably slow after the resource,
  hydration, and worker fixes; do not polish around a blank surface.
- The command/IPC spec from main changes enough that Bridge command names or
  permission atoms need a spec update.
- A validation failure is outside the agreed code path and fixing it would edit
  test infrastructure, runner infrastructure, or unrelated features.

## Open Questions Before Implementation

1. Should task 0 merge `origin/main` immediately under the user's prior approval,
   or ask for one final explicit merge confirmation after this plan review?

## Next Workflow

Run `shravan-dev-workflow:implementation-execute-plan` against this reviewed
plan. If implementation reveals a stale contract or proof gate that cannot pass
inside scope, route back to `plan-creation-swarm` before continuing.
