# BridgeWeb Large-Diff Fast Loop And UX Proof Spec

Date: 2026-06-18

Status: implementation-ready spec amendment

Related:

- `docs/superpowers/specs/2026-06-18-bridgeweb-dev-visual-proof-harness.md`
- `docs/plans/2026-06-16-bridge-viewer-diffshub-polish.md`

## Purpose

BridgeWeb must be debugged first in a fast browser loop, then proven in the
real AgentStudio Bridge pane. The current native-only loop is too slow and too
opaque for large-diff UX bugs: scrolling barely working, slow file selection,
blank pages on large packages, mismatched headers, and fixture artifacts can all
look like unrelated native issues when the frontend cannot be inspected in a
normal browser.

This spec makes the Vite dev harness and Vitest Browser Mode + Playwright proof
the front door for UX work. Native AgentStudio proof remains required, but it is
not where we discover ordinary frontend layout, virtualization, click, and
worker bugs.

2026-06-19 ordering amendment: implementation proceeds as merge-current-main,
then dev-server DiffsHub-class UX, then semantic IPC control, then native
large-diff/Victoria performance proof. IPC is not late polish: without named
commands to select files, reveal tree paths, drive filters, fetch content, and
collect telemetry snapshots, the real large-worktree proof depends on manual
clicks and cannot be repeated by agents or CI-like harnesses.

## Requirements

1. BridgeWeb has a loopback-only Vite dev server script that opens a useful
   viewer by default.
2. The dev server defaults to a realistic large review fixture, not an empty
   waiting shell.
3. The dev server supports query-selected fixtures and scenarios:
   `small-mixed`, `medium-agentstudio`, and `large-diffshub`.
   This spec supersedes the older dev-harness default: the accepted default is
   `large-diffshub` after the fixture meets this spec's minimum usefulness
   gate. The older `delivery=full-load|streaming-append` selector remains part
   of the dev harness.
4. Fixtures must exercise real BridgeWeb boundaries: package push, projection
   worker request, content-handle fetch, command/RPC capture, and optional
   latency/failure.
5. Large fixtures must not be dominated by added-only placeholder rows. They
   need modified diffs, added files with full fetched content, deleted files,
   renamed files, docs/plans markdown, tests, source, and nested paths.
6. Added files must show full fetched content after selection. Placeholder rows
   may exist only while content is pending.
7. CodeView and the right file rail must scroll independently. The body,
   document, and shell root must not become review-content scroll owners.
8. Clicking file rows must be responsive and deterministic: visible selected
   content changes, `review.markFileViewed` is captured, and selection does not
   snap back.
9. Header/chrome must follow the DiffsHub/Pierre review grammar while fitting
   AgentStudio dark styling: compact, icon-first controls, black canvas,
   custom menus, no native selects, and right-side file rail.
   The foundation is a shadcn/Base UI component layer, not one-off local rail
   widgets. BridgeWeb must initialize/adopt shadcn via the CLI for this package,
   generate the primitive components it needs, and then tune compact variants
   through the generated component source and shared tokens.
   Required primitives for this slice are at least Button, Tooltip, Popover or
   Dropdown/Menu, and Input/Search. If the shadcn CLI offers Base UI versions
   for a primitive, use the Base UI version. If a required primitive is not
   available in Base UI through the CLI, document the fallback and keep the
   wrapper API compatible with the generated shadcn style.
   The theme foundation is Catppuccin Mocha adapted to AgentStudio's dark app
   chrome and Pierre's dark review grammar. Use Pierre's DiffsHub/Trees/Diffs
   references as layout and interaction inputs, then expose BridgeWeb tokens
   through Tailwind v4 CSS variables. Do not add an unaudited remote/runtime
   theme dependency for this slice. If Pierre or Shiki would pull a broad
   bundled theme registry into the app, BridgeWeb must route that path through a
   Bridge-owned facade or custom registration path and prove the packaged app
   assets remain self-contained. The review canvas stays black where the product
   needs it, but sidebar, popover, input, ring, border, status colors, and
   CodeView token defaults should intentionally align with Catppuccin Mocha.
10. The rail filter/search controls must feel like a designed DiffsHub-class
    inspector, not generic web form controls. The open filter popover must use a
    dark raised surface, clear separators, 24-32px menu rows, colored status
    badges, trailing selected checkmarks, disabled/clear affordances, and icon
    sizing that matches AgentStudio sidebar controls. Closed controls must be
    icon-first compact buttons, not tiny black native-looking dropdown pills.
    The rail toolbar itself should read like app sidebar chrome: a small
    tree/comments tool group on one side and search/filter icon buttons on the
    other, with no visible form labels, no native select arrows, no wide tab-like
    filter fields, and no text cursor affordances. A tiny active indicator on an
    icon button is acceptable when it follows the surrounding AgentStudio sidebar
    language; decorative status dots or large badge pills that compete with the
    file rows are not.
    The reference sidebar grammar uses quiet outline icons for tree/comments,
    search, and filter controls; the active filter can use a tiny blue indicator
    attached to the icon button. BridgeWeb should match that scale and icon
    family instead of mixing oversized glyphs, text labels, pill tabs, or form
    controls into the rail header. The icon group must feel native to the
    existing AgentStudio sidebar, with the DiffsHub crop used as the external
    prior-art reference.
    The reference DiffsHub status menu uses checkbox-style item semantics, an
    explicit `Clear filter` action, about 32px rows, and a larger raised popover
    than the old local 176px-wide menu; BridgeWeb must either match those
    semantics or document a product-specific divergence. The proof must compare
    the actual rendered geometry against the DiffsHub reference: menu width,
    row height, badge box, icon/button box, selected checkmark placement,
    separator spacing, and popover offset from the filter button. Current
    DiffsHub reference measurements to target are roughly 16px icon/filter
    glyphs inside compact app-sidebar buttons, 32px top-right header buttons,
    32px popover menu rows, 8px popover internal padding, about 10px popover
    radius, compact status-token boxes, and a trailing check affordance at the
    far right. A screenshot alone is not enough if these measured affordances
    are missing.
    Browser reference capture on the Node PR measured checkbox menu items at
    about 32px high with 6px/8px row padding, 14px menu text, 16px selected
    checkmarks near the right edge, and a raised popover around 216-256px wide
    depending on viewport/crop. A later 1600px-wide DiffsHub probe measured the
    Git-status popover at about `235px x 247px`, positioned near `x=72, y=83`
    after opening from the rail toolbar. BridgeWeb proof must record these
    values for its own rendered menu and explain any intentional divergence.
    Filter-menu proof must include both semantic assertions and visual geometry:
    the trigger is a button with `aria-label`, `aria-haspopup="menu"`, and
    toggled `aria-expanded`; status rows use `role="menuitemcheckbox"` or an
    equivalent checkbox state with `aria-checked`; rows are keyboard-reachable;
    `Clear filter` exposes the correct disabled state; and a crop with the menu
    open beside the rail makes icon scale, menu offset, and row grid
    inspectable.
    The visual target is closer to a compact AgentStudio/DiffsHub sidebar menu
    than to a web dropdown: toolbar buttons stay glyph-first, the selected
    filter state is communicated by a small badge or indicator, menu rows align
    icon/status text/checkmark on a stable grid, and hover/selected states use
    the same dark raised-menu language as the app chrome. Decorative dots,
    wide text fields, oversized tab-like buttons, or controls that look unlike
    the surrounding AgentStudio sidebar are not acceptable even if they pass
    semantic role checks.
    Source-boundary note: Pierre exposes Git status rendering through FileTree
    data and public styling/state options, but the current source/reference pass
    did not identify a public DiffsHub Git-status filter-popover API. BridgeWeb
    may therefore own the status-filter popover as local chrome, but it must
    remain a semantic menu with keyboard/focus behavior and must feed Pierre
    FileTree data/model state rather than painting a separate fake filtered tree.
    BridgeWeb-owned chrome still uses generated shadcn/Base UI primitives. The
    implementation may add product wrappers such as `BridgeReviewToolbarButton`
    or `BridgeReviewFilterMenu`, but those wrappers compose the generated
    Button/Popover/Menu/Input primitives and compact variants; they do not
    reimplement focus, overlay, disabled, or menu semantics from scratch.
11. The rail header affordances should stay icon-scale. Search/filter buttons
    should measure like compact 16px-icon controls inside small button hit
    targets; they must not stretch into wide select-like fields merely because
    the rail has available width.
12. File-tree rows must keep DiffsHub-class density and alignment: compact
    disclosure affordances, consistent file/status icons, right-aligned status
    letters, selected-row contrast, and stable row height while scrolling,
    filtering, or expanding. Folder chevrons must not be oversized relative to
    file rows. The tree must preserve the DiffsHub interaction model: folder
    disclosure, search result reveal, selected row focus, and file row click
    must all use Pierre tree state instead of a separate local CSS-only state.
    Current DiffsHub reference measurements to target are about 24px tree rows,
    a narrow right status column around 12px, compact file/folder glyphs, and
    tiny folder change markers rather than large status pills.
    Browser reference capture on the Node PR measured tree rows at about 24px
    tall with 13px text, 24px line-height, roughly 6px horizontal row padding,
    pointer cursor, and `user-select: none`; selected rows use a distinct
    selected background and `aria-selected="true"`. File rows are exposed as
    `button[role="treeitem"][data-item-path]` with path-bearing `aria-label`
    values. BridgeWeb row proof must assert pointer/no-text-selection behavior,
    real treeitem roles, selected state, and visible selected paint, not only
    path text.
    Use Pierre's density/item-height and CSS-variable theming controls to reach
    this density. `density: 'compact'` is the default target; if measured rows
    are not DiffsHub-class in the actual browser/WebKit surface, set the public
    `itemHeight`/style variables needed to produce roughly 24px rows and record
    that measurement in the proof. Tree search must use `expand-matches`, so a
    successful search visibly opens ancestor folders instead of requiring a
    second manual disclosure step.
    File search and Git-status filtering must keep the same tree interaction
    model: searches reduce or reveal the visible row set, matching ancestors
    expand, and folder rows with children expose and toggle `aria-expanded`.
    A file row click must update selection and scroll CodeView to the matching
    item; it must not merely highlight a row in the rail.
    The file rail must preserve app-sidebar pointer behavior: rows, disclosure
    affordances, and file headers are controls, not selectable text. Browser and
    native proof must reject `cursor: text`, unexpected text selection, hidden
    selected rows, or folder rows whose visual disclosure state is out of sync
    with `aria-expanded`.
13. Pierre APIs must be used through public exports and explicit options:
    compact tree density, `fileTreeSearchMode: 'expand-matches'`, prepared or
    presorted tree input, CodeView layout options, custom header hooks, and
    worker-backed highlighting.
    The implementation must prefer the same SDK-level mechanisms DiffsHub uses
    over CSS-only approximations: FileTree prepared input plus stable ordering,
    compact density/item metrics, FileTree reveal/focus/scroll APIs for
    selection, CodeView item `collapsed` state with version increments,
    CodeView custom header hooks, CodeView layout props for internal
    padding/gaps, and the React worker-pool provider for Shiki highlighting.
    If BridgeWeb diverges from a Pierre/DiffsHub mechanism, the spec proof must
    name the reason and the replacement contract.
    DeepWiki/source-reference baseline for this slice: DiffsHub maps tree
    selection to CodeView `scrollTo`, configures compact FileTree row sizing,
    passes Git status through FileTree data, uses FileTree search/model methods,
    and uses CodeView item `collapsed` plus `version` increments for header
    toggles. Local Pierre source also shows DiffsHub using a 24px file-tree item
    height and layout-only density/style overrides around FileTree. BridgeWeb
    should match those public API shapes before reaching for app-local styling
    overrides.
14. All heavy rendering or rendering-adjacent work must stay off the main
    thread when possible. Projection, markdown rendering, and CodeView
    highlighting use typed workers or Pierre worker lanes.
    Plain Vite dev cannot rely on packaged-only `agentstudio://app/...` worker
    URLs. `workers=on` must provide dev-safe CodeView and markdown worker
    wiring or be split before implementation claims worker-backed dev proof.
15. Vitest Browser Mode with Playwright is the first executable proof for
    browser behavior. It must cover real DOM, CSS, click, scroll, workers,
    virtualization, and mocked Bridge ledgers.
16. Browser performance tests are proof gates, not advisory benchmarks. A blank
    viewer, missing content, missing ledger entry, inert hunk expansion, or
    body-scroll drift is a failed performance scenario even if it is fast.
17. Browser performance output must be durable and verified. It must include
    scenario id, metric id, fixture id/class, delivery mode, latency, worker
    modes, correctness assertion, p50, p95, budget, sample count, and raw
    samples.
18. The dev server must be inspectable by an agent or human with screenshots.
    Required visual states are default large fixture, scrolled CodeView,
    scrolled right rail, filter/search open, added-file content, markdown
    preview, and failure/unavailable UI. Filter/search-open screenshots must
    include the full popover, selected state, status badges, and rail context.
    The visual proof packet must include DiffsHub reference crops or fresh
    browser captures for the Node PR sidebar/filter target alongside BridgeWeb
    crops of the same states. It must call out concrete mismatches, not just
    attach images: control size, row density, status badge/checkmark alignment,
    tree disclosure affordance, file-click scroll result, and header cursor /
    collapse behavior.
19. Native AgentStudio debug proof still gates PR readiness. It must prove the
    same repaired behavior in the WKWebView Bridge pane after browser proof is
    green.
20. Markdown preview remains a security-sensitive rendering path. It must keep
    sanitized DOM insertion, inert links/media, unsafe scheme stripping, and
    Bridge content-resource URL validation.
    Markdown is also an active native-path blocker until a real AgentStudio
    debug Bridge pane proves sanitized markdown rendering in the manual/WKWebView
    path. Browser, mock, or small-smoke proof can validate lower layers, but it
    cannot close the native markdown acceptance gate.
21. The current branch/worktree is a required performance fixture:
    `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
    on branch `luna-338-pierreshikitrees-review-viewer`. It is not optional
    synthetic context because manual use on this branch observed slow
    selection, scroll, and render behavior. Mocked Node-PR-class fixtures remain
    necessary, but they are not sufficient for PR readiness.
22. Native performance proof must include the real Bridge package/worktree path
    for the current branch and record stage timings for package push, tree
    render/search/reveal, file select, CodeView hydration/render, markdown
    render, and scroll responsiveness. A fast mocked fixture does not prove the
    slow real-worktree path.
23. Before native large-performance proof, Bridge must expose a semantic IPC
    control surface for the diff/file review capability. IPC drives product
    actions, not WebKit internals: it targets a Bridge pane/capability,
    validates permissions, and calls Bridge-owned ports. Required command groups
    for this slice are:
    - `bridge.diff.load`
    - `bridge.diff.refresh`
    - `bridge.diff.getPackage`
    - `bridge.diff.selectFile`
    - `bridge.diff.scrollToFile`
    - `bridge.diff.expandFile`
    - `bridge.diff.collapseFile`
    - `bridge.fileTree.search`
    - `bridge.fileTree.setFilter`
    - `bridge.fileTree.revealPath`
    - `bridge.fileView.getContent`
    - `bridge.fileView.showMarkdownPreview`
    - `bridge.telemetry.snapshot`
    - `bridge.telemetry.flush`
    Exact names may be refined during implementation, but the namespace must
    stay Bridge-scoped and semantic. Avoid generic `webview.evaluateJavaScript`,
    raw event-bus command routing, or unscoped `diff.*` globals that could
    collide with future non-Bridge surfaces.
24. Observability is a product proof gate. Browser and native large-diff proof
    must emit or query Victoria-backed telemetry for package push, tree
    projection/render/search/reveal, file selection, CodeView hydration/render,
    markdown render, content fetch, worker readiness, and scroll/interaction
    responsiveness. Metrics/traces/logs must be debug-only, low-cardinality, and
    scoped so they can be enabled for Bridge/Pierre without stealing resources
    from the review path.

## Non-Goals

- No backend Git comparison redesign.
- No patch apply, approve/reject, annotation authoring, source mutation, or
  Monaco/editor work.
- No replacement of native proof with dev-server screenshots.
- No raw local filesystem import into the dev harness in this slice.
- No arbitrary remote URL, `file:`, `data:`, or custom-scheme loading from
  fixture query parameters.

## Design System Foundation

BridgeWeb chrome work starts with a generated shadcn/Base UI foundation.
The UI must not be designed from scratch with ad hoc Tailwind-only controls.
Tailwind v4 is the styling transport for the generated shadcn/Base UI
components, compact variants, Catppuccin Mocha tokens, and AgentStudio/Pierre
aliases. Product components compose those primitives and use `cn` for class
merging; they do not reinvent buttons, popovers, menus, search inputs, focus
management, or disabled/checked states in feature-local code.

Required setup:

- Add a `BridgeWeb/components.json` owned by the BridgeWeb package, not the
  repo root.
- Use the shadcn CLI from the BridgeWeb package root. The CLI must generate
  source into BridgeWeb-owned paths such as `BridgeWeb/src/components/ui/*`.
- Configure for React/Vite, TypeScript, Tailwind v4 CSS variables, and Base UI
  primitives where the current CLI supports them.
- Keep the existing `cn` utility or have the generated utility delegate to it;
  do not create competing class-name helpers.
- Use the generated primitives as the base for review chrome wrappers:
  buttons, icon buttons, popovers/dropdowns, menu rows, tooltips, and search
  input/overlay.
- Do not hand-roll overlay focus/escape/blur/menu semantics in feature code
  when a generated shadcn/Base UI primitive owns that behavior.
- Keep feature-local Tailwind classes shallow and product-specific: layout,
  compact sizing, and token selection are acceptable; bespoke component
  semantics or isolated visual systems are not.

Theme setup:

- Start from Catppuccin Mocha for AgentStudio BridgeWeb chrome, adapted to
  Pierre's dark review grammar and the required black review canvas. Pierre
  informs layout and component behavior; shadcn/Base UI owns control
  primitives; BridgeWeb owns the final token mapping.
- Palette and asset boundary: use shadcn/Base UI semantic chrome tokens plus
  Bridge-owned aliases for product UI. Catppuccin Mocha is the intended color
  source for this slice. The build guard should reject external runtime imports,
  remote URLs, unbounded dependency registries, and unsafe worker/resource
  loading. It must not reject assets merely because an intentional theme name,
  token, or chunk contains `catppuccin` or `mocha`.
- Cross-check the Pierre checkout before implementation:
  - `apps/diffshub/components.json`
  - `apps/diffshub/app/globals.css`
  - `packages/theming/src/collections/pierre.ts`
  - `packages/theming/src/collections/shiki.ts`
  - `packages/theming/test/color.test.ts`
- Cross-check shadcn against `shadcn-ui/ui` with DeepWiki/source references:
  generated components should read semantic Tailwind v4 CSS variables from
  `components.json`/global CSS, and BridgeWeb should tune generated component
  source rather than inventing bespoke overlay/button semantics.
- Required theme outputs are Tailwind v4 CSS variables for shadcn tokens
  (`--background`, `--foreground`, `--popover`, `--accent`, `--border`,
  `--input`, `--ring`, sidebar tokens) plus Bridge/Pierre aliases
  (`--bridge-app-bg`, `--bridge-canvas-bg`, `--bridge-surface-bg`,
  `--bridge-accent`, status colors).
- Pierre CodeView highlighting should continue to use Pierre/Shiki APIs. In
  packaged WKWebView, Bridge registers the local `catppuccin-mocha`
  CSS-variable theme with Pierre before CodeView renders so CodeView and the
  worker pool do not depend on a cold dynamic theme import. The shadcn UI theme
  and CodeView syntax theme must be visually compatible, but they are not the
  same mechanism.

Proof:

- Commit or record the exact shadcn CLI commands used. For the installed shadcn
  CLI, the Base UI selection is represented by `style: "base-nova"` in
  `components.json`; do not add unsupported schema fields just to make the base
  explicit.
- Build/typecheck must prove generated imports resolve without Next-style
  aliases unless those aliases are intentionally added.
- Component tests must assert review chrome uses generated primitives or
  Bridge wrappers over generated primitives, not standalone bespoke buttons and
  popovers.
- Visual proof must show the AgentStudio-owned dark tokens applied to the
  rail toolbar, filter popover, search control, FileTree, and CodeView canvas.

## Fast Loop Architecture

```text
pnpm --dir BridgeWeb run dev
        |
        v
Vite loopback server
        |
        v
dev bootstrap
  parses fixture/scenario params
  installs BridgeViewerMockedBackend
  injects fetch/projection/markdown/worker deps
        |
        v
BridgeApp
  same React/Zustand/runtime/coordinator path as packaged app
        |
        +----------------------+----------------------+
        |                      |                      |
        v                      v                      v
mocked Bridge lanes       Pierre FileTree        Pierre CodeView
push/RPC/content          compact rail           worker highlighted
projection ledger         expand-matches         full added files
```

The dev harness may add a dev-only bootstrap and scenario resolver. It must not
fork the viewer or add test-scenario branches inside product components.
The dev-only mocked backend, scenario resolver, and dev bootstrap must not be
bundled into packaged native BridgeWeb assets.

After browser UX proof is good, the native loop is driven through Bridge
semantic IPC instead of manual clicking:

```text
IPC client / test harness
        |
        v
AgentStudio IPC router
        |
        v
Bridge capability target
        |
        +--> bridge.diff.*       load/select/scroll/collapse package items
        +--> bridge.fileTree.*   search/filter/reveal tree rows
        +--> bridge.fileView.*   fetch content / show markdown preview
        +--> bridge.telemetry.*  snapshot / flush debug metrics
        |
        v
Bridge runtime + packaged BridgeWeb WKWebView
        |
        v
Victoria-backed proof + screenshots + stage timings
```

## Proof Pyramid

```text
Unit
  scenario resolver, zod models, materialization, store actions, workers
        |
        v
Node integration
  mocked backend contract, content loader, projection coordinator
        |
        v
Vitest Browser Mode / Playwright
  real DOM, CSS, click, scroll, workers, CodeView/FileTree behavior
        |
        v
Vite dev visual harness
  fast screenshot/manual/agent loop for large fixtures
        |
        v
Packaged BridgeWeb build
  generated app assets, worker assets, dependency audit,
  self-contained runtime import and worker asset audit
        |
        v
Semantic IPC control
  Bridge-scoped diff/fileTree/fileView/telemetry commands
        |
        v
AgentStudio debug app
  WKWebView pane, real Bridge package/worktree path,
  custom scheme content fetch, native shell proof
        |
        v
PR readiness
  review findings addressed, checks green or scoped blockers documented
```

## Acceptance Gates

- `pnpm --dir BridgeWeb run dev` serves a nonblank large fixture on loopback.
- `pnpm --dir BridgeWeb run test:browser` proves click, scroll, search,
  filters, added-file content, hunk expansion, failure UI, and worker-backed
  CodeView behavior in Chromium.
- `pnpm --dir BridgeWeb run test:benchmark:browser` emits verified structured
  scenario rows and fails on correctness or p95 budget regressions.
- Browser screenshots show the repaired visual states.
- `pnpm --dir BridgeWeb run build` proves packaged workers/assets still pass
  audit.
- Semantic Bridge IPC commands can load/refresh a package, select/reveal a
  file, drive tree search/filter, fetch content, request markdown preview, and
  capture telemetry state without opening command palette UI or exposing raw
  WebKit evaluation.
- The AgentStudio debug Bridge pane proves the same large-worktree behavior
  without blank page, scroll lock, selection stalls, or markdown render gaps.
- Native proof includes the current `agent-studio.bridge-start` worktree on
  branch `luna-338-pierreshikitrees-review-viewer` with stage timings for
  package push, tree render/search/reveal, file select, CodeView
  hydration/render, markdown render, and scroll responsiveness.
- Victoria proof includes debug-scoped Bridge/Pierre metrics or traces for the
  stages above, correlated to the IPC actions and screenshot/proof artifacts.
