# BridgeWeb Large-Diff Fast Loop And UX Proof Spec

Date: 2026-06-18

Status: implementation-ready spec amendment

Related:

- `docs/superpowers/specs/2026-06-18-bridgeweb-dev-visual-proof-harness.md`
- `docs/plans/2026-06-18-bridgeweb-large-diff-fast-loop-remediation.md`
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
then dev-server DiffsHub-class UX/performance proof, then semantic IPC control,
then native large-diff/Victoria performance proof. IPC is a follow-on lane that
may be delegated after the browser loop stabilizes. It is still required before
repeatable native large-worktree proof: without named commands to select files,
reveal tree paths, drive filters, fetch content, and collect telemetry snapshots,
the real large-worktree proof depends on manual clicks and cannot be repeated by
agents or CI-like harnesses.

2026-06-19 reset amendment: the local Pierre/DiffsHub code is the reference for
CodeView/FileTree/theming patterns, BridgeWeb's generated shadcn/Base UI
components are the reference for controls, and Catppuccin Mocha is the accepted
visual target. Any in-progress BridgeWeb edits on this branch must be validated
or reshaped against this contract before they count as proof. The reset ledger is
`tmp/research-workflows/2026-06-19-bridgeweb-diffshub-shadcn-reset/research-ledger.md`.

2026-06-19 source-truth amendment: DiffsHub parity means copying the local
source behavior contract, not approximating screenshots with bespoke CSS.
BridgeWeb must mirror DiffsHub's use of uncontrolled Pierre CodeView plus
imperative item updates, `renderHeaderPrefix` for collapse only,
CodeView-backed file scrolling, preserved-input-order FileTree updates,
`themeToTreeStyles(...)` for the tree, and a chrome-token mapping layer for
shadcn/Tailwind controls. DiffsHub's Radix shadcn wrappers are prior art;
BridgeWeb's component implementation remains shadcn/Base UI.

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
   The current visual gate is explicit: compare against
   `https://diffshub.com/ShravanSunder/agentstudio/pull/180` in dark mode with
   DiffsHub/Pierre's `catppuccin-mocha` theme selected. Local DiffsHub source
   shows the dark-theme persistence key is `diffshub-dark-theme`, and Pierre's
   Shiki theme collection exposes `catppuccin-mocha`; headless proof must set
   or select that theme before navigation or record why storage seeding was not
   available.
   The foundation is a shadcn/Base UI component layer, not one-off local rail
   widgets. BridgeWeb must initialize/adopt shadcn via the CLI for this package,
   generate the primitive components it needs, and then tune compact variants
   through the generated component source and shared tokens. Local DiffsHub uses
   shadcn-style Radix wrappers; BridgeWeb intentionally uses shadcn/Base UI. Copy
   DiffsHub's review grammar, measurements, Pierre API usage, and Catppuccin
   target, not its Radix dependency choice.
   The canonical shadcn basis is Mira on Base UI with small radius. The local
   preset code is `b1D0dxoG`, which decodes to `style = mira`,
   `baseColor = neutral`, `theme = neutral`, `iconLibrary = lucide`,
   `radius = small`, `menuAccent = subtle`, `menuColor = default`,
   `font = geist`, and `fontHeading = inherit`.
   Required primitives for this slice are at least Button, Tooltip, Popover or
   Dropdown/Menu, and Input/Search. If the shadcn CLI offers Base UI versions
   for a primitive, use the Base UI version. If a required primitive is not
   available in Base UI through the CLI, document the fallback and keep the
   wrapper API compatible with the generated shadcn style.
   Shadcn theming is the first layer. Generated primitives and their semantic
   tokens own button/menu/input/popover/focus/radius behavior. Catppuccin Mocha
   is then mapped onto those semantic tokens for AgentStudio's dark app chrome
   and Pierre's dark review grammar. Use Pierre's DiffsHub/Trees/Diffs
   references as layout and interaction inputs, then expose BridgeWeb tokens
   through Tailwind v4 CSS variables. Do not add an unaudited remote/runtime
   theme dependency for this slice. If Pierre or Shiki would pull a broad
   bundled theme registry into the app, BridgeWeb must route that path through a
   Bridge-owned facade or custom registration path and prove the packaged app
   assets remain self-contained. The review canvas stays black where the product
   needs it, but sidebar, popover, input, ring, border, status colors, and
   CodeView token defaults should intentionally align with Catppuccin Mocha.
   Component-level overrides happen downstream of this theme layer and only for
   Bridge density/layout/domain states. They must not introduce a parallel
   one-off color, radius, typography, or focus system.
   The top review summary and projection-mode strip is part of this chrome
   contract. It must not render as a high-contrast black island pasted over the
   Mocha surface. The stats, endpoint label, generation/grouping text, and
   `All / Changed / Guided / Change set / Docs/plans / Tests / Source` controls
   must sit on the same compact AgentStudio/Pierre header plane, using Mocha
   surface, border, hover, pressed, and muted-text tokens. The active scope
   affordance should be quiet and segmented, not a detached pure-black pill row.
   Each projection button must have a stable semantic test id, compact 11px
   typography, exactly one active pressed state, and no wrapper background that
   reads as a separate black strip. Browser proof must measure the rendered
   header state because screenshots have caught regressions that prop-level
   tests missed.
   Browser and native visual proof must include a top-header crop and reject
   controls whose background, height, radius, typography, or spacing visibly
   diverge from the surrounding AgentStudio dark chrome.
   Browser proof must be fixture-aware: the visual proof runner resolves a
   selectable file from the active `file-tree-container` rather than relying on
   a stale hardcoded path. The proof JSON records selected path, target path,
   dark-mode background color, worker state, and screenshot artifact paths.
   Shadcn/Base UI adoption is measured at the rendered Bridge controls, not by
   the mere presence of generated files. The generated primitives must own
   control semantics for buttons, menus, popovers, inputs, disabled states,
   focus rings, and pressed/open states. Bridge-specific wrappers may tune
   density and tokens, but the shell must not build a parallel control language
   with bespoke inline SVG buttons, native-looking selects, or detached bars.
   The top projection mode control must be a compact shadcn-style
   toggle/segmented control that belongs to the header plane, not a floating
   black strip. An unexplained hamburger/list icon in the review header is not
   acceptable unless it maps to an intentional app action and matches the same
   compact icon-button component. CodeView file headers must also stay visually
   sparse: Bridge may add the collapse/expand affordance through Pierre's
   `header-prefix` slot, but it must not add a second Bridge status badge or
   Bridge file-kind icon before Pierre's own file icon/path. Status belongs in
   the file rail/tree and metadata, not as a third leading token in every
   CodeView header.
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
    Test ids must identify the actual interactive control, not both a wrapper
    and a nested button. Hover and focus behavior should be consistent across
    the rail icon controls; unavailable future features may no-op, but should
    not become visually inert because a native disabled state suppresses hover
    affordances in the toolbar.
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
    File headers in CodeView are part of this same interaction contract. They
    must use Lucide or generated-system icons, expose a single stable
    collapse/expand control with synced `aria-expanded`, avoid duplicate path
    text on both left and right sides, preserve a faint but visible boundary
    between files, and keep the active header stable during scroll. A rail file
    click must scroll the matching CodeView header to the top of the viewport;
    collapse and expand must not cause unexpected scroll jumps or desync the
    chevron from the actual collapsed state.
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
18. Boundary data contracts must be Zod-first. Every cross-boundary BridgeWeb
    payload uses a camelCase `xxxSchema` constant as the runtime contract and a
    PascalCase `Xxx` type derived from that schema. This applies to
    Swift-to-BridgeWeb package/delta pushes, BridgeWeb-to-worker RPC, worker
    responses, dev-server fixture/query config, benchmark artifacts, telemetry
    bootstrap/config, and IPC/debug payloads added by this plan. Use
    discriminated unions for variant payloads. Prefer `z.record(z.string(),
    z.unknown())` only for intentionally opaque extension metadata; otherwise
    model the shape explicitly. Parse once at the ingress/egress boundary, then
    pass inferred typed data through projection, React, and Zustand internals.
    Zustand actions must not accept raw `unknown`, perform heavy parse work,
    call Swift, post worker messages, fetch content, mutate Pierre models, or
    emit telemetry directly. They update pure state/references and enqueue
    typed intents from already-validated inputs.
19. The dev server must be inspectable by an agent or human with screenshots.
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
    The visual packet must explicitly reject the latest manual failure modes:
    buttons with mismatched permanent outlines, detached black scope strips,
    unclear hamburger/list buttons, text-cursor file headers, duplicated file
    paths in headers, selected files that do not align to the top after a rail
    click, collapse/open operations that jump scroll position, added files that
    render as black/empty placeholders instead of full green added content, and
    scrollbars or separators that do not match the dark AgentStudio/DiffsHub
    grammar.
20. Native AgentStudio debug proof still gates PR readiness. It must prove the
    same repaired behavior in the WKWebView Bridge pane after browser proof is
    green.
21. Markdown preview remains a security-sensitive rendering path. It must keep
    sanitized DOM insertion, inert links/media, unsafe scheme stripping, and
    Bridge content-resource URL validation.
    Markdown is also an active native-path blocker until a real AgentStudio
    debug Bridge pane proves sanitized markdown rendering in the manual/WKWebView
    path. Browser, mock, or small-smoke proof can validate lower layers, but it
    cannot close the native markdown acceptance gate.
22. The current branch/worktree is a required performance fixture:
    `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
    on branch `luna-338-pierreshikitrees-review-viewer`. It is not optional
    synthetic context because manual use on this branch observed slow
    selection, scroll, and render behavior. Mocked Node-PR-class fixtures remain
    necessary, but they are not sufficient for PR readiness.
23. Native performance proof must include the real Bridge package/worktree path
    for the current branch and record stage timings for package push, tree
    render/search/reveal, file select, CodeView hydration/render, markdown
    render, and scroll responsiveness. A fast mocked fixture does not prove the
    slow real-worktree path.
    PR 180 is the visual-parity baseline; Node PR 59805 is the
    scale/performance baseline.
24. Before native large-performance proof, Bridge must expose a semantic IPC
    control surface for the diff/file review capability. IPC drives product
    actions, not WebKit internals: it targets a Bridge pane/capability,
    validates permissions, and calls Bridge-owned ports. This IPC work is not a
    prerequisite for the dev-server/DiffsHub UX slice and may run as a separate
    delegated lane after browser click/scroll/filter/content behavior is stable.
    Required command groups before native repeatable proof are:
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
25. Observability is a product proof gate. Browser and native large-diff proof
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
The canonical shadcn preset is Mira on Base UI with small radius. The local
preset code for this contract is `b1D0dxoG`.

Required setup:

- Add a `BridgeWeb/components.json` owned by the BridgeWeb package, not the
  repo root.
- Use the shadcn CLI from the BridgeWeb package root. The CLI must generate
  source into BridgeWeb-owned paths such as `BridgeWeb/src/components/ui/*`.
- Configure for React/Vite, TypeScript, Tailwind v4 CSS variables, and Base UI
  primitives where the current CLI supports them.
- Keep the shadcn alias contract real. If `components.json` declares `@/*`
  aliases, `BridgeWeb/tsconfig.json` and `BridgeWeb/vite.config.ts` must define
  matching resolution so `shadcn apply`, generated imports, typecheck, Vite dev,
  and packaged builds all agree.
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

- Start from the shadcn Mira/Base UI/small-radius preset, then map Catppuccin
  Mocha onto the shadcn semantic variables for AgentStudio BridgeWeb chrome,
  adapted to Pierre's dark review grammar and the required black review canvas.
  Pierre informs layout and component behavior; shadcn/Base UI owns control
  primitives and semantic token names; BridgeWeb owns the final Catppuccin token
  mapping.
- Palette and asset boundary: use shadcn/Base UI semantic chrome tokens plus
  Bridge-owned aliases for product UI. Catppuccin Mocha is the intended color
  source for this slice. The build guard should reject external runtime imports,
  remote URLs, unbounded dependency registries, and unsafe worker/resource
  loading. It must not reject assets merely because an intentional theme name,
  token, or chunk contains `catppuccin` or `mocha`.
- Source-control boundary: generated native app resource bundles, copied
  packaged app assets, and `dist` output are build products. They should be
  reproducible from checked-in BridgeWeb source, generated shadcn component
  source, scripts, fixtures, and lockfiles through `mise`/`pnpm` build tasks, not
  checked in as source.
- Cross-check the Pierre checkout before implementation:
  - `apps/diffshub/components.json`
  - `apps/diffshub/components/ui/button.tsx`
  - `apps/diffshub/components/ui/button-group.tsx`
  - `apps/diffshub/components/ui/dropdown-menu.tsx`
  - `apps/diffshub/app/globals.css`
  - `apps/diffshub/app/_components/CodeViewHeader.tsx`
  - `apps/diffshub/app/_components/CodeViewSidebar.tsx`
  - `apps/diffshub/app/_components/CodeViewFileTree.tsx`
  - `apps/diffshub/app/_components/_theming/react/ThemedCodeView.tsx`
  - `apps/diffshub/app/_components/_theming/react/ThemedFileTree.tsx`
  - `apps/diffshub/app/_components/_theming/js/treeThemeProps.ts`
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
- Pierre CodeView highlighting should continue to use Pierre/Shiki APIs with
  `catppuccin-mocha` as the named dark theme. If packaged WKWebView cannot rely
  on Pierre's normal dynamic theme import path, BridgeWeb may add a packaged
  local adapter, but it must not silently register a different CSS-variable
  theme under `catppuccin-mocha` and call that parity. The adapter must prove
  equivalence or use a Bridge-owned name while still producing Catppuccin Mocha
  visuals. The shadcn UI theme and CodeView syntax theme must be visually
  compatible, but they are not the same mechanism.
- Pierre FileTree styling should come from the same resolved theme through
  `themeToTreeStyles(...)`, with only narrow Bridge-specific overrides layered
  after it. Direct `--trees-*-override` palettes are allowed only when the
  public theme/style surface does not reach a necessary AgentStudio state, and
  the implementation proof must name that gap.

Proof:

- Commit or record the exact shadcn CLI commands used. For the installed shadcn
  CLI, the accepted Base UI/Mira selection is represented by
  `style: "base-mira"` in `components.json`; do not add unsupported schema
  fields just to make the base explicit.
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
Semantic IPC control (follow-on lane)
  Bridge-scoped diff/fileTree/fileView/telemetry commands after browser UX proof
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
- Before native repeatable proof, semantic Bridge IPC commands can load/refresh
  a package, select/reveal a file, drive tree search/filter, fetch content,
  request markdown preview, and capture telemetry state without opening command
  palette UI or exposing raw WebKit evaluation. This gate follows the browser UX
  gate and must not substitute for visual/browser proof.
- The AgentStudio debug Bridge pane proves the same large-worktree behavior
  without blank page, scroll lock, selection stalls, or markdown render gaps.
- Native proof includes the current `agent-studio.bridge-start` worktree on
  branch `luna-338-pierreshikitrees-review-viewer` with stage timings for
  package push, tree render/search/reveal, file select, CodeView
  hydration/render, markdown render, and scroll responsiveness.
- Victoria proof includes debug-scoped Bridge/Pierre metrics or traces for the
  stages above, correlated to the IPC actions and screenshot/proof artifacts.
