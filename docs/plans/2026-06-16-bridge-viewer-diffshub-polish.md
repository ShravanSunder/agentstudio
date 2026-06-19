# Bridge Viewer DiffsHub Polish Implementation Plan

Date: 2026-06-16

Goal id: `2026-06-16-bridge-viewer-diffshub-polish`

Status: reviewed plan; accepted `shravan-dev-workflow:plan-review-swarm` findings addressed

2026-06-19 reset: the DiffsHub/Shadcn/Catppuccin contract below is the active
implementation contract. The branch may already contain in-progress BridgeWeb
edits; validate or reshape those edits against this contract instead of treating
them as proof. The reset ledger is
`tmp/research-workflows/2026-06-19-bridgeweb-diffshub-shadcn-reset/research-ledger.md`.

## Goal

Make the Bridge review viewer feel like a dense, dark, high-performance DiffsHub-style review surface while preserving AgentStudio boundaries and the user-requested right-side file rail.

This is a hard polish and behavior pass over the current Bridge viewer shell. It is not a Bridge contract rewrite.

## Non-Goals

- No patch apply, approve/reject, source mutation, Monaco/editor behavior, or annotation authoring.
- No Bridge contract model rewrite.
- No CI harness or unrelated Swift test infrastructure changes without explicit approval.
- No DiffsHub pixel clone. Borrow the review grammar, APIs, density, and proof style, then fit AgentStudio.
- No markdown diff renderer in this slice. Two-sided markdown diffs stay in CodeView until a rendered markdown diff design exists.
- No Swift IPC implementation before the dev-server DiffsHub-class UX and
  performance gates are coherent. IPC is a follow-on lane that may be delegated
  after browser UX/perf proof stabilizes; it is required before repeatable
  native large-worktree proof, not before the DiffsHub visual/interaction loop.

## 2026-06-19 Reset Contract

The implementation order is reset to this sequence:

1. Re-anchor on local Pierre/DiffsHub source and BridgeWeb current code.
2. Fix the design-system foundation: shadcn/Base UI primitives first, then
   Bridge wrappers for compact review chrome.
3. Fix the theme foundation: Pierre/Shiki `catppuccin-mocha` first, FileTree
   through `themeToTreeStyles(...)`, Bridge chrome through shadcn/Tailwind
   semantic tokens mapped to Catppuccin Mocha.
4. Fix dev-server UX and Browser Mode proof on realistic large fixtures.
5. Hand off or implement semantic Swift IPC only after the browser loop proves
   selection, reveal, filtering, content fetch, markdown, scroll, and visual
   parity.
6. Finish with AgentStudio debug app, Victoria metrics/traces/logs, screenshots,
   and PR-readiness gates.

This reset supersedes any earlier implementation drift that treated the viewer
as a hand-built Tailwind shell with Pierre inside it. BridgeWeb may customize
generated shadcn/Base UI components, but it must not create a parallel control
language for buttons, menus, toggles, filters, focus rings, disabled states, or
overlay behavior.

The comparison target is DiffsHub running Catppuccin Mocha. Local DiffsHub
source shows `diffshub-dark-theme` is the dark-theme persistence key and
Pierre's theme packages expose `catppuccin-mocha`; browser proof should set or
select that theme before comparing. DiffsHub uses shadcn-style Radix wrappers,
while BridgeWeb uses shadcn/Base UI; copy DiffsHub's review grammar,
measurements, Pierre API usage, and Catppuccin target, not its Radix dependency
choice. The DiffsHub default `pierre-dark` is useful source prior art, but it is
not the accepted visual target for this branch.

Current known drift to correct before more feature work:

- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx` has
  in-progress scroll-anchor/collapse edits. Before implementation continues,
  finish the helper path or back out the partial helper references without using
  destructive git commands.
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-theme.ts` registers a
  custom CSS-variable theme under `catppuccin-mocha`. Audit this first. If it
  masks Pierre's built-in Catppuccin theme, replace it with a Bridge-owned
  adapter that uses Pierre's supported theme resolution without name collision.
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx` hardcodes many
  tree color variables. Replace the broad hand-authored palette with
  `themeToTreeStyles(...)` output from the resolved Catppuccin/Pierre theme,
  then layer only narrow AgentStudio overrides.
- Do not begin Swift IPC while added-file content, markdown rendering,
  collapse/expand anchoring, tree-click alignment, and visual parity are still
  failing in the dev-server loop.
- Generated packaged app assets are build outputs, not source. Check in
  BridgeWeb source, shadcn component source, lockfiles, scripts, build/audit
  contracts, and fixture definitions. Do not check in generated native app
  resource bundles or dist assets that `mise run bridge-web-build`,
  `pnpm --dir BridgeWeb run build`, or setup/build scripts can reproduce.

## Source Coverage

### User Requirements

- Match the DiffsHub dark CodeView/FileTree target shown in the screenshots.
- The comparison target is side-by-side strict: our viewer may differ from
  DiffsHub only in the file rail location. DiffsHub keeps the rail on the left;
  AgentStudio keeps it on the right. Header density, CodeView file rows,
  collapse affordances, icon grammar, filter menus, scroll behavior, colors,
  and file/tree interactions should otherwise match the DiffsHub/Catppuccin
  Mocha experience as closely as the AgentStudio shell allows.
- Keep the file sidebar on the right side.
- Canvas background must be black.
- Remove ugly/native browser controls.
- Replace mismatched filter/dropdown/icon styling with AgentStudio/Pierre-style controls.
- Use shadcn components generated/configured through `components.json`
  (`style: "base-mira"`) with Base UI primitives. Do not build raw custom
  controls when a shadcn/Base UI button, menu, popover, input, tooltip, or
  toggle primitive applies. Customize those primitives downstream with Tailwind
  classes and theme tokens.
- Use Catppuccin Mocha as the visual basis for AgentStudio Bridge chrome and
  the Pierre viewer surfaces. Where Pierre exposes a Catppuccin Mocha theme,
  CodeView and FileTree must use Pierre's supported Catppuccin Mocha theme/API
  rather than approximating it with ad hoc CSS. If a Pierre API requires a
  theme object/name/style map, prove the exact API from local Pierre source or
  DeepWiki before implementing.
- Use Tailwind v4.
- Use zod v4 schema/type conventions:
  - `xxxSchema` for zod schemas.
  - `Xxx` for derived types.
  - discriminated unions for projection/view/render variants.
  - prefer `Record<string, unknown>` over loose object/any shapes.
- Use Pierre CodeView/FileTree APIs properly.
- Use workers for all rendering work that can block UI. CodeView syntax
  highlighting stays in Pierre's Shiki worker lane; markdown parsing,
  markdown-exit rendering, and Shiki-highlighted markdown code blocks stay in
  the dedicated markdown worker lane. The main thread may coordinate,
  cancel/drop stale work, sanitize/display bounded results, and update React
  state, but it must not import or execute markdown/Shiki rendering packages.
  If debug observability shows heavy projection, filtering, tree shaping,
  CodeView preparation, markdown preparation, or other rendering-adjacent data
  work on the main thread, move that work behind a typed worker RPC lane rather
  than normalizing it as product runtime behavior.
- Added/new files must show their full fetched content in this slice. Placeholder
  rows are acceptable while selected content is pending; after content resolves,
  added-file head/file resources must materialize as full CodeView file items.
- Maintain Zustand discipline.
- Add markdown rendering with `@shikijs/markdown-exit`.
- Fix and prove CodeView scrolling.
- Use Peekaboo screenshots in the proof loop.
- Use Browser Mode / Playwright / CDP visual loops against the dev server and
  DiffsHub examples before claiming UI parity. Subagents should be used for
  parallel visual/API audits when they can inspect DiffsHub or Pierre without
  conflicting with implementation.

### Local AgentStudio Evidence

Read before planning:

- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx` owns the right sidebar, search/filter chrome, canvas/sidebar grid, and summary stats. The review viewer must not render a detached visible top metadata strip above CodeView; compact header-plane chrome is allowed only when it matches the shadcn/Catppuccin app surface.
- `BridgeWeb/src/app/bridge-app.css` is 56 lines and owns the current dark tokens.
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx` is 101 lines and wraps Pierre `FileTree`.
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx` is 232 lines and wraps Pierre `CodeView`.
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.ts` is 243 lines and converts Bridge content resources into Pierre `file` or `diff` items.
- `BridgeWeb/src/app/bridge-app.tsx` is 588 lines and currently owns selected item, projection mode, search, git-status filter, file-class filter, RPC, content fetch, and telemetry wiring.
- `BridgeWeb/src/review-viewer/state/review-viewer-store.ts` is 215 lines and owns the current Zustand store.
- `BridgeWeb/src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx` is 256 lines and owns the Pierre Shiki worker pool.
- `BridgeWeb/tsdown.config.ts`, `BridgeWeb/scripts/build-app-assets.ts`, and `BridgeWeb/scripts/audit-dependencies-and-assets.ts` own BridgeWeb bundling, generated assets, worker assets, and asset proof.

Observed current problems:

- Shell chrome is custom and minimal, while only the inner CodeView is Pierre-like.
- Earlier shell revisions exposed counts and internal metadata as a plain top text strip. That strip must stay removed; compact rail chrome and CodeView file headers own visible review metadata.
- Projection buttons are text pills and do not share a durable component system.
- Sidebar uses native `<select>` for `Git status` and `File class`.
- Sidebar search is always visible with labels, not a compact DiffsHub-style search affordance.
- Tree uses stock `FileTree` directly, with 28px rows and broad default expansion.
- The code plane can leave large blank/unstyled space and has an unproven scroll ownership bug.
- Docs/plans projection is only a filter, not a markdown/prose presentation mode.

Current hard feedback catalog from the DiffsHub comparison loop:

- Theme mismatch: the live Bridge viewer is still not using Pierre/Catppuccin
  Mocha end to end. CodeView syntax colors, added/deleted backgrounds, chrome
  surfaces, rail colors, row hover/selection, and separators must converge on
  the DiffsHub Catppuccin Mocha target.
- Component-system mismatch: some controls still look hand-built. Buttons,
  menus, filter popovers, search, toggles, and tooltips must be shadcn/Base UI
  primitives customized with Tailwind and theme tokens, not bespoke raw
  controls.
- Top chrome mismatch: detached top metadata/text strips are not acceptable.
  Any remaining top plane must be compact shadcn/Catppuccin chrome that matches
  the app design. Review counts and scope controls must not become an ugly
  full-width strip or pure-black pill row.
- File header mismatch: CodeView file headers must use compact Lucide/Pierre
  icon grammar, clear boundaries between files, no duplicate left/right path
  text, no text cursor affordance, and no oversized expand/collapse control.
- Sticky/collapse behavior mismatch: collapse/expand must preserve the file
  header's current viewport offset. If the header is pinned at the top, it
  stays pinned. If the header is in the middle of the viewport, it stays there
  and content below moves up/down. Collapse must not snap mid-screen headers to
  the top and must not push the header offscreen.
- File navigation mismatch: clicking a file in the tree must scroll/select the
  corresponding CodeView file aligned to the top/pinned header behavior, with
  no sluggish or ambiguous movement.
- Added-file mismatch: added files must expand/render full fetched content,
  including full-file added green backgrounds as DiffsHub does. Empty headers
  for added files are a failing state, not a future task.
- Markdown mismatch: docs/plans markdown still does not render in the live
  experience. Selected markdown docs/plans must render through the markdown
  worker path and have browser tests plus visual proof.
- Scrollbar/scroll-owner mismatch: scrollbars, scroll ownership, pinned header
  behavior, and collapse/expand anchoring must match DiffsHub's feel. The
  viewer cannot rely on the native app manual loop to discover these defects;
  dev-server Browser Mode/Playwright gates must catch them.
- Rail mismatch: the right rail is allowed, but its internal controls, tree
  density, icons, filter menu, search affordance, stats, and selection styling
  must follow DiffsHub/Catppuccin Mocha density and AgentStudio shadcn styling.

### Pierre/DiffsHub Evidence

Read before implementation:

- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/ReviewUI.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewHeader.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewSidebar.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewFileTree.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewWrapper.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/_theming/js/diffshubChromeMapping.ts`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/diffs/src/react/CodeView.tsx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/docs/app/(diffs)/docs/WorkerPool/content.mdx`
- `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/docs/app/(trees)/docs/Guides/ShapeTreeDataForFastRendering/content.mdx`

Borrow:

- Compact review chrome with icon-first controls.
- Custom dropdown/menu surfaces instead of native controls.
- Dense FileTree settings: about 24px rows, low inline padding, flattened empty dirs, preserved review order, sticky folders when useful.
- FileTree styling must follow Pierre's documented layering order:
  host element styles for panel layout/framing, CSS custom properties for
  tree-internal appearance, `themeToTreeStyles(...)` when inheriting a
  VS Code/Shiki/editor palette, and only small/local `unsafeCSS` escape hatches
  after supported surfaces are exhausted.
- FileTree density must be set with Pierre's `density` option, preferably
  `density: "compact"`, so virtualized and painted row heights remain aligned.
  Do not hard-code item heights except when the preset cannot satisfy the
  design after measuring.
- FileTree theme implementation must layer explicit AgentStudio overrides on
  top of Pierre's Catppuccin Mocha/theme-derived variables rather than
  rebuilding the tree visual system from raw shadow-DOM selectors.
- Hidden-until-open file search using Pierre `fileTreeSearchMode: 'expand-matches'` so search opens matching branches instead of only filtering the currently expanded visible rows.
- Incremental FileTree model updates through Pierre model methods when data arrives progressively.
- CodeView custom header hooks such as `renderHeaderPrefix`, `renderHeaderMetadata`, and, where needed, `renderCustomHeader`.
- Tight CodeView layout: small top/bottom padding and small inter-file gaps.
- Themed scrollbars and separators.
- WorkerPool ownership for syntax highlighting.

Do not copy:

- DiffsHub's left sidebar placement. AgentStudio keeps the rail on the right for this slice.
- DiffsHub mobile bottom-sheet behavior.
- DiffsHub diagnostic worker monitor as product UI.
- Raw DiffsHub CSS variable names as AgentStudio source of truth.
- DiffsHub comments/annotation model.

### Vitest Browser Mode Prior Art Evidence

Read before implementation:

- `/Users/shravansunder/Documents/dev/project-dev/askluna-project/askluna-finance/packages/reactive-duckdb-wasm/vitest.config.ts`
- `/Users/shravansunder/Documents/dev/project-dev/askluna-project/askluna-finance/packages/reactive-duckdb-wasm/package.json`
- `/Users/shravansunder/Documents/dev/project-dev/askluna-project/askluna-finance/packages/reactive-duckdb-wasm/tests/integration/strictmode-react.browser.test.tsx`
- `/Users/shravansunder/Documents/dev/project-dev/askluna-project/askluna-finance/packages/reactive-duckdb-wasm/tests/integration/duckdb-bundle-loading.browser.test.ts`
- `/Users/shravansunder/Documents/dev/project-dev/askluna-project/askluna-finance/packages/reactive-duckdb-wasm/tests/benchmark/zero-copy.benchmark.ts`
- `tmp/research-workflows/2026-06-18-bridgeweb-browser-mode-testing/evidence-ledger.md`

Borrow:

- Named Vitest projects/configs so node tests, browser integration tests, and browser performance tests have separate proof lanes.
- A Chromium Playwright browser instance for behavior tests that require real DOM,
  layout, scroll, click, worker, and virtualization behavior.
- `.browser.test.tsx` naming for browser integration tests.
- A separate browser performance project is required. In this repo, prefer
  stable Vitest Browser Mode tests with explicit p95 budgets over experimental
  `vitest bench`, unless a future Vitest upgrade proves browser-project
  discovery and reporting are reliable.
- Test-local setup files for deterministic browser-mode mocks and cleanup.
- Install Browser Mode global failure guards in setup:
  - console error guard
  - uncaught `error` event guard
  - unhandled promise rejection guard
  - page-error guard if the current Browser Mode API exposes it
  These guards must fail the current test unless an explicit local allowlist
  entry names the warning, source, and reason it cannot affect behavior.

Do not borrow:

- DuckDB-specific COOP/COEP headers, WASM asset middleware, or OPFS cleanup unless BridgeWeb later needs equivalent browser assets.
- Multi-tab Playwright E2E as the default BridgeWeb frontend proof. Use it only when testing native app IPC or multi-window behavior; the normal viewer loop should run in Vitest Browser Mode with a mocked Bridge backend.

BridgeWeb testing direction:

- Keep fast pure and integration tests in the existing node lane owned by
  `BridgeWeb/vitest.config.ts`.
- Keep browser integration and browser performance tests in
  `BridgeWeb/vitest.browser.config.ts`. That config is the browser-test source
  of truth and should stay separate from the node-only default config unless a
  future plan intentionally merges the projects.
- Use the `integration-browser` project to mount the real viewer with a mocked
  Bridge transport/content backend.
- Use the `benchmarks-browser` project for fixture-sized interaction and render
  budgets. This project currently runs through `vitest run`, not `vitest bench`,
  so the tests themselves must collect samples and assert budgets.
- Keep Peekaboo/native debug proof as final smoke/manual proof, not as the first or only way to detect frontend regressions.
- Use the DuckDB package's script grammar for performance naming: normal browser
  tests are `test:browser` / `test:browser:integration`; browser benchmarks
  or browser performance tests are `test:benchmark:browser`.
- Verify the provider package shape against the installed Vitest version before
  adding dependencies. The current BridgeWeb install has `@vitest/browser@3.2.6`
  exposing a built-in `playwright` provider from
  `BridgeWeb/node_modules/@vitest/browser/dist/providers.js`; do not add an
  incompatible `@vitest/browser-playwright` package unless the Vitest version is
  intentionally changed and the local package metadata proves compatibility.
- Current scripts are already expected to exist after Task 0.5:
  - `test:browser`
  - `test:browser:integration`
  - `test:benchmark:browser`

### 2026-06-18 Frontend Mock Backend And Performance Test Amendment

Research ledger:

- `tmp/research-workflows/2026-06-18-bridgeweb-mocked-backend-performance-tests/research-ledger.md`
- `tmp/research-workflows/2026-06-18-bridgeweb-frontend-mock-backend-performance-plan/research-ledger.md`
- `tmp/research-workflows/2026-06-18-bridgeweb-frontend-performance-mocked-backend-plan/research-ledger.md`
- `tmp/research-workflows/2026-06-18-bridgeweb-frontend-performance-mock-backend-refresh/research-ledger.md`

Primary-source anchors for the frontend proof shape:

- Pierre diff virtualization tests:
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/diffs/test/DiffHunksRendererVirtualization.test.ts`
  and
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/diffs/test/virtualizedFileDiffEstimatedHeights.test.ts`.
- Pierre tree behavior/performance tests:
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/trees/test/file-tree-search.test.ts`,
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/trees/test/file-tree-density.test.ts`,
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/trees/test/file-tree-virtualization-window.test.ts`,
  and
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/trees/test/file-tree-git-status.test.ts`.
- DiffsHub integration references:
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewFileTree.tsx`,
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/CodeViewWrapper.tsx`,
  and
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/_components/codeViewDataAccumulator.ts`.
- Pierre docs references for scale knobs:
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/docs/app/(trees)/docs/Guides/HandleLargeTreesEfficiently/content.mdx`
  for prepared/presorted tree input and
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/docs/app/(diffs)/docs/WorkerPool/content.mdx`
  for worker-backed highlighting.

Decisions:

- Browser performance tests are tests, not advisory benchmarks. They must fail
  when correctness fails, when metrics are missing, or when a viewer is blank,
  stuck, or using the wrong scroll owner.
- The mocked backend is a Bridge protocol simulator, not a Pierre fixture
  shortcut. It must exercise the same product boundaries the native app uses:
  package push, delta/checkpoint replacement, projection worker request,
  content-handle fetch, command capture, status/error paths, latency, and
  telemetry/performance probes.
- Keep BridgeWeb on the provider shape proven by the installed Vitest version.
  The askluna prior art currently uses Vitest 4 with
  `@vitest/browser-playwright`; BridgeWeb currently uses Vitest 3.2.x with the
  built-in Browser Mode Playwright provider. Do not copy the Vitest 4 provider
  dependency unless the implementation explicitly upgrades Vitest and proves the
  local package graph.
- Browser Mode is the first proof layer for frontend behavior because it gives
  real DOM, layout, click, scroll, worker, and virtualization behavior. Peekaboo
  remains the final native smoke/manual visual proof, not the only way to catch
  broken frontend interactions.
- Borrow Pierre/DiffsHub proof structure, not DiffsHub's GitHub fetch path.
  The portable patterns are deterministic fixtures, narrow behavior assertions,
  append-only tree updates, CodeView/FileTree API usage, and dedicated browser
  performance fixtures with readiness probes. AgentStudio's tests must still
  enter through the mocked Bridge package/content/worker boundary.
- Treat browser performance scenarios as product tests with budgets. The test is
  invalid if it records time before proving the expected viewer behavior,
  Bridge mocked-backend ledger entries, worker mode, and fixture metadata. Fast
  blank renders, worker-disabled-only proof, jsdom-only proof, or native-only
  screenshots cannot satisfy this frontend performance layer.
- Preserve the current BridgeWeb proof-lane split instead of introducing a new
  runner unless the package graph is intentionally upgraded. `BridgeWeb`
  already has:
  - node tests through `pnpm --dir BridgeWeb run test`
  - Chromium Browser Mode integration through
    `pnpm --dir BridgeWeb run test:browser`
  - Chromium Browser Mode performance through
    `pnpm --dir BridgeWeb run test:benchmark:browser`
  - deterministic node benchmark proof through `mise run bridge-viewer-benchmark`
- Browser benchmark output must become durable, not stdout-only. The existing
  browser performance test emits structured JSON and enforces p95 budgets inside
  Vitest; PR readiness also requires a saved or captured browser-performance
  artifact plus a verifier that proves required scenarios, fixture metadata,
  worker modes, correctness assertion names, p50/p95, budgets, and sample counts
  are present.

Current implementation gaps this plan must close before PR readiness:

- `BridgeWeb/tests/vitest-browser-setup.ts` already fails tests on
  `console.error`, window errors, and unhandled promise rejections. Remaining
  work is to keep allowlist entries explicitly documented with reason and
  source. Current Vitest Browser Mode exposes runner-level unhandled error
  reporting and browser `trackUnhandledErrors`, but no test-local Playwright
  `page.on('pageerror')` hook; use `window.error` and
  `unhandledrejection` guards for in-test proof and document this API boundary
  in the implementation proof.
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts`
  already exposes zero/small/slow-bounded latency, content-fetch failure, and
  projection-worker failure. Remaining work is stale package/delta generation
  and hold/release controls for delayed package, delta, content, projection,
  and markdown responses. The hold/release API must be typed and test-owned by
  the mocked Bridge backend, not by test-local untyped maps.
- Browser integration tests already cover package push, tree click, added-file
  full-content rendering, hunk expansion, content failure, projection failure,
  independent CodeView/right-rail scrolling, search expand-matches,
  filter/projection switching, markdown worker rendering, and stale markdown
  supersession. Remaining browser integration work is to broaden stale-drop
  coverage for package replacement, delta revision gaps, content response races,
  and projection
  response races. Those tests must mount the real viewer through Browser Mode,
  push through the mocked Bridge transport, and assert both UI state and Bridge
  backend ledgers before counting the stale/drop row as proven.
- Add direct unit coverage for the test harness and runtime seams that browser
  tests depend on:
  - mocked-backend contract tests for handshake, `pushPackage` vs `pushDelta`
    ledgers, deferred content/projection queues, fixture metadata invariants,
    and typed failure profiles
  - projection-coordinator tests for sync fallback, worker lane selection,
    failed completion, stale completion, telemetry recording, and flush behavior
  - content-loader negative-path tests for non-OK responses, aborted fetch,
    missing handles, and stale selected-content identity changes
- Browser performance tests must measure multiple user-important paths, not only
  package push:
  - cold package push to interactive viewer
  - warm tree selection to visible selected CodeView item
  - added-file selection to full fetched content visible
  - hunk separator click to expanded unchanged lines visible
  - content failure to typed unavailable state visible
  - right-rail scroll and CodeView scroll ownership checks
  - search text to matching tree row visible with `expand-matches`
  - projection/filter switch to updated tree and visible item
  - markdown file selection to sanitized markdown preview visible when the
    markdown worker client is enabled
  - stale package/content/projection/markdown result drop after a newer
    generation, revision, or selected-content identity wins
- Every performance scenario must assert behavior before recording duration.
  Missing selected text, missing fetched content, inert hunk expansion, unchanged
  visible rows after scroll, body/page scroll drift, console errors, or missing
  metric JSON is a failed test.
- Performance output must be structured JSON per scenario with:
  - metric name
  - fixture id
  - fixture class
  - item count
  - path count
  - diff line count
  - package byte count when available
  - backend latency profile
  - worker mode flags
  - viewport size
  - sample count
  - raw samples
  - p50 and p95
  - budget
- Use deterministic fixture seeds and keep performance files sequential. If a
  future Vitest upgrade makes `vitest bench` reliable for the browser project,
  the plan may switch to `vitest bench`; until then,
  `test:benchmark:browser` may remain a normal Browser Mode test project that
  records timings and asserts p95 budgets.
- Worker-disabled browser tests are allowed only as a shell/Bridge baseline.
  They do not satisfy worker-backed CodeView or markdown preview proof. At least
  one Browser Mode integration test and one Browser Mode performance scenario
  must mount with the default packaged Pierre worker path. Injected Blob worker
  factories are allowed as helper probes but do not satisfy product-runtime
  packaged-worker proof.

Frontend mocked-backend test contract:

- Treat `BridgeViewerMockedBackend` as the app-side Bridge contract simulator.
  It should expose typed helpers for pushing packages/deltas, resolving content
  handles, observing commands, observing projection-worker requests, injecting
  latency/failure, and flushing pending browser ticks. Browser tests should not
  reach inside Pierre internals or bypass the Bridge app boundary to make rows
  appear.
- Keep the fixture API deterministic and scenario-oriented:
  - `small-mixed`: fast red/green fixture for package push, tree click, added
    file, hunk expansion, markdown, and negative paths
  - `medium-agentstudio`: realistic source/docs/tests/plans/renames/deletes
    fixture for filters and view switches
  - `large-diffshub`: large file tree plus large diff/hunk surface for scroll,
    virtualization, and performance budgets
- Keep two mocked data delivery shapes because they stress different Pierre and
  BridgeWeb behavior:
  - `full-load`: one deterministic package/source payload enters through
    `pushPackage(...)`; proves initial package push, projection request, content
    fetch, and selected-content materialization.
  - `streaming-append`: later package/delta publishes add ordered paths/items
    and git-status patches without forcing a full tree/model reset; proves the
    Tree/FileTree path can stay O(delta) when the backend streams a large
    review surface.
- Every browser integration test should name which boundary it proves:
  - Swift-to-Web package/delta push
  - Web-to-Swift command/RPC capture
  - Web-to-Swift-to-Web content fetch
  - worker-backed projection or markdown path
  - Pierre CodeView/FileTree browser behavior
- Every browser performance scenario must name the same boundary before timing.
  A scenario that measures only React state mutation, only Pierre item
  construction, or only fixture generation belongs in node benchmark coverage,
  not in Browser Mode performance proof.
- Mocked backend tests must include at least these failure assertions:
  - content fetch failure leaves selected item stable and renders a typed
    unavailable/error surface
  - projection failure renders a typed projection/error surface and does not
    leave stale “loading” UI
  - slow content fetch is aborted or ignored when a newer package/revision wins
  - stale markdown/projection responses cannot overwrite newer selected content
  - console error, unhandled rejection, uncaught window error, or missing metric
    JSON fails the test
- Mocked backend tests must include at least these positive interaction
  assertions before PR readiness:
  - search uses Pierre Tree search behavior with `expand-matches`, reveals a
    nested match, and does not rebuild or blank the CodeView plane
  - git-status and file-class filters route through the Bridge projection
    request path, update the right rail, and preserve a valid selected item
  - view chips for all/changed/guided/change-set/docs-plans/tests/source are
    custom controls, not native selects, and each view switch has a browser
    assertion over visible rows
  - markdown docs/plans selection uses a non-null markdown worker client or
    worker-backed test client and proves the sanitized preview is visible
  - stale content, projection, and markdown responses are aborted or ignored
    after a newer selected-content identity wins
- Browser performance fixture sizes must be explicit in the test data:
  - `small-mixed`: enough items for package push, one modified diff, one added
    file with full content, one docs markdown file, one hunk-expansion target,
    and one failure target
  - `medium-agentstudio`: source, tests, docs/plans, deleted, renamed, added,
    and modified files with realistic ordering and class/status filters
  - `large-diffshub`: enough files, hunks, and lines to require both CodeView
    and right-rail virtualization; keep added-only placeholders below the level
    where they dominate visual proof
- Performance fixtures must not treat “new file row exists” as enough. Added
  files must be selected and hydrated through the content-handle request path
  until full source text is visible in CodeView.
- Browser performance tests must be regular proof gates. A scenario records a
  duration only after its correctness assertions have passed. The metric helper
  should reject missing samples, NaN/negative timings, missing fixture metadata,
  missing worker-mode flags, and any sample whose behavior assertion failed.
- Browser performance tests must also record one compact completion row per
  scenario in the proof artifact. The row must include scenario id, metric id,
  fixture id/class, latency profile, worker modes, correctness assertion name,
  p50, p95, budget, and sample count.
- Browser performance proof must be inspectable from command output and from the
  implementation proof artifact. The executor must paste or summarize the exact
  structured rows emitted by `pnpm --dir BridgeWeb run test:benchmark:browser`,
  including the measured p95 and budget for every scenario.
- Current browser scenario status to preserve during execution:

| Scenario | Current status | Required next proof |
| --- | --- | --- |
| cold package push | covered by Browser Mode performance | keep budget and structured JSON |
| warm tree select | covered by Browser Mode performance | keep command/content assertions |
| added file full content | covered by integration and performance | keep multi-line fetched content |
| hunk expand | covered by integration and performance | keep real Pierre separator click |
| content unavailable | covered by integration and performance | keep typed unavailable state |
| scroll ownership | covered by integration and performance | keep body/root drift assertions |
| search expand-matches | covered by integration and performance | keep nested-match visibility and CodeView-preservation assertions |
| filter/projection switch | covered by integration and performance | keep Bridge projection request assertions |
| markdown worker preview | covered by worker-backed integration and performance | keep sanitized preview and unsafe-link/image assertions |
| stale/superseded result drop | partially covered by markdown stale-drop integration and performance | add package/delta/projection stale-drop proof when those delayed lanes are implemented |

### 2026-06-18 Frontend Test Hardening Delta

This delta is part of the implementation plan, not a future nice-to-have.
Browser Mode tests are the first proof layer for frontend behavior, and the
mocked backend must behave like the Bridge product boundary rather than a
shortcut into Pierre state.

Required frontend test tiers:

- Node unit/integration tests cover pure materialization, projection, Zustand,
  RPC schemas, worker clients, sanitizer behavior, and asset-audit logic. They
  do not prove real browser scroll, layout, browser worker availability, or
  virtualization correctness.
- Vitest Browser Mode integration tests mount the real React viewer with the
  real CSS/Tailwind/PostCSS path and a mocked Bridge package/delta/content/
  projection backend.
- Vitest Browser Mode performance tests use the same mocked Bridge boundary,
  assert visible behavior before sampling time, emit structured metric JSON,
  and fail on p95 budget regressions.
- Peekaboo native smoke proof is final app-shell visual proof after Browser
  Mode behavior is green; it is not a substitute for the browser test layer.

Mocked backend fixture classes:

- `small-mixed`: fast red/green fixture for package push, tree click,
  added-file full content, hunk expansion, markdown preview, unavailable
  content, and one nested search target.
- `medium-agentstudio`: realistic source/tests/docs/plans/renames/deletes
  fixture for file-class, status, guided/change-set/docs/tests/source
  projections, ordering, and selected-item preservation.
- `large-diffshub`: large tree plus large diff/hunk fixture modeled after
  DiffsHub scale demos; enough rows to require FileTree and CodeView
  virtualization, but not dominated by placeholder added files.

Mocked backend delivery modes:

- `full-load`: one package push enters through the same Bridge push path the
  native app uses.
- `streaming-append`: later package/delta pushes append or patch ordered
  paths/items/status without forcing the tree model to reset from scratch.
  Browser tests must prove the visible tree updates and the selected item
  remains valid.

Mocked backend contract checks:

- Treat the mocked backend as a typed Bridge protocol simulator. Tests should
  observe package/delta push records, projection RPC requests, content URL
  requests, command details, and fixture metadata; they should not reach into
  Pierre internals or mutate viewer state directly.
- Each non-trivial Browser Mode scenario must assert the expected backend
  ledger entries before it records performance. A fast render with missing
  `review.markFileViewed`, missing `agentstudio://resource/content/...`, stale
  projection revision, or absent package/delta push is a failed test.
- Medium and large fixtures must avoid added-only placeholder dominance. They
  need enough modified, renamed, deleted, docs/plans, tests, source, config,
  and nested paths to exercise the filters and view chips the real review flow
  exposes.
- Fixture metadata must be emitted in the performance envelope so reviewers can
  see which fixture class, delivery mode, item/path count, diff-line count,
  package byte size, latency profile, and worker modes produced each p50/p95.

Real-worktree Vite provider:

- Add a dev-only Vite provider that can point at an allowlisted local
  repo/worktree and generate the same Bridge boundary shape the Swift app sends:
  metadata-only review package first, lazy content-handle fetches second.
- The provider is a high-realism design/performance loop, not a replacement for
  deterministic mocked-backend tests or packaged WKWebView proof.
- Configure the provider through local dev configuration or environment such as
  `BRIDGE_WEB_DEV_WORKTREE`, `BRIDGE_WEB_DEV_BASE`, and
  `BRIDGE_WEB_DEV_COMPARE`; do not require raw filesystem paths in normal
  browser URLs.
- The browser must not read arbitrary local files. Vite/Node owns local
  worktree access, path allowlisting, package generation, content-handle
  creation, and bounded content serving.
- The provider must preserve the product data contract:
  - package and delta pushes contain descriptors, stats, statuses, ordered
    paths, handles, and bounded metadata only
  - source/diff/markdown bodies are returned only through content handles
  - file ordering, filtering, and class/status projection use the same zod
    schemas and discriminated unions as the mocked backend and app path
  - heavy diff generation, tree shaping, markdown preparation, or projection
    work that is not trivial must run in Node or worker lanes, not in the
    browser main thread
- Required local proof:
  - `pnpm --dir BridgeWeb run dev` or the named dev-server script can load the
    current branch/worktree as a source without a Swift rebuild
  - the large local AgentStudio branch can select files, scroll CodeView, show
    added-file full content, render docs/plans markdown, collapse/expand file
    headers, and switch file tree filters
  - `pnpm --dir BridgeWeb run test:dev-server` covers at least one large
    added-file path and one markdown docs/plan path through Playwright
  - the dev-server verifier reports the selected path, markdown path, worker
    state, and scenario URLs

Worker-backed proof requirement:

- Browser tests may mount with `codeViewWorkerPoolEnabled={false}` only as an
  app/Bridge baseline that isolates package/content/projection behavior.
- At least one Browser Mode integration test and one Browser Mode performance
  scenario must mount with the packaged Pierre worker pool enabled before PR
  readiness can claim worker-backed CodeView proof.
- The packaged-worker tests must omit `codeViewWorkerFactory` so they exercise
  the same worker asset fetch, Blob URL creation, worker factory creation, and
  post-ready CodeView hydration path used by the shipped app.
- The worker-backed scenario must assert that CodeView content is visible,
  scroll ownership still holds, no console/window/unhandled-rejection guard
  fires, and metric JSON records `codeViewWorkerPoolEnabled: true`.
- Markdown proof must still use a non-null markdown worker client or the real
  markdown worker transport path; `markdownWorkerClient: null` never satisfies
  markdown preview proof.

Stale/drop proof requirement:

- Current stale markdown proof is not enough for the whole viewer. Add browser
  integration coverage for stale package/delta and projection responses before
  PR readiness unless implementation evidence shows those delayed lanes do not
  exist in the current code path.
- Stale tests must use explicit hold/release controls instead of wall-clock
  sleeps. The newer package, revision, selected-content identity, or projection
  request must win deterministically.
- The mocked backend must provide typed pending queues for deferred content and
  projection responses. Tests release older responses after a newer selected
  content identity or projection request wins, then assert the stale response is
  ignored and the backend ledger records the superseded request.

Browser artifact hygiene:

- Set Vitest Browser Mode `screenshotDirectory` to a repo-local `tmp/` path.
  Failure screenshots are useful evidence, but they must not create
  `__screenshots__` directories under `BridgeWeb/src`.

Performance proof must include a compact summary row per scenario in the
implementation proof artifact:

- scenario id
- metric id
- fixture id and fixture class
- delivery mode
- latency profile
- worker modes
- correctness assertion
- p50
- p95
- budget
- sample count

Open split trigger:

- If worker-backed Browser Mode proof is blocked by packaged worker loading in
  Vitest/WebKit-equivalent conditions, stop and split that into a focused
  worker-packaging/browser-runtime plan. Do not silently count the
  worker-disabled baseline as product-runtime performance proof.

### Shiki Markdown Evidence

`@shikijs/markdown-exit` is a Shiki plugin with async-native rendering. The Shiki docs show `md.renderAsync(...)`, transformer support, `fromAsyncCodeToHtml(...)`, and a fine-grained/core path through `@shikijs/markdown-exit/core`. The documented examples also import `createMarkdownExit` from `markdown-exit`, so implementation must account for both the Shiki plugin package and the markdown-exit runtime package instead of adding only one dependency.

Implementation should use markdown rendering as a selected-content presentation path, not as part of the hot CodeView scroll lane.

## Architecture Target

```text
Swift Bridge runtime
  pushes package/delta metadata only
        |
        v
BridgeWeb transport
  validates schemas, updates package registry, records telemetry
        |
        v
Zustand store
  viewer state, statuses, request identities, intent queue state
        |
        +----------------------+
        |                      |
        v                      v
Projection worker        Content fetch intent
  filters/orders tree      BridgeWeb -> Swift RPC
  returns projection        agentstudio://resource/content
        |                      |
        v                      v
Review shell            selected content resources
        |
        +----------------------+----------------------+
        |                      |                      |
        v                      v                      v
Pierre FileTree          Pierre CodeView        Markdown preview
compact right rail       virtual diff/file      selected docs only
prepared input           worker highlighted     markdown worker
```

Ownership rules:

- Swift owns packages, content handles, content fetch, pane lifecycle, and transport.
- BridgeWeb transport owns schemas and typed protocol ingress.
- Zustand owns viewer UI state, selected item, projection mode/refinements, filter state, render mode, request identities, and statuses. `BridgeApp` may own integration handles and refs, but it must not duplicate these viewer state fields in local React state after the cutover.
- Worker clients own expensive projection or markdown rendering.
- Pierre CodeView owns diff/file virtualization and syntax highlighting.
- Pierre FileTree owns visible tree virtualization.
- Shell/components own visual chrome.

## Visual Acceptance Contract

The implementation is not accepted unless the debug app visually satisfies these checks:

- Main viewer canvas is exact black and fills the pane.
- CodeView is not inside a decorative card.
- The right rail is compact and visually integrated with the code plane.
- Header is compact and icon-first, with counts and compare context treated as metadata.
- No visible native browser `<select>` controls.
- Git status, file class, and projection/filter controls use custom buttons, segmented controls, or popovers.
- Search uses a custom hidden-until-open control, has no native WebKit search decorations, and is visually proven open and focused.
- Tree rows are compact, aligned, and close to the DiffsHub density.
- Tree collapse/expand affordances are not oversized.
- File icons/status colors match the surrounding rail style.
- Custom CodeView file headers show path/status/counts in a coherent compact row.
- Docs/plans markdown selected-file view renders readable prose and highlighted code blocks.
- CodeView vertical scrolling works on a large fixture.
- Right rail scrolling works independently from CodeView.
- Body/page scrolling does not steal scroll from the CodeView plane.

## Data And State Model

Introduce view/render model schemas under `BridgeWeb/src/review-viewer/models/`:

- `bridgeReviewViewModeSchema`
- `bridgeReviewFilterStateSchema`
- `bridgeReviewRenderModeSchema`
- `bridgeReviewSidebarTabSchema`
- `bridgeReviewPanelLayoutSchema`
- `bridgeMarkdownRenderRequestSchema`
- `bridgeMarkdownRenderResultSchema`

Each schema should derive a PascalCase type:

```ts
export const bridgeReviewRenderModeSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('codeView') }),
  z.object({ kind: z.literal('markdownPreview') }),
]);

export type BridgeReviewRenderMode = z.infer<typeof bridgeReviewRenderModeSchema>;
```

Use discriminated unions for:

- projection modes
- sidebar tabs
- filter choices
- render modes
- worker request/result variants
- content status
- visual proof scenarios

Do not introduce loose `any`; use `Record<string, unknown>` only for opaque external details.

## Zustand Discipline

Keep the rule explicit and testable:

```text
Zustand actions may:
  - update pure state
  - enqueue an intent/status
  - record request identity

Zustand actions may not:
  - call Swift/RPC
  - fetch content
  - post worker messages
  - mutate Pierre models
  - emit telemetry directly
```

Enforcement:

- Add unit tests around actions and intent/status transitions.
- Extend the existing `BridgeWeb/scripts/check-bridgeweb-architecture.ts` so state files cannot import:
  - `bridge-rpc-client`
  - worker transports
  - content resource loader
  - telemetry recorder/sink
  - Pierre `CodeView`/`FileTree`
- Keep side effects in coordinators/hooks/components with clear names.
- Migrate duplicated viewer state out of local `BridgeApp` `useState` fields and into the Zustand viewer store in the same slice, so selection, projection mode, refinements, filter state, render mode, and status have one write owner.

Performance reason:

- Zustand being a single write path is acceptable only if actions are small and pure.
- Heavy work must remain in workers or Pierre's virtualization/worker lanes.
- React components should subscribe to narrow selectors, not whole-package snapshots, when adding new state.
- Debug mode should emit enough logs/metrics/traces around worker queue,
  execution duration, stale-drop/abort counts, fallback reasons, and render/data
  preparation duration to identify when a lane steals budget from review
  interaction.

## Worker Lanes

Keep three separate lanes:

```text
Projection worker
  owns filtering, ordering, grouping, and derived projection.

Pierre worker pool
  owns CodeView syntax highlighting.

Markdown worker
  owns markdown-exit parsing and Shiki-highlighted code blocks for selected docs.
```

Do not reuse the Pierre CodeView worker pool for markdown. It is CodeView-owned.
Do not add a main-thread markdown/Shiki fallback. If the markdown worker cannot
be packaged and audited, fall back to CodeView source rendering or stop and
replan.

Future heavy-work lanes should mirror this shape instead of expanding main
thread responsibilities: define zod request/result schemas, create a typed
worker client/transport, record queue/run/drop telemetry, and let React render
only the returned view model.

The markdown worker should mirror the existing projection-worker pattern:

- `workers/markdown/bridge-markdown-render-worker-rpc.ts`
- `workers/markdown/bridge-markdown-render-worker-client.ts`
- `workers/markdown/bridge-markdown-render-worker-transport.ts`
- `workers/markdown/bridge-markdown-render-worker-entry.ts`
- sync fallback only inside worker/client unit tests, not in product runtime

Update:

- `BridgeWeb/tsdown.config.ts` with the markdown worker entry.
- `BridgeWeb/scripts/build-app-assets.ts` to include the generated worker asset.
- `BridgeWeb/scripts/audit-dependencies-and-assets.ts` dependency and worker self-containment checks.
- `BridgeWeb/scripts/check-bridgeweb-architecture.ts` and its proof path must explicitly allow the new `src/review-viewer/workers/markdown/` lane while preserving the existing ban on worker usage from state and shell files.

## Markdown Rendering Policy

Render markdown preview only when all of these hold:

- selected item is markdown by `language === 'markdown'`, extension `.md`/`.mdx`, or docs/plans classifier
- selected content resolves to a single current document body
- item is a file or one-sided added/deleted markdown view

Keep CodeView when:

- item has base and head resources
- item is a true two-sided diff
- content is too large for markdown preview budget
- markdown worker fails or times out

Security policy:

- Treat repository markdown as untrusted.
- Raw HTML must remain disabled for v1.
- Keep link validation behavior and block unsafe URL schemes.
- Markdown links are inert in v1. Do not implement external-open behavior in this slice. `agentstudio`, `file`, `data`, `javascript`, custom app schemes, relative internal navigation, and raw active `href` attributes must be rejected or stripped.
- The approved v1 render sink is sanitized HTML inserted by a dedicated markdown preview component. Add `dompurify` as a direct dependency and sanitize every `markdown-exit` result immediately before DOM insertion, even with raw HTML disabled.
- The sanitizer policy must strip script-capable tags/attributes, inline event handlers, active link `href`s, image `src`s, remote image loads, and app/internal navigation schemes.
- Images are disabled in v1. Do not load arbitrary remote, `file:`, or `data:` images in this slice.
- Before markdown render mode consumes content handles, validate selected handle `resourceUrl` values with the existing Bridge content-resource URL parser. Malformed nested handle/resource metadata falls back to CodeView or unavailable-content UI instead of being fetched/rendered as markdown.

Performance policy:

- Render markdown lazily for the selected item only.
- Cancel/drop stale worker results when selection changes.
- Do not render all markdown docs in the package.
- Add large-markdown benchmark coverage with fenced code blocks.
- Record markdown fallback reasons and worker render timings in debug/telemetry
  proof so slow or unexpected fallbacks are visible.

## Task Sequence

### Task 0: Re-Anchor And Baseline Visual Proof

Read the source coverage listed above, then capture the current debug app with Peekaboo.

Write surfaces:

- `tmp/bridge-viewer-visual-proof/<timestamp>/baseline-*.png`
- `tmp/bridge-viewer-visual-proof/<timestamp>/baseline-notes.md`

Proof:

- `peekaboo permissions status`
- `peekaboo list apps --json`
- `peekaboo list windows --app "Agent Studio Debug <code>" --json`
- `peekaboo see --app "Agent Studio Debug <code>" --window-title "AgentStudio" --path <baseline>.png --json`

Do not edit product code in this task.

### Task 0.5: Add Browser-Mode Frontend Test Harness

Add the BridgeWeb testing surface needed to prove real viewer behavior without
launching the native debug app for every frontend bug.

Likely files:

- `BridgeWeb/package.json`
- `BridgeWeb/pnpm-lock.yaml`
- `BridgeWeb/vitest.config.ts`
- `BridgeWeb/vitest.browser.config.ts`
- `BridgeWeb/postcss.config.mjs`
- `BridgeWeb/tests/vitest-browser-setup.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser-dom.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx`
- `BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.ts`

Requirements:

- Add direct dev dependencies needed for Vitest Browser Mode with Playwright.
- Add the Tailwind v4 PostCSS path used by Vite/Vitest Browser Mode. The
  production build may still run Tailwind through the CLI, but browser tests
  must process `@import 'tailwindcss'` so layout/scroll proof tests the real
  surface rather than an unstyled document.
- Keep provider dependencies version-aligned with the installed Vitest package.
  If using Vitest 3.2.x, first verify whether `@vitest/browser` already exposes
  the Playwright provider locally. If upgrading to a provider package, update the
  plan with the exact version reason before changing the package graph.
- Keep the test config split explicit:
  - `BridgeWeb/vitest.config.ts` owns fast node unit/integration/e2e-style tests.
  - `BridgeWeb/vitest.benchmark.config.ts` owns node deterministic benchmark tests.
  - `BridgeWeb/vitest.browser.config.ts` owns browser integration and browser
    performance projects.
- Add or preserve scripts:
  - `test:browser`
  - `test:browser:integration`
  - `test:benchmark:browser`
- Browser tests must run against Chromium through the Playwright provider.
- Use `vitest-browser-react` or the currently recommended Vitest Browser React
  render utilities for React component mounting, unless the installed Vitest
  version provides an equivalent first-party helper.
- Browser integration files use `.browser.test.tsx`.
- Browser performance files use `.browser.benchmark.ts` or
  `.browser.benchmark.tsx`, or live under a clearly named benchmark folder.
- The mocked backend must model the Bridge product boundary, not Pierre internals:
  - package/delta push
  - generation/checkpoint replacement
  - typed RPC command recording
  - content handle fetch responses
  - bounded fetch latency injection
  - fetch error injection for one negative test
  - projection worker error injection for one negative test
  - stale package/delta generation for stale-result tests
  - selected-file content hydration
  - mark-viewed command capture
  - deterministic fixture sizes and timing probes
- The mocked backend should expose a small typed scenario API instead of
  test-local ad hoc maps:
  - `pushPackage(...)` / `pushDelta(...)` for Bridge push lanes
  - `setLatencyProfile(...)` or constructor options for deterministic latency
  - `failContentHandle(...)` for fetch-error scenarios
  - `failProjectionRequest(...)` for projection-error scenarios
  - request ledgers for content URLs, projection RPCs, and app commands
  - fixture metadata helpers for item count, path count, diff line count, and
    approximate package bytes
- Mock fixtures must include:
  - a mixed small fixture for fast red/green behavior
  - a medium AgentStudio-like fixture with source, tests, docs/plans, added,
    modified, deleted, and renamed entries
  - a large DiffsHub-style fixture with enough files and hunks to require both
    CodeView and right-rail scrolling
  - a multi-line added source file whose content is only available through the
    mocked content-handle fetch path
  - a collapsed unchanged-section diff that can only pass by clicking Pierre's
    interactive `line-info` separator
- The harness must fail tests on console page errors and unhandled promise rejections.
- Browser performance tests run sequentially to avoid noisy timing, and must assert
  behavior before recording timings so a blank or stuck viewer cannot pass as
  "fast".
- Browser performance tests are a required PR proof gate for this slice. They
  must run through the mocked Bridge backend in Chromium Browser Mode, not
  through jsdom, a node-only benchmark, or a handcrafted static fixture page.
- Browser performance tests must record structured metrics to stdout, including
  p50, p95, budget, sample count, raw sample values, fixture id/class, item
  count, path count, diff line count, package byte count when available,
  viewport size, backend latency profile, and worker mode flags. The first
  required budget is package push to interactive browser state on the mocked
  backend; later scenarios must follow the same metric envelope.
- Browser performance samples must be dual-entry proofs: every timed scenario
  must assert a visible product result and the matching mocked Bridge ledger
  entry before sampling duration. Required ledgers are push records, projection
  RPCs, content URLs for content-bearing selections, and command details for
  interactions such as mark-viewed. Missing ledger entries, wrong fixture
  metadata, no visible row change, body/page scroll drift, or worker-mode
  mismatch fail the performance test even when duration is below budget.
- Browser performance tests must include both cold and warm paths. Cold paths
  start from app mount/package push. Warm paths start after the viewer and
  worker clients are available and measure user actions such as tree selection,
  search/filter, hunk expansion, markdown selection, and independent scroll.
- Browser behavior tests may inject `codeViewWorkerPoolEnabled={false}` only to
  isolate app/Bridge behavior from Pierre's packaged Shiki worker lane. That is
  not product runtime behavior. A separate packaged-worker proof remains
  required before claiming full worker-backed CodeView proof.
- Add a dedicated worker-backed Browser Mode integration test that mounts with
  `codeViewWorkerPoolEnabled={true}` and the packaged Pierre worker pool path.
  It must assert visible CodeView content, scroll ownership, and clean browser
  failure guards.
- Add a dedicated worker-backed Browser Mode performance scenario or scenario
  variant that records `codeViewWorkerPoolEnabled: true` in metric JSON. The
  current worker-disabled baseline cannot satisfy product-runtime performance
  proof by itself.
- Extend the mocked backend fixture typing beyond `small-mixed` before PR
  readiness. `medium-agentstudio` and `large-diffshub` must be first-class
  fixture classes with explicit item/path/diff-line/package-byte metadata.
- Add hold/release controls for delayed package/delta, projection, content, and
  markdown responses so stale-result tests are deterministic and do not use
  wall-clock sleeps.
- Add or preserve dedicated unit tests for the mocked backend itself. These
  tests must prove handshake request/response, package vs delta push records,
  command ledgers, requested content URL ledgers, deferred content/projection
  queues, failure profiles, and fixture metadata invariants for `small-mixed`,
  `medium-agentstudio`, and `large-diffshub`. Browser tests may then rely on
  the mocked backend without duplicating all harness assertions.
- Add direct projection-coordinator tests for the seam that chooses sync vs
  worker projection, starts requests, applies successful results, ignores stale
  completions, marks failures, records telemetry, and flushes telemetry only
  after an applied success.
- Add content-loader negative-path tests for aborted fetch, non-OK responses,
  missing handles, selected-handle item/role/generation mismatch,
  stale selected-content identity, and selected added/deleted content resources
  where the content-handle shape differs from a modified two-sided diff.
- Add a durable browser-performance artifact/verifier path. It may capture
  structured rows from `test:benchmark:browser` stdout or write browser JSONL
  directly, but it must fail when required scenarios, fixture metadata, worker
  flags, correctness assertions, p50/p95, budgets, sample counts, scoped Bridge
  content URLs, push/command/projection ledgers, or exact scenario contracts are
  missing. The verifier must recompute p50/p95 from raw samples and fail if
  reported percentiles drift. Keep this separate from the existing node
  benchmark verifier because browser rows prove visible Chromium behavior and
  node rows prove deterministic algorithmic workload costs.

Proof:

- A tiny browser smoke test mounts the viewer and proves the harness can receive a mocked package push.
- A browser integration test proves mocked content fetch hydrates a selected file.
- A browser integration test proves the mocked projection worker RPC receives
  `reviewProjection.build` before the viewer is considered ready.
- Browser integration tests prove:
  - tree click changes the selected CodeView item and does not snap back
  - added-file click fetches and renders full multi-line content
  - collapsed unchanged-section click expands additional unchanged lines
  - CodeView scroll changes visible code without moving the right rail
  - right-rail scroll changes visible tree rows without moving CodeView
  - status/file-class filters and view switches update the tree without
    rebuilding source shape unnecessarily
  - search uses Pierre `fileTreeSearchMode: 'expand-matches'` and expands the
    matched branch instead of depending on the branch already being open
  - content fetch failure renders a typed unavailable/error state and does not
    leave selection, request identity, or command status hanging
  - stale package/delta generation cannot apply older selected content or
    markdown worker results over a newer package/revision/content cache key
- Browser integration tests prove the mocked backend contract itself:
  - the test fails if a scenario records no projection request
  - the test fails if a content-bearing selection records no content URL
  - the test fails if a command expected from user interaction is not captured
  - failure-profile tests assert request ledgers and visible error states
- A browser performance smoke run records fixture id, file count, diff line count,
  package bytes, mounted row/window count if available, and interaction timing.
- A worker-backed browser integration proof mounts with packaged CodeView worker
  support enabled and proves visible code, scroll ownership, and no failure
  guard trips.
- A worker-backed browser performance proof emits a metric row with
  `codeViewWorkerPoolEnabled: true`.
- Medium and large mocked-backend fixtures each have at least one Browser Mode
  behavior assertion and one performance metric row before PR readiness.
- Browser performance budgets must be explicit in the test-support file and
  scenario-specific. Initial budgets can be generous while the fixture is
  stabilizing, but they must fail on pathological regressions such as blank
  render, no selected-content change, inert hunk expansion, no visible-row
  change after scroll, body/page scroll drift, main-thread long interaction
  above the agreed budget, or missing performance sample output.
- Mocked-backend contract tests pass and prove fixture metadata, handshake,
  push ledgers, request ledgers, command ledgers, deferred queues, and typed
  failure controls before Browser Mode scenarios count as reliable proof.
- Projection-coordinator unit tests pass and prove sync/worker lane selection,
  stale completion ignoring, failure completion handling, and telemetry
  flushing semantics.
- Content-loader unit tests pass for negative paths and stale identity changes,
  so Browser Mode failures can be diagnosed without treating the whole app as a
  black box.
- Browser performance proof emits or captures a durable artifact and a verifier
  checks required scenario ids, metric ids, fixture metadata, worker modes,
  correctness assertion names, raw samples, p50, p95, budgets, and sample counts.
- The mocked backend proof must be dual-entry: every performance scenario proves
  both the UI result and the Bridge boundary. Required ledgers are package/delta
  push records, projection requests, content URLs for content-bearing
  selections, and command details for user actions such as mark-viewed. A
  scenario that reaches a visible row without the expected Bridge ledger entry
  is a failed scenario.

### Task 1: Introduce BridgeWeb Review Chrome Primitives

Create local BridgeWeb UI primitives so the shell stops hand-rolling inconsistent controls.

Likely files:

- `BridgeWeb/src/components/ui/button-group.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-button.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-button-group.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-popover.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-filter-menu.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-icons.tsx`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-chrome-models.ts`
- `BridgeWeb/src/review-viewer/chrome/bridge-review-chrome.unit.test.tsx`

Requirements:

- Use `BridgeWeb/components.json` as the shadcn contract:
  `style: "base-mira"`, Base UI primitives, Tailwind v4 CSS variables,
  lucide icons, small-radius compact control variants.
- Generate or add the missing shadcn-style `ButtonGroup` primitive before
  building feature-local segmented controls. If the current CLI cannot generate
  a Base UI version, compose it from the generated `Button` primitive and
  document that fallback in the implementation proof.
- Tailwind v4 classes only, merged through existing `cn`.
- Icon-first controls where a familiar symbol exists.
- Text only where meaning would be unclear.
- No native select styling.
- Dark-only tokens mapped to Catppuccin Mocha through shadcn semantic variables
  and Bridge/Pierre aliases. Avoid raw one-off RGB/hex values in feature-local
  chrome unless the value is a named token in `bridge-app.css`.
- Components are presentational and do not import app transport, workers, or content loaders.

Proof:

- Vitest structural tests prove filter menus are custom controls and no `<select>` is rendered by shell.
- Typecheck proves schemas/types are explicit.

### Task 2: Rebuild The Shell Layout Around A Right Review Rail

Refactor `ReviewViewerShell` into smaller components because the current 430-line shell owns too much.

Likely files:

- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- `BridgeWeb/src/review-viewer/shell/bridge-review-main-layout.tsx`
- `BridgeWeb/src/review-viewer/shell/bridge-review-right-rail.tsx`
- `BridgeWeb/src/review-viewer/shell/bridge-review-filter-controls.tsx`
- `BridgeWeb/src/review-viewer/shell/bridge-review-stats.tsx`
- `BridgeWeb/src/app/bridge-app.css`

Requirements:

- Preserve `data-sidebar-position="right"`.
- Remove detached plain text metadata/app bars. If summary/projection controls
  remain in the top plane, they must use compact shadcn/Catppuccin chrome that
  visually belongs to the surrounding app surface.
- Move projection/filter affordances into compact chrome; the projection mode
  control should be a shadcn-style ButtonGroup/segmented toggle, not a dropdown
  or pure-black pill row.
- Keep counts visible but quiet in the right rail stats region.
- Keep the code plane full-height with `min-height: 0` through every flex/grid parent.
- Right rail has its own scroll region and does not resize the CodeView plane on hover/filter changes.

Proof:

- Existing shell tests updated from old labels to structural expectations.
- Tests assert no native selects.
- Tests assert right rail exists and uses custom filter controls.
- Tests and visual proof assert no detached `bridge-review-top-header`/metadata
  strip exists. Compact integrated header-plane controls may exist only if their
  background, height, radius, typography, and spacing match the app chrome.
- Visual proof captures CodeView and the right rail against the live worktree dev server.

### Task 3: Fix Scroll Ownership

Make scrolling an explicit layout invariant.

Requirements:

- Main pane owns one vertical CodeView scroll container.
- Right rail owns a separate vertical tree/filter scroll container.
- `body` and shell root do not become the scroll container for review content.
- CodeView works with a large fixture without trapping on a blank area.
- File rail can scroll while CodeView remains stable.

Likely files:

- `BridgeWeb/src/review-viewer/shell/bridge-review-main-layout.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- `BridgeWeb/src/app/bridge-app.css`
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.integration.test.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.ts`

Proof:

- Add a large visual fixture with enough files/hunks to require CodeView scrolling.
- Add unit/component tests for the required layout classes where the node test
  lane can prove structure.
- Add Vitest Browser Mode tests with a mocked backend that:
  - scroll the CodeView plane and assert the visible file/hunk changes
  - scroll the right rail and assert the tree position changes
  - assert `document.scrollingElement` and the shell root do not become the active review scroll owner
  - assert clicking another visible tree item changes the selected CodeView item and does not snap back to the previous file
- Add one mandatory programmatic scroll-ownership proof:
  - either a node/browser runtime test proving the CodeView scroll container and rail scroll container change while `document.body` and shell root do not
  - or a debug IPC/diagnostic proof recording before/after scroll state for the actual containers
- Add a visual/manual proof script or checklist using Peekaboo:
  - capture top of CodeView
  - scroll the CodeView region
  - capture after scroll
  - verify visible hunk/file changed
  - scroll the right rail
  - verify tree position changed without body/page drift
- Record scroll container `scrollTop` before/after in the proof artifact when the debug IPC/diagnostic path is used.

### Task 4: Tune Pierre FileTree For Review Density

Refactor `BridgeReviewTreesPanel` so FileTree feels like the DiffsHub rail.

Likely files:

- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-controller.ts`
- `BridgeWeb/src/review-viewer/trees/bridge-tree-theme.ts`
- `BridgeWeb/src/review-viewer/trees/bridge-review-tree-controls.tsx`

Requirements:

- Use `preparedInput` / `preparePresortedFileTreeInput(...)` from the existing source boundary.
- Preserve review/projection order with `sort: () => 0`.
- Reduce row height to about 24px unless visual proof shows it harms readability.
- Tighten inline padding and chevron affordances.
- Resolve/apply the Catppuccin/Pierre theme through `themeToTreeStyles(...)`
  before adding Bridge-specific FileTree variables. Do not rebuild the FileTree
  palette from raw shadow-DOM selectors.
- Hide search until toggled, and configure Pierre `fileTreeSearchMode: 'expand-matches'`.
- Support quick view switches:
  - all
  - changed
  - guided
  - change set
  - docs/plans
  - tests
  - source
- Support git-status and file-class filters with custom menus.
- Avoid rebuilding tree shape on every small filter change when projection already owns ordering/filtering.

Proof:

- Unit tests for tree source ordering and prepared input.
- Integration tests for filter/search projection updates.
- Vitest Browser Mode tests for real tree behavior:
  - expand/collapse folder paths
  - search with `fileTreeSearchMode: 'expand-matches'`
  - click a file row and verify selected content changes
  - switch All/Changed/Guided/Change set/Docs/plans/Tests/Source quickly without rebuilding avoidable client shape
- Benchmark workload covers thousands of paths and large changed-file sets.
- Update `BridgeWeb/scripts/bridge-viewer-benchmark.benchmark.ts`, `BridgeWeb/scripts/verify-bridge-viewer-benchmark.ts`, and any row-height/visible-row budgets so benchmark proof reflects the new tree density instead of stale 28px assumptions.

### Task 5: Tune CodeView Options And Headers

Make CodeView match the compact DiffsHub review style.

Likely files:

- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-header.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-materialization.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.integration.test.tsx`

Requirements:

- Use Pierre/Shiki `catppuccin-mocha` as the CodeView dark theme. If BridgeWeb
  must register a packaged local theme to satisfy WKWebView/worker asset
  self-containment, do not register it under the same name in a way that masks
  Pierre's supported theme without an explicit adapter/test proving equivalence.
- Tighten `layout.paddingTop`, `layout.paddingBottom`, and `layout.gap`.
- Use Pierre's interactive unchanged-section settings:
  - `hunkSeparators: 'line-info'`
  - explicit `expansionLineCount`
  - explicit `collapsedContextThreshold`
  - `expandUnchanged` only for fixtures or modes where always-expanded context is intentional
- Use CodeView header hooks rather than outer cards.
- Show compact path/status/count metadata in file headers.
- Keep added-only/deleted-only/new-file cases readable.
- Prove added-only/new-file cases hydrate into full CodeView file content after
  content fetch, not empty rows.
- Added files with fetched full content must render as Pierre `type: 'file'` items with the full `file.contents` text unless a future explicit design chooses a one-sided diff view.
- Do not regress virtualization or worker highlighting.

Proof:

- Tests prove CodeView receives custom header hooks/options.
- Tests prove the exact Pierre expansion options are passed.
- Vitest Browser Mode tests click collapsed unchanged-line separators and verify additional unchanged lines appear.
- Vitest Browser Mode tests open an added file and verify full fetched content appears, including multi-line source content.
- Visual proof captures custom header style.
- Benchmark verifies large fixture render/hydration stays inside accepted thresholds.

### Task 6: Add Markdown Preview Rendering

Add selected-file markdown preview as a parallel render mode beside CodeView.

Likely files:

- `BridgeWeb/package.json`
- `BridgeWeb/pnpm-lock.yaml`
- `BridgeWeb/tsdown.config.ts`
- `BridgeWeb/scripts/build-app-assets.ts`
- `BridgeWeb/scripts/audit-dependencies-and-assets.ts`
- `BridgeWeb/src/review-viewer/markdown/bridge-markdown-render-mode.ts`
- `BridgeWeb/src/review-viewer/markdown/bridge-markdown-preview.tsx`
- `BridgeWeb/src/review-viewer/markdown/bridge-markdown-renderer.ts`
- `BridgeWeb/src/review-viewer/workers/markdown/*`
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`

Requirements:

- Use `@shikijs/markdown-exit`.
- Add every direct runtime package needed by the chosen integration: `@shikijs/markdown-exit`, `markdown-exit`, `dompurify`, and explicit Shiki packages if using the fine-grained/core path. Do not rely on transitive `shiki` from `@pierre/diffs`.
- Packaging rule: the markdown worker must emit a self-contained packaged worker asset that passes the existing worker self-containment audit. Do not leave runtime dynamic imports, network fetches, or unpackaged `shiki/wasm` dependencies in the emitted worker.
- Allowed Shiki strategy: use a no-runtime-WASM bundle/engine or a fully packaged manifest-backed asset strategy proven by `pnpm --dir BridgeWeb run build`. If the fine-grained/core path cannot satisfy the worker audit, stop and replan instead of quietly falling back to a non-audited worker.
- Render selected markdown only.
- Raw HTML disabled.
- Remote image loading disabled.
- Stale worker results are dropped when selection changes.
- Markdown render request identity includes package id, review generation, revision, item id, item version, and selected content cache key/hash. The same item id across a later delta must not accept an older worker result.
- Two-sided markdown diffs remain in CodeView.
- Markdown preview CSS matches the dark review surface and does not create a separate light page.

Proof:

- Unit tests for render-mode selector.
- Worker RPC schema tests.
- Worker transport/client tests for construction failure, malformed response, error event, postMessage failure, abort/stale response, and fallback to CodeView/unavailable preview.
- Markdown rendering tests for headings, paragraphs, fenced code, unsafe HTML, unsafe links, and stale result drops.
- Markdown security tests for image sources:
  - `http` / `https`
  - `file:`
  - `data:`
  - custom or non-allowlisted schemes
- Tests must prove `img` elements and image `src` attributes are stripped entirely.
- Resource URL validation tests cover malformed nested `resourceUrl`, wrong scheme, wrong host, wrong path, missing generation, and valid `agentstudio://resource/content/{handleId}?generation=...`.
- Stale-result tests cover the same `itemId` receiving a newer package/revision/content cache key before the earlier markdown worker result returns.
- Vitest Browser Mode integration proves a selected docs/plans markdown file
  renders through the markdown worker/client path with sanitized prose and
  highlighted fenced code visible.
- Vitest Browser Mode integration proves worker-disabled shell tests are not
  counted as markdown proof; a non-null markdown worker client or worker-backed
  test client is required for this row.
- Build/audit proves new dependencies and worker assets are packaged.
- Visual proof captures selected markdown doc in the debug app.

### Task 7: Preserve State/Data Flow Boundaries

Move side effects out of store actions where current or new UI pressure would tempt drift.

Likely files:

- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
- `BridgeWeb/src/review-viewer/runtime/*`
- `BridgeWeb/scripts/check-bridgeweb-architecture.ts`

Requirements:

- Store actions stay pure.
- New menus/controls dispatch state changes or intents only.
- RPC/content fetch remains in app/runtime coordinators.
- Worker calls remain in hooks/clients/coordinators.
- Telemetry remains in telemetry adapters/coordinators.
- Move `loadSelectedReviewItemContentResources(...)` and content-role selection out of `review-viewer/shell/` into `review-viewer/runtime/` or another non-shell coordinator before markdown render mode is added.
- Shell files render from props and must not import `foundation/content/*` after the cutover.
- Viewer state has one owner: Zustand owns selection, projection/filter/render-mode state, request identities, and statuses; local React state in `BridgeApp` is limited to integration refs/handles and non-viewer host lifecycle.

Proof:

- Architecture check forbids forbidden imports from state files.
- Store unit tests cover actions.
- Runtime/coordinator tests cover side effects.

### Task 8: Visual Proof And Performance Fixture Loop

Create proof fixtures modeled on the DiffsHub demos:

- small mixed source/docs fixture for visual regression.
- medium AgentStudio-like fixture.
- large DiffsHub-style fixture with many files/hunks and fewer added-only placeholder files than the current ugly fixture.
- added-file fixture that proves selected new files show full source content.
- markdown docs fixture with fenced code.
- failure/latency fixture profiles for fetch failure, projection failure,
  slow-but-bounded content fetch, and stale package/delta replacement.

Fixture ownership:

- `bridge-viewer-mocked-backend.ts` owns browser-interactive fixtures and
  backend profiles because those tests exercise transport/content/request
  behavior.
- `review-viewer-fixtures.ts` owns compact deterministic projection fixtures for
  node tests.
- `bridge-viewer-benchmark-workloads.ts` owns deterministic large node
  workloads for projection/tree/diff workload budgets.
- Browser performance cannot claim node benchmark coverage unless the same
  scenario is mounted through Browser Mode and the mocked backend.

Likely files:

- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.ts`
- `BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts`
- `tmp/bridge-viewer-visual-proof/<timestamp>/`

Proof:

- Run BridgeWeb benchmark tests.
- Run Vitest Browser Mode behavior tests and browser performance tests against the mocked backend fixture.
- Record file count, additions, deletions, line count, package bytes, projection duration, tree update duration, CodeView hydration duration, markdown render duration.
- Record browser runtime metadata: Chromium version if available, viewport size,
  device scale factor, fixture id, fixture seed, and whether workers were used.
- Record interaction timings for:
  - package push to first rendered viewer
  - tree click to selected CodeView item visible
  - added-file click to full content visible
  - collapsed unchanged-section click to expanded lines visible
  - search text to matched tree row visible
  - projection/filter switch to updated tree and CodeView list visible
  - content-fetch failure to typed unavailable/error state visible
  - stale package/delta push to stale-result drop recorded
  - CodeView scroll to visible-code-window change
  - right-rail scroll to visible-tree-window change
- Initial browser performance scenarios:
  - `bridge.viewer.browser.cold_package_push.interactive_ms`
    proves package push, projection request, first content fetch, and first
    selected CodeView content are visible.
  - `bridge.viewer.browser.warm_tree_select.visible_ms`
    proves a right-rail row click captures `review.markFileViewed`, fetches the
    selected handle, and shows different selected code without snapping back.
  - `bridge.viewer.browser.warm_added_file.visible_ms`
    proves added files render full fetched content instead of placeholder rows.
  - `bridge.viewer.browser.warm_hunk_expand.visible_ms`
    proves Pierre hunk separator interaction changes visible unchanged lines.
  - `bridge.viewer.browser.warm_search.expand_matches_ms`
    proves FileTree search uses `expand-matches` and reveals a nested match.
  - `bridge.viewer.browser.warm_filter_switch.visible_ms`
    proves file status/class filters and view-switch chips update the tree
    using prepared input rather than rebuilding the whole app shell.
  - `bridge.viewer.browser.warm_markdown_preview.visible_ms`
    proves markdown worker output is sanitized and visible for a selected docs
    file.
    This scenario must mount with a non-null markdown worker client or a
    worker-backed test client that exercises the same typed request, stale-drop,
    sanitize, and render-result path. A `markdownWorkerClient: null` mount does
    not satisfy markdown browser performance proof.
  - `bridge.viewer.browser.failure_content_unavailable.visible_ms`
    proves fetch failure reaches a typed unavailable state and records the
    failed request.
  - `bridge.viewer.browser.stale_generation_drop.visible_ms`
    proves stale package/content/markdown/projection results are ignored after a
    newer generation or revision wins.
  - `bridge.viewer.browser.warm_scroll_ownership.visible_ms`
    proves CodeView scroll and right-rail scroll each change their own visible
    window while `document.scrollingElement` and the review shell root remain
    stable.
- Separate cold and warm measurements:
  - cold render after package push
  - warm tree selection after viewer is mounted
  - warm filter/search after prepared tree input exists
  - warm content fetch/hydration after worker and CodeView assets are loaded
- Each measurement must use a named metric id under
  `bridge.viewer.browser.*` and write one structured JSON line with the same
  envelope used by Task 0.5. Do not rely on human-readable console text as the
  only benchmark output.
- Store or print a compact scenario summary suitable for the implementation
  proof artifact:
  - scenario id
  - metric id
  - fixture id
  - fixture class
  - delivery mode
  - latency profile
  - worker modes
  - correctness assertions passed
  - p50
  - p95
  - budget
  - sample count
- Include medium and large fixture scenarios before PR readiness:
  - `medium-agentstudio` must have one behavior assertion and one performance
    row for filter/projection/search or streaming append behavior.
  - `large-diffshub` must have one behavior assertion and one performance row
    that proves virtualization-facing scroll or cold package push behavior.
  - A worker-disabled row may prove the Bridge package/content/projection
    contract, but worker-backed CodeView proof requires a separate row with
    `codeViewWorkerPoolEnabled: true`.
- Use deterministic mocked backend latency buckets:
  - zero-latency baseline for pure frontend/render cost
  - small latency bucket for normal content fetch behavior
  - slow-but-bounded latency bucket for cancellation/stale-drop behavior
  - one failure bucket for error UI and command/status accounting
- Fail the performance test if correctness assertions fail before timing is sampled.
  A blank viewer, stuck selected file, missing added-file content, or inert hunk
  separator is a failed performance result, not a fast result.
- Capture Peekaboo screenshots:
  - overview/top
  - scrolled CodeView
  - scrolled right rail
  - filter menu open
  - markdown preview
  - large fixture

### Task 9: Validation And PR Readiness

Required commands:

```bash
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test:browser
pnpm --dir BridgeWeb run test:benchmark:browser
mise run bridge-viewer-benchmark
pnpm --dir BridgeWeb run fmt:check
pnpm --dir BridgeWeb run lint:types
pnpm --dir BridgeWeb run typecheck
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run build
mise run lint
mise run test -- --filter Bridge
git diff --check
```

Generated asset hygiene is part of the validation gate. `pnpm --dir BridgeWeb
run build` and the `mise` BridgeWeb build/setup tasks must reproduce packaged
BridgeWeb resources from checked-in source, scripts, fixtures, and lockfiles.
Do not stage generated native app resource bundles, `dist` output, or copied
packaged app assets unless a future release plan explicitly changes that
ownership model.

If the implementation touches telemetry or debug runtime proof, run the full smoke/verify sequence for Bridge observability rather than the verifier alone:

```bash
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-bridge-observability
```

If the implementation changes Swift runtime or Bridge IPC:

```bash
mise run test
```

Swift IPC is a follow-on lane after the browser/DiffsHub UX loop is proven. If a
separate IPC subagent works in parallel, keep its write set disjoint from
BridgeWeb visual/theming files and do not let IPC proof substitute for
dev-server/browser visual proof.

If `mise run test-fast` or GitHub CI times out outside this slice, do not change CI harness as part of this plan. Report it as unrelated infrastructure unless the user expands scope.

## Requirements/Proof Matrix

| Requirement | Owning task | proof owner: | Proof gate | Layer | stale-proof guard: | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| Dark DiffsHub-style shell with black canvas | 1, 2 | executor + visual reviewer | Peekaboo screenshots and shell tests | smoke/manual + unit | current debug app capture after rebuild | red baseline screenshot, green final screenshot |
| Right-side compact file rail | 2, 4 | executor | shell structural tests and Peekaboo | unit + smoke/manual | assert `data-sidebar-position="right"` in current code | green required |
| No detached top metadata strip | 2, 8 | executor | shell structural tests and visual proof script | unit + smoke/manual | reject detached `bridge-review-top-header`/metadata strips; allow only integrated compact shadcn/Catppuccin header-plane chrome | red/green required |
| No native select controls | 1, 2 | executor | shell tests query absence of `select` | unit | inspect built shell, not only component source | red current tests/text, green absence |
| Custom filter/menu controls | 1, 2 | executor | component tests and screenshot with menu open | unit + smoke/manual | menu proof captured in debug app | green required |
| CodeView scroll works | 3 | executor + visual reviewer | Vitest Browser Mode scroll test plus Peekaboo large-fixture capture | integration/browser + smoke/manual | body/root must not be the scroll owner; selected visible code must change | red current behavior, green final |
| Right rail scroll independent | 3, 4 | executor + visual reviewer | Vitest Browser Mode rail virtualized-scroll test plus Peekaboo rail scroll proof | integration/browser + smoke/manual | Trees virtualized-scroll surface exists and body/page do not drift; manual proof covers visible row changes | green required |
| FileTree dense and fast | 4 | executor | browser behavior tests + benchmark | integration/browser + benchmark | fixture includes thousands of paths and prepared/presorted input | green required |
| CodeView custom headers and added-file content | 5 | executor | CodeView option/header/materialization tests + screenshot | unit + smoke/manual | prove hook is passed to CodeView and added selected file hydrates full content | green required |
| Markdown preview for selected docs | 6 | executor | markdown unit tests, Browser Mode markdown integration, and screenshot | unit + integration/browser + smoke/manual | fixture uses real selected markdown content and non-null markdown worker/client path | red/green required |
| Markdown security policy | 6 | executor + security reviewer | DOMPurify sink plus unsafe HTML/link/image/resource URL tests | unit/security | raw HTML disabled; sanitized DOM insertion; no remote image load | green required |
| Worker separation | 6, 7 | executor | architecture tests and worker RPC tests | unit/integration | no Pierre worker reuse for markdown | green required |
| Zustand discipline | 7 | executor | architecture import guard + store tests | unit/architecture | check real files, not convention docs only | green required |
| Bundle/asset integrity | 6, 9 | executor | BridgeWeb build and audit | build | generated packaged assets are reproducible build outputs and not checked in as source; generated manifest includes markdown worker | green required |
| Performance not regressed | 8, 9 | executor | benchmark and observability verifier | benchmark + observability | compare named workload metrics, not anecdote | green required |
| Native debug visual proof | 0, 8 | executor | Peekaboo proof artifact | smoke/manual | current app/window id captured | green required |
| Browser-mode mocked backend harness exists | 0.5 | executor | `pnpm --dir BridgeWeb run test:browser` | integration/browser | test runs in Chromium via Vitest Browser Mode, not jsdom, with package push/RPC/content-handle mocks | red/green required |
| Browser global failure guards exist | 0.5, 9 | executor | Browser Mode setup guard test or forced-console-error fixture | integration/browser | setup fails on console error, unhandled rejection, and uncaught window error unless explicitly allowlisted | red/green required |
| Browser page-error guard is resolved | 0.5, 9 | executor | Browser Mode setup proof or explicit API-not-supported note in implementation proof | integration/browser | if the installed Vitest Browser Mode provider exposes a page-error hook, setup must fail on page errors; if not, proof must cite the inspected provider/API and keep console/window/rejection guards green | green required |
| Mocked backend request accounting is complete | 0.5, 8 | executor | browser integration tests over request ledgers | integration/browser | each scenario asserts package/delta push, projection RPC, content URL, and expected command capture where applicable | red/green required |
| Mocked backend contract is unit-proven | 0.5 | executor | mocked-backend contract unit tests | unit/test-support | handshake, package vs delta ledgers, content/projection deferred queues, projection abort ledgers, failure profiles, and fixture metadata invariants are proven outside Browser Mode consumers | red/green required |
| Projection coordinator seam is unit-proven | 0.5, 7 | executor | projection coordinator unit tests | unit/runtime | sync fallback, worker lane, cleanup abort/cancel, stale completion, failed completion, telemetry recording, and flush behavior are tested directly | red/green required |
| Content loader negative paths are unit-proven | 0.5, 7 | executor | content-loader unit tests | unit/runtime | aborted fetch, non-OK response, missing handles, selected-handle item/role/generation mismatch, stale selected-content identity, and edge content-resource shapes are covered | red/green required |
| Browser performance uses mocked Bridge boundary | 0.5, 8, 9 | executor | `pnpm --dir BridgeWeb run test:benchmark:browser` structured output plus implementation proof rows | performance/browser | every timed scenario asserts visible UI behavior and matching mocked-backend ledger entries before sampling; jsdom, node-only benchmarks, static fixture pages, and native screenshots are not accepted substitutes | red/green required |
| Mocked backend has medium and large fixture classes | 0.5, 8 | executor | Browser Mode integration + performance rows for `medium-agentstudio` and `large-diffshub` | integration/browser + performance/browser | fixture metadata records fixture id/class, delivery mode, item/path/diff-line/package-byte counts, and avoids added-only placeholder dominance | red/green required |
| Streaming append/delta path is proven | 0.5, 4, 8 | executor | Browser Mode integration test with mocked `streaming-append` delivery | integration/browser | later package/delta updates tree/status without full reset, selected item remains valid, and request ledgers show Bridge push path | red/green required |
| Tree click changes selected file | 0.5, 4 | executor | browser integration test with mocked package/content backend | integration/browser | assert selected CodeView content changes and does not snap back | red/green required |
| Added files expand/render full content | 0.5, 5, 8 | executor | browser integration test plus materialization unit test | unit + integration/browser | fixture uses multi-line added source file, not a one-line placeholder | red/green required |
| Unchanged hunk expansion works | 0.5, 5 | executor | browser integration test clicking Pierre line-info separator | integration/browser | assert new unchanged lines appear after click | red/green required |
| Mocked backend negative paths work | 0.5, 8 | executor | browser integration tests for fetch failure, projection error, and latency | integration/browser | typed unavailable/error state appears, ledgers record the failed request, and no stale loading UI remains | red/green required |
| Stale package/delta/projection drops are proven | 0.5, 6, 8 | executor | Browser Mode integration tests with explicit hold/release controls | integration/browser | stale markdown-only proof is insufficient; package/delta, projection, content, and markdown delayed responses must be ignored when a newer generation, revision, selected-content identity, or projection request wins unless implementation evidence proves a lane cannot be delayed in the current code path | red/green required |
| Worker-backed CodeView Browser Mode proof exists | 0.5, 5, 8, 9 | executor | worker-backed browser integration test and `test:benchmark:browser` metric row | integration/browser + performance/browser | `codeViewWorkerPoolEnabled: true` recorded; visible CodeView content and scroll ownership asserted; worker-disabled baseline is not counted | red/green required |
| Browser performance budgets cover interaction | 0.5, 8, 9 | executor | `pnpm --dir BridgeWeb run test:benchmark:browser` | performance/browser | sequential Chromium performance test records structured JSON, p50/p95, budgets, fixture metadata, correctness assertions, and worker usage | green required |
| Browser performance covers cold and warm paths | 8, 9 | executor | `pnpm --dir BridgeWeb run test:benchmark:browser` output review | performance/browser | named `bridge.viewer.browser.*` scenarios include cold push plus warm selection, added-file, hunk, search, filter, markdown, failure, stale, and scroll paths | green required |
| Browser performance artifact is durable | 8, 9 | executor | implementation proof update after `test:benchmark:browser` | proof artifact + performance/browser | exact per-scenario metric rows from structured stdout are pasted or summarized with scenario id, metric id, fixture id/class, delivery mode, latency profile, worker modes, correctness assertion, p50, p95, budget, and sample count | green required |
| Browser performance artifact is verified | 8, 9 | executor | browser-performance artifact verifier | performance/browser + proof artifact | verifier fails on missing scenario ids, scenario-contract drift, missing fixture metadata, missing worker-mode flags, missing correctness assertion names, missing samples, NaN timings, underreported p50/p95, p95 above budget, unscoped content URLs, or missing push/projection/content/command ledgers | red/green required |
| Node and browser benchmark ownership stays separate | 8, 9 | executor | `mise run bridge-viewer-benchmark` plus `pnpm --dir BridgeWeb run test:benchmark:browser` | benchmark + performance/browser | node deterministic workload metrics are not used as browser interaction proof unless Browser Mode mounted the same scenario | green required |

## Validation Detail

BridgeWeb local gate:

- `pnpm --dir BridgeWeb run check`
- `pnpm --dir BridgeWeb run fmt:check`
- `pnpm --dir BridgeWeb run lint:types`
- `pnpm --dir BridgeWeb run typecheck`
- `pnpm --dir BridgeWeb run test`
- `pnpm --dir BridgeWeb run test:browser`
- `pnpm --dir BridgeWeb run test:benchmark:browser`
- `mise run bridge-viewer-benchmark`
- `pnpm --dir BridgeWeb run build`

Swift/app gate:

- `mise run lint`
- `mise run test -- --filter Bridge`
- `mise run verify-bridge-observability` only after the required observability smoke launch when telemetry/debug proof is in scope

Visual gate:

- Peekaboo captures in `tmp/bridge-viewer-visual-proof/<timestamp>/`.
- Proof notes include app name, PID, window id, fixture name, and screenshots.
- Window-targeted capture must be tried first with app/window id. If it fails with ScreenCaptureKit `SCStreamErrorDomain Code=-3811`, retry documented fallback engines and screen-level capture.
- A black or blank screenshot is a failed visual proof, not a pass. Treat persistent window capture failure or black screen capture as a visual-proof infrastructure blocker and report it separately from BridgeWeb implementation status.

Optional broad health gate:

- `mise run test`
- `mise run test-fast`

Only require broad health if implementation touches Swift runtime, IPC, launch/debug infrastructure, or shared test harnesses.

## Rollback And Recovery

- Keep Bridge contracts unchanged, so rollback should be limited to BridgeWeb shell/rendering files and generated BridgeWeb resources.
- If markdown worker packaging creates asset issues, revert markdown preview task independently while preserving shell polish.
- If visual proof fails due to native debug launch infrastructure, stop and report that blocker rather than editing launch infrastructure.
- If Pierre beta APIs break during implementation, re-check local Pierre sources and docs before patching around it.

## Risks

- Pierre CodeView/FileTree APIs are beta/experimental and may change.
- Markdown rendering introduces an HTML trust boundary.
- A dedicated markdown worker adds packaging and asset-audit complexity.
- CSS can accidentally fight Pierre internals if the shell reaches too deeply.
- Right-side rail differs from DiffsHub's left rail, so visual proof should compare style grammar, not exact layout.
- Current CI `test-fast` timeout may remain unrelated to this slice.

## Resolved Decisions And Deferrals

1. Added/deleted one-sided markdown files render as markdown preview in v1.
2. Modified/two-sided markdown files stay in CodeView; prose markdown diff is deferred.
3. No visible worker/system monitor is added in product UI; use metrics and proof artifacts only.
4. The right rail includes file/search/filter/stats only; comments and annotation tabs stay out of scope unless the user expands scope.

## Next Workflow

Run `shravan-dev-workflow:implementation-execute-plan` against this reviewed plan.

Expected execution focus:

- Execute the tasks in order.
- Keep Bridge contracts read-only and unchanged.
- Preserve right-rail layout and exact black canvas.
- Prove scroll ownership programmatically and visually.
- Prove markdown security before DOM insertion.
- Stop and replan if the markdown worker cannot satisfy packaging/audit constraints.
