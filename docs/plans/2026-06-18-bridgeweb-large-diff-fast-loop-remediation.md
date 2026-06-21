# BridgeWeb Large-Diff Fast Loop Remediation Plan

Date: 2026-06-18

Goal id: `2026-06-18-bridgeweb-diffshub-node-pr-parity`

Status: amended during execution after DiffsHub/Node PR parity research

Current source-of-truth, 2026-06-19:

- This is the active executor-facing plan for the BridgeWeb DiffsHub/Shadcn
  reset. The companion UX/style plan is
  `docs/plans/2026-06-16-bridge-viewer-diffshub-polish.md`; the older
  `docs/plans/2026-06-15-bridge-codeview-trees-shiki-review-viewer.md` is
  historical foundation only and must not be executed directly after this
  reset.
- Local Pierre/DiffsHub source is the primary behavior reference:
  `apps/diffshub/app/_components/CodeViewWrapper.tsx`,
  `CodeViewFileTree.tsx`, `ReviewUI.tsx`,
  `_theming/js/treeThemeProps.ts`, and `_theming/js/diffshubChromeMapping.ts`.
- DiffsHub uses Radix/new-york shadcn wrappers; BridgeWeb does not copy that
  component implementation. BridgeWeb uses package-local shadcn with
  `style = "base-mira"` and Base UI-backed primitives. Borrow DiffsHub's review
  grammar, Pierre API usage, theme flow, density, and behavior tests, not its
  Radix dependency choice.
- The user-visible design target is DiffsHub on Catppuccin Mocha with
  AgentStudio's right-side rail as the intentional product difference. Do not
  approximate that target with hand-authored Tailwind controls, fake theme
  dumps, or broad FileTree shadow-DOM CSS surgery.
- Product-code edits already present on this branch are candidate partial
  fixes. They must be validated or reshaped against this plan before they count
  as accepted implementation proof.
- Current product-code edits classify as follows:
  - keep and finish: selected-content extraction, shell prop plumbing,
    CodeView collapse-anchor intent, browser tests for added-file hydration and
    collapse anchoring.
  - reshape: `bridge-app.tsx` hydration policy,
    `bridge-code-view-panel.tsx` rendered-item/materialization access,
    dev-server visual scripts, broad tree/color overrides, and markdown theme
    selection.
  - discard or replace: detached top-scope compatibility paths and
    branch-specific target-file heuristics in proof scripts.
- Current local source counts before the next implementation pass:
  `bridge-app.css` 195 lines, `bridge-trees-panel.tsx` 182 lines,
  `bridge-code-view-panel.tsx` 765 lines, `bridge-app.tsx` 1330 lines, and
  `bridge-pierre-worker-pool.tsx` 1069 lines. Any task that assumes the older
  small scaffold must re-read the file before editing.

Execution order amendment, 2026-06-19:

- Merge `origin/main` into this branch before more UX or IPC implementation.
  Main has changed Swift feature/file structure, so conflict resolution is a
  correctness gate rather than repo hygiene.
- Finish the dev-server DiffsHub-class interaction loop before native proof:
  compact right rail, shadcn/Base UI controls, Catppuccin Mocha tokens,
  markdown rendering, added-file content, collapsible headers, file click to
  CodeView scroll, and browser-controlled visual comparison against DiffsHub
  example PRs.
- Review-mode and summary controls are part of the interaction loop only when
  they are integrated into the same compact AgentStudio/Pierre surface,
  preferably the right rail or same-plane app chrome. Do not resume new Swift
  IPC surface work while the browser or native screenshot still shows a
  detached pure-black
  `All / Changed / Guided / Change set / Docs/plans / Tests / Source` strip,
  mismatched header typography, or controls that do not sit on the Mocha
  AgentStudio/Pierre header plane. The target control is a compact
  normal/guided/plans-specs review-mode segmented control plus separate facet
  controls for Git status, file kind, path, extension, scope, and search.
- Add semantic Bridge IPC control before large native performance proof. The
  real branch cannot be measured repeatably if agents cannot drive file
  selection, tree search/filter/reveal, content fetch, markdown preview, and
  telemetry snapshots without manual clicks.
- Then prove large-diff performance on the real current worktree through the
  native AgentStudio Bridge pane, with Victoria Stack telemetry as the source of
  truth for package push, tree/render/search/reveal, file selection, CodeView
  hydration/render, markdown render, worker readiness, content fetch, and scroll
  responsiveness.

Manual visual review blocker, 2026-06-19:

- Current BridgeWeb code partially uses shadcn/Base UI, but not enough for this
  gate. `BridgeWeb/components.json` now exists with `style = base-mira`, and
  generated `Button`, `DropdownMenu`, `Input`, `Popover`, and `Tooltip`
  primitives exist under `BridgeWeb/src/components/ui`. The failing surfaces are
  the Bridge-owned wrappers and shell composition: top header/scope controls,
  right rail toolbar, filter/search wrappers, and CodeView custom headers still
  look like bespoke Tailwind widgets instead of compact shadcn/Base UI controls
  tuned with AgentStudio/Pierre Mocha tokens.
- Buttons must match the app sidebar language: compact icon-led shadcn controls,
  no always-visible heavy outlines, no native/select-looking black pills, and
  only hover/focus/pressed states drawing the border or raised surface.
- Remove or replace the detached top `All / Changed / Guided / Change set /
  Docs/plans / Tests / Source` bar. The review-mode affordance must become a
  compact shadcn-style toggle/segmented control for normal review, guided
  review, and plans/specs. Changed/current-scope/docs/tests/source must move to
  facet controls where appropriate. A black floating strip is a failed proof
  state. The unexplained hamburger/list icon in the top-left header is also a
  failed proof state unless it owns a clear app action and matches the icon
  system.
- File headers must use Lucide or generated-system icons, not local ad hoc SVG
  drawings. Each header needs a stable collapse/expand button with synced
  `aria-expanded`, no text cursor affordance, no duplicate path rendered on both
  left and right, no extra Bridge-owned status/kind icon stacked before
  Pierre's file icon, a clear faint boundary between files, and DiffsHub-like
  sticky behavior while scrolling.
- File rail clicks must align the target file header to the top of the CodeView
  viewport and remain stable after collapse/expand. Collapse/open must not jump
  the scroll owner unexpectedly, desync the chevron, or make the file boundary
  ambiguous.
- Motion is now a hard browser gate. CodeView scroll, rail click-to-file,
  collapse/expand, and hydration after selection must feel like DiffsHub rather
  than a teleport. Static screenshots do not close this row. Use Playwright,
  Browser Mode, or video-derived frame analysis to compare BridgeWeb against a
  DiffsHub reference and fail the checkpoint when scroll deltas spike, the
  selected file does not settle at the top, a pinned header is displaced, or
  collapse/expand changes the scroll anchor unexpectedly.
- Skeletons and pending placeholders must live inside the CodeView item they
  represent. A floating loading block in open canvas, a skeleton detached from
  its file header, or a placeholder that collapses/expands the scroll space
  differently than loaded content is a failed state.
- BridgeWeb must not trigger Pierre/React lifecycle warnings during CodeView
  materialization. In particular, avoid calling Pierre imperative `updateItem`
  or related item mutations directly from React lifecycle phases when that
  causes `flushSync` warnings. Route imperative mutations through a
  feature-owned post-effect scheduler/queue, then prove streaming append,
  selected-file hydration, collapse/expand, and large-fixture scroll run with a
  clean browser console.
- Added files must render as full added content through the Bridge content
  handle path and Pierre CodeView item model. A mostly black body or placeholder
  row for added files is a failed UX state.
- Scrollbars, file separators, status colors, added/deleted backgrounds, and
  selected row/header colors must be compared against the DiffsHub Node PR
  reference and the AgentStudio Mocha palette. Current screenshots with black
  file bodies, mismatched green backgrounds, or detached top chrome do not pass.
- Tests must capture these exact blockers: browser/Playwright assertions for
  shadcn primitive composition on controls, no detached top strip, no hamburger
  without action, file header icon/collapse state, no Bridge status/kind icon
  in the CodeView prefix slot, no duplicate header path, click-to-top alignment,
  collapse no-jump behavior, added-file full green content, and visual-proof
  crops for top header, open filter, scrolled rail, scrolled CodeView, and
  added-file content.

Visual checkpoint, 2026-06-19:

- Current hard gate is now DiffsHub PR 180 parity, not merely nonblank local
  rendering. Reference URL:
  `https://diffshub.com/ShravanSunder/agentstudio/pull/180`.
  Browser capture must force dark mode with `theme = dark` and
  `diffshub-dark-theme = catppuccin-mocha`; otherwise DiffsHub may fall back to
  another dark theme in headless Chromium and the comparison is invalid.
  Current valid reference
  screenshot:
  `BridgeWeb/tmp/bridge-viewer-visual-proof/compare-pr180-2026-06-19T18-56-50-515Z/diffshub-dark.png`.
- Current local worktree screenshot:
  `tmp/bridge-viewer-visual-proof/2026-06-19T18-59-29-384Z-dev-server/large-scrolled-view.png`.
  It proves the dev server renders and selects `.github/workflows/ci.yml`, but
  does not prove parity. Known open deltas: the outer shell is still too purple
  compared with DiffsHub's `rgb(16, 16, 16)` dark chrome, the top projection
  control remains a Bridge-only row rather than DiffsHub-class chrome, the right
  rail controls still need compact hover-only shadcn/Base UI behavior, and file
  header/scroll interactions still need strict browser assertions.
- The dev visual proof script must be fixture-aware. It previously hardcoded
  `Sources/BridgeViewer/NewPanel.ts`, which fails against the real worktree
  fixture. The accepted harness resolves a preferred target path from the
  actual `file-tree-container` shadow DOM, then records `targetDisplayPath`,
  `selectedDisplayPath`, theme colors, screenshots, and worker state.
- Dev-server verifier JSON must include a typed `hydrationDiagnostics` object
  for the current hydration bug: CodeView item count, rendered `diffs-container`
  item id count/ids when exposed, selected item id/path, selected content
  state, selected cache/role/character/line counts, selected materialization
  type/version/update-result and materialized line counts, empty expanded
  header count, and an explicit `visibleHydratedCacheCountAvailable` flag. As
  of this slice, visible hydrated cache count is reported unavailable because
  no app-side diagnostic attribute exposes it.
- Browser visual QA confirmed the apparent "three icons before the file name"
  came from CodeView header slot composition: Bridge rendered a collapse button
  and status badge in `slot[name="header-prefix"]`, while Pierre rendered its
  own `svg[data-change-icon="file"]` for the file path. The accepted contract is
  now stricter: Bridge's prefix slot renders only the collapse/expand button.
  File status remains in the file rail/tree and summary metadata; it does not
  stack beside Pierre's file icon in the CodeView header.
- Header proof must inspect the slotted DOM, not only normal descendants:
  `slot[name="header-prefix"].assignedElements()` for Bridge controls and
  `slot[name="header-metadata"].assignedElements()` for count metadata. A
  selector that looks only inside `diffs-container.shadowRoot` can miss the
  Bridge-owned prefix and produce false confidence.
- Review-mode proof must inspect the actual browser-rendered header, not just
  React props. The accepted state is compact normal/guided/plans-specs mode
  controls, one active `aria-pressed` or equivalent selected state, compact
  typography, transparent/same-plane background, and no detached pure black
  scope strip. Facets live in the filter/search controls, not as extra
  top-level mode buttons. The dev-server verifier owns this check.
- The right rail toolbar must not duplicate test ids between wrappers and
  buttons. `bridge-review-search-toggle` belongs to the button only; wrapper
  slots use their own ids. Icon controls in the rail must remain hoverable and
  visually consistent even when the underlying feature is not implemented yet.

2026-06-19 correction: earlier checkpoint text that allowed a Bridge status
badge in the CodeView header is superseded. The canonical grammar is exactly:
Bridge collapse/expand affordance in Pierre's header-prefix slot, then
Pierre-owned file icon/path, then count metadata. File status and class remain
in the right rail/tree and summary metadata.

Shadcn theming source-of-truth amendment, 2026-06-19:

- Canonical shadcn preset is Mira on Base UI with small radius. The preset code
  resolved locally is `b1D0dxoG`, which decodes to `style = mira`,
  `baseColor = neutral`, `theme = neutral`, `iconLibrary = lucide`,
  `radius = small`, `menuAccent = subtle`, `menuColor = default`, `font = geist`,
  and `fontHeading = inherit`.
- Shadcn theming is the first layer. BridgeWeb must let shadcn own semantic UI
  token names, component primitives, menu/button/input focus semantics, and
  radius scale. AgentStudio then maps those semantic tokens to Catppuccin Mocha
  and app-specific dark chrome in `BridgeWeb/src/app/bridge-app.css`.
- Component overrides are downstream of the theme. Bridge review wrappers may
  tune density, layout, and domain-specific states, but they must not replace
  the shadcn semantic token layer with unrelated one-off colors, radii, fonts,
  or focus styles.
- Current shadcn CLI guard: `shadcn apply mira` failed because
  `BridgeWeb/components.json` declares `@/*` aliases, but `BridgeWeb/tsconfig.json`
  and `BridgeWeb/vite.config.ts` do not define matching aliases. Fix the alias
  contract first, then apply/regenerate the Mira/Base UI theme/components.
- 2026-06-19 correction: after adding matching `@/*` resolution in
  `BridgeWeb/tsconfig.json` and `BridgeWeb/vite.config.ts`,
  `pnpm --dir BridgeWeb exec shadcn info` reports Tailwind v4, import alias
  `@`, `style = base-mira`, `base = base`, `iconLibrary = lucide`,
  `radius = small`, installed `button`, `dropdown-menu`, `input`, `popover`,
  and `tooltip`. Do not reintroduce `base-nova`, Hugeicons, or font package
  dependencies for BridgeWeb chrome.

Execution checkpoint, 2026-06-18 20:42 local:

- Native blank/smoke blocker is resolved for the current branch build. Fresh
  `Agent Studio Debug oq4s` marker
  `debug-observability-oq4s-1781829578-58944` completed
  `bridge-review-observability-smoke`; worker pool state was `ready`, manager
  state was `initialized`, total workers was `2`, CodeView height was `1077px`,
  diff container height was `152px`, rendered code line count was `14`, selected
  content was `ready`, page issue count was `0`, and render proof succeeded.
- This does not close the DiffsHub visual parity work. The latest manual
  DiffsHub-vs-Bridge screenshots still show the Bridge right rail/search/filter
  chrome as too buttony, oversized, and visually detached from the compact
  DiffsHub/AgentStudio sidebar grammar. Keep Task 5 and the rail/filter proof
  rows open until screenshots, bbox checks, and behavior tests prove the
  compact icon-first rail.
- Native screenshot capture now works for the smoke pane:
  `tmp/bridgeweb-visual-proof/2026-06-18-agentstudio-debug-oq4s-bridge-smoke.png`.
  This proves the native pane is nonblank, but it is still only the small
  one-file smoke fixture. Large-fixture native visual proof remains open: it
  must capture the DiffsHub-class right rail, scrolled CodeView, scrolled rail,
  and open filter/search states before PR readiness.
- Visual sidecars/subagents may collect DiffsHub-vs-Bridge measurements and
  screenshots, but they do not close Task 5. The main executor owns the plan
  update, code changes, browser proof, native proof, and final pass/fail call.
  Treat the rail/header work as unresolved until the live Bridge controls are
  compact, icon-led, and integrated with the AgentStudio sidebar grammar rather
  than merely nonblank.
- Current manual/native acceptance blockers are still open. Markdown rendering
  has not been accepted in the real AgentStudio debug Bridge pane and remains
  blocked until the manual/WKWebView path proves sanitized markdown render
  through packaged BridgeWeb assets. The current real worktree
  `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
  on branch `luna-338-pierreshikitrees-review-viewer` is itself a required
  performance fixture because manual use there observed slow selection,
  scrolling, and rendering. Mocked large fixtures are necessary for repeatable
  browser proof, but they are not sufficient for PR readiness without this real
  Bridge package/worktree path.

Source spec:

- `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`

Related source:

- `docs/superpowers/specs/2026-06-18-bridgeweb-dev-visual-proof-harness.md`
- `docs/plans/2026-06-16-bridge-viewer-diffshub-polish.md`

## Goal

Make BridgeWeb large-diff UX debuggable and provable before further visual
polish: add a fast Vite dev-server harness with deterministic large fixtures,
use Vitest Browser Mode + Playwright as the first behavior/performance proof
layer, fix the reproduced scrolling/click/header/content problems, then prove
the same behavior in the real AgentStudio debug Bridge pane.

The live visual baseline for this plan is DiffsHub rendering the AgentStudio PR
180 shape:

- `https://diffshub.com/ShravanSunder/agentstudio/pull/180`

The live scale/performance reference for this plan is DiffsHub rendering Node
PR 59805:

- `https://diffshub.com/nodejs/node/pull/59805`
- observed reference scale: about 3,420 files, 168,778 additions, 99,119
  deletions, and about 1,952,384 lines

The local fixture may be synthetic, but it must be Node-PR-class in the ways
that matter to the product: thousands of paths, deep virtualized tree
navigation, search/reveal/select, a huge selected file/diff, worker-backed
rendering, compact collapsible headers, and a single CodeView scroll surface.

## Non-Negotiable Product Requirements

This plan is not complete when lower-layer tests are green. It is complete only
when each user-visible requirement below has matching browser and native proof,
or an explicitly approved split/replan says why a row moved out of scope.

| Requirement | Current proof needed | Completion rule |
| --- | --- | --- |
| DiffsHub-class dark review surface | Screenshot from Vite dev loop and AgentStudio debug pane | Black/dark canvas, compact chrome, right-side rail, and no unstyled/native form controls are visible. |
| Large fixture target | Fixture metadata and screenshot | Default dev route uses `large-diffshub` or a Node-PR-class equivalent with thousands of files, huge selected diff/file payload, docs/plans, tests, source, deleted, renamed, and added files. |
| Right-side file rail | Browser interaction test and screenshot | File rail is right-side, compact, independently scrollable, searchable, filterable, and clicking a file selects and scrolls CodeView to that file. |
| CodeView scroll ownership | Browser scroll test, benchmark row, and native screenshot | CodeView owns the main review scroll; document/body/root do not drift while review content scrolls. |
| CodeView motion quality | Browser motion probe or video/frame analysis plus DiffsHub reference | Scroll, rail click-to-file, collapse/expand, and hydration settle smoothly without teleporting, large frame-delta spikes, displaced pinned headers, or unexpected scroll-anchor jumps. |
| Loading placement | Browser screenshot/video and DOM assertions | Skeletons and placeholders render inside the target CodeView item/header space and do not float in canvas or move the scroll anchor when content hydrates. |
| Clean CodeView update lifecycle | Browser console/assertion gate | Streaming append, selected-file hydration, collapse/expand, and large-fixture scroll do not emit React/Pierre `flushSync` or lifecycle warnings from Bridge-owned imperative updates. |
| Collapsible file headers | Browser test and screenshot | Every mounted CodeView file header is a non-text-cursor control that toggles item collapse/expand using Pierre-supported item ownership. |
| Added file content | Browser test, benchmark row, and native screenshot | Added source files show full fetched content through the Bridge content-handle lane, not placeholder rows. |
| Markdown preview | Browser test, worker ledger, sanitizer assertions, and real AgentStudio debug-pane screenshot/state | `.md` files render a sanitized markdown preview through the markdown worker path by default; native/manual Bridge markdown remains an active blocker until proven in WKWebView, not only mocked/browser tests. |
| Hunk expansion | Browser test and benchmark row | Collapsed unchanged sections expand additional context and remain responsive on large fixtures. |
| Worker-backed rendering | Browser worker proof, benchmark worker flags, and asset audit | Product proof uses Pierre CodeView worker pool and markdown worker lanes; worker-disabled fallback cannot satisfy this row. |
| shadcn/Base UI design foundation | Generated files, typecheck, component tests, and screenshot | BridgeWeb has package-local shadcn CLI configuration, generated Base UI primitives where supported, compact variants, and AgentStudio-owned dark tokens before rail chrome is considered complete. |
| Design system composition | Component tests, source review, and screenshot | BridgeWeb composes generated shadcn/Base UI primitives with `cn`, compact variants, and Catppuccin Mocha tokens; Tailwind classes are transport/layout, not a bespoke feature-local control system. |
| Visual parity with DiffsHub grammar | Side-by-side or comparable screenshots | Headers, separators, rail density, icon-first controls, and dark palette are close enough to the DiffsHub Node PR reference while matching AgentStudio styling. |
| Review-mode/header chrome | Browser screenshot crop, native screenshot crop, and bbox/color checks | The top-level control is normal review / guided review / plans-specs, rendered as compact integrated chrome, preferably in the right rail or same-plane app header. Changed/current-scope/docs/tests/source are facets, not extra top-level mode buttons. A detached pure-black pill strip, oversized tab bar, mismatched typography, unrelated hamburger/list icon, or controls that look pasted over the Mocha surface fail this row. |
| DiffsHub-class filter popovers | Browser screenshot with filter menu open, semantic assertions, and bbox measurements | Filter/search controls are compact icon-first buttons; open filter popover uses a dark raised surface, clear separators, about 32px rows, colored status badges, trailing selected checkmarks, disabled/clear affordance, `menuitemcheckbox` semantics, and no native/select-looking black pills. |
| Rail row/icon alignment | Browser screenshot, DOM checks, and bbox measurements | Tree rows use compact 24px-ish stable height, `button[role="treeitem"][data-item-path]`, consistent file/folder/status icons, right-aligned status letters, readable selected-row contrast, and disclosure chevrons sized like DiffsHub/AgentStudio controls rather than oversized row text. |
| Native packaged proof | AgentStudio debug app evidence | Packaged BridgeWeb renders the same repaired behavior through Bridge package push and `agentstudio://resource/content/...`, not a Vite/mock-only path. |

The current branch state does not satisfy this table until the browser/dev
loop and AgentStudio debug loop produce these artifacts. Green unit,
integration, build, Swift, or benchmark commands are necessary but not
sufficient.

## Non-Goals

- No Git backend redesign.
- No annotations, patch apply, approve/reject, source mutation, Monaco/editor,
  or command-surface expansion.
- No native-proof shortcut: dev-server screenshots do not replace WKWebView
  proof.
- No arbitrary workspace filesystem fixture import in this slice.
- No CI or app-launch infrastructure rewrites unless a scoped blocker is proven
  inside this plan.

## Security And Reliability Context

Assets / privileges:

- Local source and plan content rendered inside BridgeWeb.
- Packaged BridgeWeb app assets loaded by the native WKWebView.
- Worker assets and generated asset manifests.
- Browser benchmark and screenshot artifacts under `tmp/`.

Entry points:

- Vite dev server on loopback.
- Dev harness URL query params.
- Mocked Bridge package/delta/content/command lanes.
- Markdown render worker messages.
- `agentstudio://resource/content/...` content handles.
- Browser Mode and native debug screenshot/proof runners.

Untrusted inputs:

- Repository markdown/code content.
- Fixture query-param values.
- Mocked package data and worker responses.
- Content resource URLs.
- Browser console/page errors and benchmark stdout.

Security invariants:

- Dev server binds to loopback only.
- Dev query params select from typed enum values only; they cannot load local
  paths, remote URLs, arbitrary `agentstudio://`, `file:`, `data:`, or custom
  schemes.
- Repository markdown remains sanitized before DOM insertion; images and active
  links stay inert per the existing markdown security plan.
- Dev mocked-backend code is not bundled into native packaged BridgeWeb assets.
- Dev worker paths are explicit. Plain Vite dev must not accidentally try to
  fetch packaged-only `agentstudio://app/...` worker URLs for worker-backed
  CodeView or markdown scenarios.
- Browser screenshots and benchmark artifacts stay repo-local under `tmp/`.
- Worker-disabled proof never substitutes for product worker-backed proof.
- Vite/browser proof never substitutes for packaged AgentStudio proof. The fast
  loop finds and fixes issues; the outer loop must still prove the packaged
  BridgeWeb app inside the AgentStudio debug Bridge pane using Bridge package
  push and `agentstudio://resource/content/...` content fetches.

Required proof:

- Dev scenario resolver unit tests reject unknown params.
- Dev worker-on scenario proof supplies a dev-safe Pierre worker factory and a
  dev-safe markdown worker client, or it is explicitly split before execution.
- Build/audit proves packaged asset boundaries.
- Markdown sanitizer and content-resource URL tests remain green.
- Browser failure guards fail on console errors, uncaught errors, and unhandled
  rejections unless explicitly allowlisted. If the installed Browser Mode
  provider exposes a page-error hook, use it; otherwise record the inspected API
  boundary in the implementation proof.

## Source Coverage

Loaded and checked:

- Spec amendment:
  `docs/superpowers/specs/2026-06-18-bridgeweb-dev-visual-proof-harness.md`
  has 356 lines, read in full.
- Existing DiffsHub polish plan:
  `docs/plans/2026-06-16-bridge-viewer-diffshub-polish.md`
  was re-read in full after the 2026-06-19 reset amendments.
- Current BridgeWeb evidence:
  `package.json`, `vite.config.ts`, `index.html`, `bridge-app-bootstrap.tsx`,
  `bridge-app.tsx`, `vitest.browser.config.ts`,
  `tests/vitest-browser-setup.ts`, `bridge-viewer-mocked-backend.ts`, and
  `bridge-viewer.browser.benchmark.tsx`.

Important current-state facts:

- Browser Mode and browser benchmark scripts already exist:
  `test:browser`, `test:browser:integration`, and `test:benchmark:browser`.
- The feature worktree already contains substantial BridgeWeb implementation
  edits and untracked files for chrome, markdown, worker, browser-test, and
  benchmark lanes. Execution must inventory and reconcile existing work before
  creating new files or duplicating concepts.
- Current `BridgeWeb/index.html` mounts `BridgeApp` directly, so Vite dev can
  show an empty waiting shell instead of a useful fixture.
- The mocked backend already has fixture classes:
  `small-mixed`, `medium-agentstudio`, and `large-diffshub`.
- The current large fixture is not yet enough as a visual target because it can
  still over-represent generated/added rows and does not force every broken UX
  path into the fast loop.
- Browser failure guards currently catch console errors, `window.error`, and
  unhandled promise rejections, with a narrow existing React `flushSync`
  allowlist.
- Current DiffsHub/Pierre research is recorded in:
  `tmp/research-workflows/2026-06-18-bridgeweb-diffshub-node-pr-parity/research-ledger.md`.
- Live browser research found the local large path
  `large/browser/huge-diff.ts` is not initially mounted in the virtualized
  tree. Search can reveal it, but the post-search click path does not yet
  reliably persist selected row state, update CodeView header/content, or avoid
  a long-running browser probe.
- Pierre FileTree `scrollToPath` only works for visible paths. BridgeWeb must
  expand ancestor directories through public FileTree item handles before
  focusing and scrolling a selected deep file path.

## Requirements And Proof Matrix

| Requirement | Task | Proof owner | Proof gate | Layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| Existing partial implementation is reconciled | 0 | executor | inventory notes and git diff review | planning/execution | no duplicate dev bootstrap, fixture, worker, or benchmark concepts are created | green required |
| Dev-only bootstrap cannot leak into packaged assets | 1 | executor | asset-contract unit test and build/audit | unit + build | packaged output rejects `bridge-app-dev-bootstrap` and mocked-backend imports | red/green required |
| Vite dev opens useful viewer by default | 1 | executor | resolver unit test, dev smoke screenshot | unit + visual | URL with no params must choose large fixture, not empty shell | red/green required |
| Dev scenarios are typed and query-selectable | 1 | executor | scenario resolver unit tests | unit | unknown fixture fails with useful error | red/green required |
| Boundary payloads are Zod-first | 1, 3, 6, 8 | executor | schema unit tests, typecheck, architecture review | unit + typecheck + review | every Swift/Web, worker RPC, dev-fixture, benchmark, telemetry, and IPC/debug payload has a camelCase `xxxSchema`, PascalCase inferred `Xxx` type, discriminated unions for variants, and exactly-one boundary parse before Zustand/projection internals | red/green required |
| Dev harness reuses BridgeApp and mocked Bridge lanes | 1 | executor | Browser/dev smoke with push, projection, content, command ledgers | integration/browser | no forked viewer or direct Pierre state mutation | green required |
| Dev harness supports existing delivery modes | 1, 7 | executor | resolver tests and streaming-append smoke | unit + browser | `delivery=full-load|streaming-append` reuses mocked backend owner | red/green required |
| Dev worker-on paths are real or explicitly split | 1, 6 | executor | dev worker browser smoke | browser | no plain Vite fetch of packaged-only `agentstudio://app/...` worker URLs | red/green required |
| Large fixture represents real review work | 2 | executor | fixture metadata unit tests and visual screenshot | unit + visual | modified/deleted/renamed/docs/tests/source counts recorded | red/green required |
| Large fixture is large enough to reproduce DiffsHub-class UX issues | 2, 7 | executor | fixture metadata and browser perf rows | unit + performance/browser | `large-diffshub` meets minimum item/diff-line/package-size targets and optional stress fixture is recorded separately | red/green required |
| Added files show full fetched content | 2, 5 | executor | Browser click test and materialization unit test | unit + browser | content must arrive through handle fetch ledger | red/green required |
| Large-fixture file clicks are responsive and stable | 3 | executor | large browser performance scenario and interaction test | browser + performance | row uses `fixtureClass: large-diffshub`, visible selected text changes, mark-viewed command captured, selected header scrolls quickly to the top/sticky threshold, and no snapback/jump-around occurs | red/green required |
| Large search/reveal/select is stage-proven | 3 | executor | targeted Browser Mode or Playwright stage artifact | browser + performance | stages record search settle, row click, selected row state, selected item/store state, CodeView header/path, content hydration, and scroll movement | red/green required |
| Large projection/search/filter stays off main thread | 3, 4, 7, 8 | executor | browser artifacts and native Victoria telemetry | browser/performance + native/observability | large search, reveal, select, projection-chip, and filter scenarios record `projectionExecutionLane=worker` or equivalent; product-runtime sync fallback is allowed only for tiny fixtures or unit-test-only seams and cannot satisfy PR readiness | red/green required |
| Selected deep paths reveal collapsed ancestors | 3, 4 | executor | FileTree controller unit test and large browser proof | unit + browser | selected path expands ancestor directories before `scrollToPath`; no hidden-path no-op | red/green required |
| Large-fixture CodeView scroll works | 4 | executor | large browser scroll test plus screenshot | browser + visual | row uses `fixtureClass: large-diffshub`; body/document/shell root scroll remain stable | red/green required |
| Large-fixture right rail scroll works independently | 4 | executor | large Browser rail scroll test plus screenshot | browser + visual | tree visible row window changes without CodeView drift | red/green required |
| File click and collapse preserve header geometry | 3, 4, 5, 8 | executor | Playwright top-offset assertions plus native stage proof | visual/browser + native | rail click aligns the target file header to the top/sticky threshold; mid-viewport collapse/expand preserves the header top within a small tolerance while content below moves; pinned-header collapse remains pinned | red/green required |
| Content hydration stays request-scoped | 3, 5, 7, 8 | executor | unit/integration/browser fetch-ledger tests and benchmark artifact | unit + browser + performance | package push remains metadata-first; cold mount hydrates the selected/revealed item only, not every rendered placeholder row; large fixtures must not hide bridge bandwidth regressions behind broad visible prefetch | red/green required |
| Header/chrome matches target grammar | 5 | executor + reviewer | structural tests and screenshot | unit + visual | no native selects; compact custom controls visible | red/green required |
| Filter popover matches DiffsHub/AgentStudio grammar | 5 | executor + visual reviewer | screenshot with menu open plus component/browser assertions and bbox probe | unit + visual/browser | open popover shows raised surface, separators, status badges, selected checkmarks, clear affordance, no tiny native-looking dropdown pills, `aria-haspopup="menu"`, toggled `aria-expanded`, `menuitemcheckbox` or equivalent checked state, and measured width/row/badge/checkmark geometry close to DiffsHub | red/green required |
| Rail rows match DiffsHub density and icon discipline | 5 | executor + visual reviewer | screenshot crop plus browser row assertions | visual/browser | compact 24px-ish rows, 13px-ish text, pointer/no text-selection behavior, consistent icons, right-aligned status, selected row contrast, proportionate disclosure controls, and real Pierre tree disclosure/search/selection state | red/green required |
| Rail chrome dimensions are measured | 5 | executor + visual reviewer | Playwright bbox probe and screenshot | browser + visual | search/filter affordances stay icon-scale in compact hit targets; popover width/height/offset, toolbar button boxes, and row height are recorded against DiffsHub baseline including ~16px rail glyphs, 32px menu rows, and ~235px-wide status menu | red/green required |
| BridgeWeb shadcn/Base UI foundation exists | 5 | executor | CLI transcript, generated files, typecheck, component tests | config + unit + build | `BridgeWeb/components.json` is package-local; required primitives are generated by shadcn CLI with Base UI where available; review chrome composes generated primitives or wrappers over them | red/green required |
| AgentStudio/Pierre theme tokens drive chrome | 5 | executor + visual reviewer | CSS token tests or snapshot, browser screenshot, native screenshot | unit + visual/native | tokens are sourced from AgentStudio dark styling plus Pierre dark references; rail/popover/search/tree/CodeView use shared variables instead of ad hoc per-control colors | red/green required |
| Pierre APIs are used properly | 5 | executor | component tests, architecture check, visual proof | unit + architecture | public imports only; compact density and expand-matches asserted | green required |
| Heavy rendering remains off main thread | 6 | executor | worker-backed browser integration and performance row | browser + performance | worker flags recorded; worker-disabled baseline does not satisfy row | green required |
| Markdown preview is secure and visible | 6, 7, 8 | executor + reviewer | sanitizer tests, browser scenario, screenshot | unit + browser + native | DOMPurify sink preserved; links/images inert; resource URLs validated before markdown render | red/green required |
| Failure/unavailable UI remains proven | 7, 8 | executor | Browser scenario and screenshot/state capture | browser + native | content failure cannot be optimized away or counted as optional | red/green required |
| Streaming append and stale-drop remain proven | 1, 7 | executor | benchmark rows and hold/release browser tests | browser + performance | current `medium-streaming-append-delta` and `stale-generation-drop` scenario contract is preserved | red/green required |
| Browser performance rows are durable and verified | 7 | executor | `test:benchmark:browser` artifact verifier | performance | current runner `requiredScenarioIds` is the floor; recompute p50/p95 from raw samples | red/green required |
| Large select and scroll rows are mandatory floor scenarios | 3, 4, 7, 8 | executor | benchmark runner contract and verifier | performance/browser + native/performance | required scenario floor includes large-fixture semantic select, large CodeView scroll ownership, and large rail scroll ownership rows with `fixtureClass: large-diffshub`; native proof records comparable real-worktree stages | red/green required |
| Semantic Bridge IPC drives native proof | 8 | executor | IPC integration tests and debug IPC transcript | integration/native | Bridge-scoped `bridge.review.*`, `bridge.fileTree.*`, `bridge.fileView.*`, and `bridge.telemetry.*` commands drive product ports, not command palette UI or raw WebKit evaluation. Hot file/diff/markdown bodies load through `agentstudio://resource/*`, not IPC results. | red/green required |
| Victoria Stack is performance source of truth | 8 | executor | Victoria metrics/traces/log query artifact | native/performance/observability | native proof correlates IPC actions and screenshots with debug-scoped Bridge/Pierre telemetry for package push, tree render/search/reveal, file select, content fetch, CodeView hydration/render, markdown render, worker readiness, and scroll responsiveness | green required |
| Current real worktree performance is stage-proven | 8 | executor | real AgentStudio debug pane stage artifact | native/performance | uses `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start` on `luna-338-pierreshikitrees-review-viewer`; records package push, tree render/search/reveal, file select, CodeView hydration/render, markdown render, and scroll responsiveness timings | green required |
| Real AgentStudio pane proves same behavior | 8 | executor | debug app IPC/visual proof | smoke/native | real large worktree/package path after packaged build; debug-only mock cannot be sole proof | green required |
| AgentStudio outer loop uses packaged BridgeWeb and content scheme | 8 | executor | debug app render state plus package/content ledger | smoke/native | evidence shows packaged assets, Bridge package push, and `agentstudio://resource/content/...`; Vite/dev server cannot satisfy this row | green required |
| PR readiness has full proof chain | 9 | executor + review swarm | implementation review + PR wrapup | review/PR | checks and visual/browser/native artifacts are current | green required |

## Task Sequence

Commit hygiene for execution:

- Commit coherent green checkpoints after scoped proof gates pass so work is
  not lost during the long BridgeWeb/native loop.
- Do not commit broken checkpoints, failing proof states, or partial changes
  that cannot be explained as a coherent recoverable slice.

### Task -1: Merge Current Main And Rebaseline

Write surfaces:

- Conflict-resolution edits only.
- Workflow state notes if conflict resolution changes the Bridge/IPC plan.

Implementation:

- Fetch and merge `origin/main` into this branch before further UX/IPC work.
- Resolve Swift feature/file-structure conflicts by following the current main
  architecture, not stale branch names.
- Preserve the generated-assets policy: `Sources/AgentStudio/Resources/BridgeWeb/app/`
  remains generated/ignored and is rebuilt by mise/BridgeWeb build tasks.
- Re-run the minimum focused gates needed to prove the branch still builds
  before resuming BridgeWeb UX work.

Proof:

- `git status --short --branch` before and after merge.
- Conflict files named in the workflow state if conflicts occur.
- `mise run bridge-web-build`
- `mise run test -- --filter Bridge`
- `mise run lint` if Swift conflict resolution touches source or architecture.

### Task 0: Inventory Current Partial Implementation

Write surfaces:

- `tmp/workflow-state/2026-06-19-bridgeweb-diffshub-shadcn-reset/details.md`
- `tmp/bridge-viewer-visual-proof/<timestamp>/implementation-inventory.md`

Implementation:

- Inspect the current dirty worktree before adding files. The current branch
  already contains BridgeWeb changes for browser tests, benchmark runner,
  chrome, markdown, worker lanes, generated assets, and IPC diagnostics.
- Classify existing files as:
  - keep and finish
  - keep but adjust to this plan
  - superseded by this plan
  - unrelated/pre-existing and ignored
- Do not create duplicate dev-bootstrap, mocked-backend, fixture, browser
  benchmark, markdown worker, or chrome primitives if equivalent files already
  exist.
- Record the inventory in the workflow details or visual-proof artifact so the
  implementation review can distinguish new work from pre-existing branch work.

Proof:

- `git status --short` captured before execution.
- Inventory names the existing files used by each task.
- No duplicated concept files are created during Task 1 or Task 2.

### Task 1: Make Vite Dev Harness Real

Write surfaces:

- `BridgeWeb/package.json`
- `BridgeWeb/index.html`
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/src/app/bridge-app-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`
- `BridgeWeb/src/app/bridge-app-dev-fixture.ts`
- `BridgeWeb/src/app/bridge-app-dev-fixture.unit.test.ts`
- `BridgeWeb/scripts/app-asset-contract.ts`
- `BridgeWeb/scripts/app-asset-contract.unit.test.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/scripts/capture-bridge-viewer-dev-visual-proof.ts`

Implementation:

- Add `pnpm --dir BridgeWeb run dev` as a loopback-only script, for example
  `vite --host 127.0.0.1`.
- Keep Vite bound to loopback through script and/or Vite server config, and
  include a proof step that inspects the launched dev URL/host.
- Split bootstrap responsibilities so dev-only mocked-backend code cannot enter
  the packaged native build:
  - packaged/native bootstrap mounts `BridgeApp` with real Bridge transports
  - dev bootstrap installs `BridgeViewerMockedBackend`, pushes the selected
    fixture, and passes mocked `fetchContent` and projection worker client into
    `BridgeApp`
  - build output and asset audit must prove the dev mocked backend is not
    bundled into `Sources/AgentStudio/Resources/BridgeWeb/app/assets/bridge-app.js`
- Extend the asset contract to reject `bridge-app-dev-bootstrap` and dev-only
  mocked-backend/test-support imports in packaged output.
- `bridge-app-dev-fixture.ts` is a typed query resolver/adapter only. It must
  delegate to the existing `makeBridgeViewerBrowserFixture(...)` and
  `installBridgeViewerMockedBackend(...)` fixture owner; do not create a second
  fixture schema or duplicate fixture data.
- Default fixture should be `large-diffshub` for UX work.
- The default-route screenshot is accepted only after the minimum
  `large-diffshub` fixture repair in Task 2 is complete. Before Task 2, a
  smoke may prove the dev harness mounts, but it cannot satisfy visual target
  proof.
- Query params:
  `fixture=small-mixed|medium-agentstudio|large-diffshub|off`,
  `delivery=full-load|streaming-append`,
  `latency=zero|small|slowBounded`,
  `workers=on|off`, and `scenario=default|scroll|markdown|failure`.
- The large-diff spec supersedes the older dev-harness default of
  `medium-agentstudio`: default route is `large-diffshub` once Task 2 fixture
  repair is complete. The older `delivery` parameter remains supported.
- Rewrite the dev-server proof scripts as fixture-aware harnesses, not
  path-specific demos:
  - no hardcoded `Sources/BridgeViewer/NewPanel.ts` or `NewPanel` search text
    in verifier logic
  - resolve target paths from fixture metadata or the active
    `file-tree-container` DOM
  - record `targetDisplayPath`, `selectedDisplayPath`, fixture id/class,
    worker state, hydration diagnostics, and screenshot paths in the proof
    artifact
  - the same verifier shape must work for at least two large-fixture variants
    whose selected added-file paths differ, and for the real-worktree fixture
    whose paths are discovered at runtime
- Dev-server Playwright proof must use event/DOM waits, not fixed sleeps. Both
  verifier scripts must install console-error, page-error, uncaught-error, and
  unhandled-rejection guards with the same narrow allowlist discipline as the
  Vitest Browser Mode setup. A partial DOM after a runtime error is a failed
  proof, not a pass.
- For `workers=on`, provide dev-safe worker wiring:
  - CodeView/Pierre: explicit dev worker factory or dev worker script URL that
    works in plain Vite.
  - Markdown: explicit dev-safe `markdownWorkerClient` or markdown worker
    transport that works in plain Vite.
  If either worker lane cannot be made dev-safe in this slice, stop and split
  before accepting `workers=on` proof; do not let Vite try packaged-only
  `agentstudio://app/...` worker URLs and then count a failure/disabled state.
- Packaged/native bootstrap remains the real Bridge path and does not install
  the mocked backend.

Proof:

- Resolver unit tests fail before implementation and pass after.
- Browser/dev smoke proves a nonblank review shell appears from `pnpm run dev`.
- Screenshot captured from the dev server default route using Browser plugin,
  Playwright, or an equivalent browser screenshot tool.
- Build/audit proves packaged BridgeWeb assets do not include the dev-only
  mocked backend or scenario UI.
- Asset-contract unit tests fail if packaged HTML, manifest, or bundled JS
  references `bridge-app-dev-bootstrap`, mocked backend modules, or dev scenario
  resolver modules.
- Streaming-append dev smoke proves a delta updates the right rail without
  resetting selection.
- Worker-on dev smoke proves visible CodeView and markdown preview without
  packaged-only worker URL failures, or the worker slice is explicitly split.
- Verifier unit or scripted negative proof shows a console/page/runtime error
  fails the dev-server proof, and a delayed-render fixture still passes through
  event/DOM waits without wall-clock sleep dependence.

### Task 2: Repair Fixture Shape Before UX Polish

Write surfaces:

- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`
- `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx`

Implementation:

- Make `large-diffshub` visually useful: fewer placeholder-only added rows,
  realistic modified diffs, docs/plans, tests, source, deleted, renamed, and
  nested files.
- Complete the minimum `large-diffshub` repair before accepting the default
  dev-route visual proof from Task 1.
- Add explicit fixture scale targets:
  - `small-mixed`: around 100 files, at least one modified diff, added source
    file, docs markdown file, hunk expansion target, and failure target.
  - `medium-agentstudio`: at least 1,000 files with source, tests, docs/plans,
    added, modified, deleted, renamed, config, and nested directories.
  - `large-diffshub`: at least 3,420 files, matching the Node PR 59805
    file-count class, and at least one selected diff with 100,000 logical
    lines or enough hunks/rows to force CodeView and FileTree virtualization
    under a 1728x972 viewport.
  - optional `huge-diffshub-stress`: allowed for non-default manual/perf
    stress proof when a million-line or 50k+ file fixture is needed; it must
    not make the default dev route unusable.
- Add explicit fixture metadata counts for item/path/diff lines, package bytes,
  change kind distribution, file class distribution, logical diff-line counts,
  selected large-file line counts, and full-content targets.
- Ensure every fixture has at least one multi-line added file whose visible
  content requires the content-handle fetch path.
- Keep synthetic filler rows classified as volume/virtualization stress data.
  One-line filler content is valid for scale, but it must not be the sole
  visual-parity proof. Visual proof must include representative modified diffs,
  added full-content files, markdown/docs, and real worktree rows so
  empty-looking placeholder bodies are not mistaken for useful UX.

Proof:

- Current red/green proof as of 2026-06-19:
  `bridge-viewer-mocked-backend.unit.test.ts` rejects large fixtures below
  3,420 items, `bridge-viewer-browser-benchmark-runner.unit.test.ts` rejects
  benchmark artifacts whose large rows fall below that floor, and
  `pnpm --dir BridgeWeb run test:benchmark:browser` wrote verified rows under
  `tmp/bridge-viewer-browser-benchmark/2026-06-19T08-06-14-193Z` with
  `large-diffshub` at 3,420 items, 112,310 diff lines, and a 6.5 MB package.
  Browser visual proof after the pointer/chevron cleanup is under
  `tmp/bridge-viewer-visual-proof/20260619T-large-3420-dev/`, including
  `default-large-3420-after-pointer-fix.png`,
  `default-large-3420-after-pointer-fix-measurements.json`,
  `git-status-filter-open.png`, and `git-status-filter-open-measurements.json`.

- Unit tests assert metadata distributions and required targets.
- Browser integration selects added, modified, deleted, docs/plans, tests, and
  source rows.
- Large fixture screenshot shows the intended mix rather than a wall of empty
  added rows.
- Browser performance rows record fixture id/class, item count, path count,
  logical diff-line count, package bytes, viewport, worker modes, and p95.

### Task 3: Reproduce And Fix Slow File Selection

Write surfaces:

- `BridgeWeb/src/app/bridge-app.tsx`
- `BridgeWeb/src/review-viewer/state/review-viewer-store.ts`
- `BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.ts`
- `BridgeWeb/src/review-viewer/content/review-content-loader.ts`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- relevant tests under `BridgeWeb/src/review-viewer/**`

Implementation:

- Add a Browser Mode test that clicks a visible file row in the large fixture
  and asserts selected content changes within the scenario budget.
- Assert the mocked backend captured the semantic select/reveal action and the
  selected resource URL used for content hydration.
- Add a stage-based large-path reveal/select test for
  `large/browser/huge-diff.ts`. The test must record and assert each stage
  separately:
  - search settles or direct reveal helper expands ancestors
  - target row exists in the FileTree shadow DOM
  - click or semantic select dispatches exactly one selection command
  - selected row state persists
  - selected item state changes to the huge item
  - CodeView header/path reflects the huge item
  - content hydration fetches the huge content handle
  - CodeView visible content or scroll position changes
  - the selected CodeView header aligns to the top/sticky threshold quickly,
    matching DiffsHub file-click navigation instead of jumping around
- Do not rely on full-text tree search as the only way to reveal a known item
  id/path. Use Pierre public FileTree item handles to expand ancestors before
  `focusPath` and `scrollToPath` for semantic selection paths.
- Add or update a dedicated large-fixture scenario id, such as
  `large-warm-tree-select`, or explicitly set `fixtureClass: 'large-diffshub'`
  on the row that claims large-file selection proof. The existing
  `warm-tree-select` small-fixture row may stay, but it cannot satisfy this
  requirement.
- Current selection command dispatch and content-hydration/stale-result
  side effects live in `BridgeApp` and runtime seams. Keep them there unless
  the implementation intentionally redesigns ownership and updates the
  architecture checks/tests.
- Backlog before continuing broad hydration work: split `BridgeApp` hydration
  orchestration into vertical slices with explicit responsibilities. The app
  shell should compose hooks/adapters only; pure candidate selection, cache-key
  construction, stale-result guards, hydration queue policy, and resource-cache
  projection belong in separate typed modules under the owning
  `review-viewer/content`, `review-viewer/projections`, or
  `review-viewer/code-view` slice. Do not keep adding
  large inline helpers/effects to `BridgeWeb/src/app/bridge-app.tsx`; files
  should have one reason to change and pure functions should be unit-testable
  outside React.
- Fix whichever measured lane is slow: avoid avoidable full projection rebuild,
  narrow Zustand subscriptions, keep heavy work in workers, and prevent stale
  content from snapping selection back.
- If the user-facing search path is still heavy, split search proof from
  semantic path reveal proof. Search remains a required UX feature, but
  deterministic file navigation should not depend on synchronous search over
  thousands of paths.

Proof:

- `warm_tree_select` browser performance row includes visible content,
  command ledger, content ledger, p50, p95, and budget.
- Large-fixture selection row records `fixtureClass: 'large-diffshub'`, visible
  selected content, command ledger, content ledger, p50, p95, and budget.

### Task 4: Reproduce And Fix Scroll Ownership

Write surfaces:

- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- `BridgeWeb/src/app/bridge-app.css`
- Browser tests and benchmark scenarios.

Implementation:

- Add browser tests for CodeView scroll and right-rail scroll using large
  fixtures.
- Add or update dedicated large-fixture scenario ids, such as
  `large-scroll-ownership` and `large-rail-scroll`, or explicitly set
  `fixtureClass: 'large-diffshub'` on rows that claim large scroll proof.
  The existing small-fixture `scroll-ownership` row may stay, but it cannot
  satisfy the large-diff requirement alone.
- Fix flex/grid `min-height: 0`, overflow ownership, and any CodeView/FileTree
  container sizing issues.
- Body/document/root scroll must stay at zero during review-content scrolling.

Proof:

- Browser scroll tests pass.
- `warm_scroll_ownership` performance row records behavior and p95.
- Large scroll rows record `fixtureClass: 'large-diffshub'`, changed visible
  CodeView rows, changed visible rail rows, stable document/body/shell scroll,
  p50, p95, and budgets.
- Screenshots capture top, CodeView scrolled, and rail scrolled states.
- Unit proof covers hidden deep-path reveal: ancestor directories are expanded
  before the selected file path is focused/scrolled.

### Task 5: Fix Header, Controls, And Pierre Configuration

Write surfaces:

- `BridgeWeb/components.json`
- `BridgeWeb/src/components/ui/*`
- `BridgeWeb/src/lib/*` or the existing `BridgeWeb/src/app/class-name.ts`
  class-name helper if the generated utility is redirected there
- `BridgeWeb/src/review-viewer/chrome/*`
- `BridgeWeb/src/review-viewer/shell/*`
- `BridgeWeb/src/review-viewer/trees/bridge-trees-panel.tsx`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- `BridgeWeb/src/app/bridge-app.css`

Implementation:

- Establish the design-system foundation before further rail polishing:
  - initialize/adopt package-local shadcn CLI config for `BridgeWeb`, not the
    monorepo root
  - use the CLI, not manual copy/paste, to generate the required primitives
  - configure React/Vite/TypeScript/Tailwind v4 CSS variables and Base UI
    primitives where the current shadcn CLI supports them
  - required primitives/wrappers for this slice: Button, Tooltip, Popover or
    Dropdown Menu, Input/Search, and a compact ButtonGroup/ToggleGroup-style
    segmented control for projection/view modes; add only what the rail/chrome
    actually needs
  - if the CLI cannot generate a needed primitive with Base UI, document the
    fallback in the workflow state and keep the Bridge wrapper API compatible
    with the generated shadcn component shape
  - generated imports must work in BridgeWeb's current TypeScript/Vite setup.
    BridgeWeb currently has no `@/*` path alias, so either configure aliases
    intentionally or generate/use relative-import-safe paths
  - Establish theme tokens before component styling:
    - use Catppuccin Mocha as the shadcn UI color foundation, adapted to
      AgentStudio dark chrome and Pierre dark review references for layout and
      contrast grammar. shadcn/Base UI controls and Pierre review APIs are the
      integration targets; BridgeWeb owns the final token mapping.
    - generated BridgeWeb app assets must be self-contained and must not depend
      on remote runtime imports, unaudited theme registries, or unsafe worker
      resource loading. Do not fail the build merely because an intentional
      Catppuccin Mocha theme name, token, or local chunk contains `catppuccin`
      or `mocha`.
  - cross-check Pierre's open-source theme references before applying tokens:
    `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/components.json`,
    `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/apps/diffshub/app/globals.css`,
    `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/theming/src/collections/pierre.ts`,
    `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/theming/src/collections/shiki.ts`,
    and `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre/packages/theming/test/color.test.ts`
  - expose standard shadcn/Tailwind v4 tokens (`--background`,
    `--foreground`, `--popover`, `--accent`, `--border`, `--input`, `--ring`,
    sidebar tokens) plus Bridge/Pierre aliases
  - keep the review canvas black where required; use Catppuccin Mocha-backed
    AgentStudio tokens for sidebar, popover, row, border, ring, input, and
    status colors
  - keep Pierre CodeView syntax themes on Pierre/Shiki APIs. For packaged
    WKWebView, register the Bridge-owned `catppuccin-mocha`
    CSS-variable theme with Pierre before rendering so worker-pool
    initialization does not rely on a cold dynamic theme import. Do not confuse
    syntax theme selection with shadcn UI chrome tokens.
- Replace text/native controls with compact shadcn-derived controls.
- Review-mode controls must compose the local segmented
  ButtonGroup/ToggleGroup wrapper. Do not rebuild them as a standalone
  floating text strip or as unrelated raw buttons.
- Keep file rail on the right.
- Use Tailwind v4 classes with generated shadcn CSS variables.
- Current implementation gaps to close before claiming Task 5:
  - `bridge-review-search-control.tsx` still expands a real inline `w-32`
    search input in the rail header. The target is an icon-first rail control;
    visible text entry must be compact, deliberate, and not make the rail read
    as a form row.
  - `bridge-review-filter-menu.tsx` still uses a colored rounded selected
    badge in the closed filtered state. The target is a quiet filter icon with
    at most a tiny icon-attached active indicator.
  - `bridge-trees-panel.tsx` currently hides
    `[data-item-section='git']` for changed items. That conflicts with the
    required DiffsHub-style right status column and must be removed or replaced
    with a Pierre-public styling path that keeps status letters visible.
  - `review-viewer-shell.tsx` presents search plus two filters as adjacent form
    controls. The rail header must be reworked into sidebar chrome: tree/comment
    affordances on the leading side and compact search/filter affordances on
    the trailing side, while preserving the existing filter prop/callback
    contracts.
- Rework rail filter/search chrome to follow the DiffsHub filter grammar while
  matching AgentStudio sidebar controls:
  - BridgeWeb review chrome wrappers compose generated shadcn/Base UI
    primitives or compact variants; do not hand-roll button/popover/menu/input
    semantics in feature-local code
  - closed filter/search controls are compact icon-first buttons, not
    native-looking black dropdown pills
  - the rail toolbar reads as app sidebar chrome: compact tree/comment
    affordances on one side and search/filter icon buttons on the other, with
    no visible form labels, no native select arrows, no text-cursor affordance,
    and no wide tab-like filter fields
  - toolbar affordances follow AgentStudio/DiffsHub sidebar scale: glyph-first
    controls, compact hit targets, no wide text-based tab buttons, and no
    decorative status dots that do not match the surrounding sidebar language
  - icon choices and active states follow the DiffsHub/AgentStudio sidebar
    grammar: quiet outline tree/comment/search/filter glyphs, a tiny
    icon-attached active indicator when needed, and no mixed-size glyph set or
    text-label control that makes the rail header look like a web form
  - a tiny active indicator on an icon button is allowed only when it follows
    the AgentStudio sidebar language; large status dots, wide badge pills, or
    decorative markers that compete with file rows are rejected
  - open filter menus use a raised dark popover, clear title/subtitle,
    separators, 24-32px rows, colored status badges, trailing selected
    checkmarks, disabled clear action, and keyboard/focus states
  - menu row layout uses a stable icon/status/checkmark grid so badges and
    checkmarks line up like the DiffsHub status menu; rows must not look like a
    text-only web menu or a native select replacement
  - menu items use checkbox-style semantics (`menuitemcheckbox`) unless an
    intentional product divergence is documented
  - the clear action is present as an explicit menu item and disabled when the
    all/default option is already selected
  - icon sizes, row height, padding, radii, and hover/selected states align with
    AgentStudio sidebar/menu styling
  - browser proof records the filter button box, popover width/height, row
    height, badge box, trailing checkmark box, separator spacing, and popover
    offset; the recorded values are compared against a captured DiffsHub
    reference crop before review. Target observations from the DiffsHub Node PR
    reference are ~16px icon/filter controls, ~32px popover menu rows, ~8px
    popover internal padding, ~10px popover radius, compact leading status
    badges, and trailing selected checkmarks. The latest browser lane measured
    menu rows at about 32px high with 6px/8px row padding, 14px text,
    checkbox-style `menuitemcheckbox` semantics, and 16px selected checkmarks
    aligned at the right edge; those are the explicit comparison targets.
  - browser proof also records menu semantics and interaction state:
    `menuitemcheckbox` or equivalent checked state for each status row,
    keyboard-reachable rows, disabled `Clear filter` when no filter is active,
    and a screenshot crop showing the open menu beside the rail header
  - Pierre owns Git status rendering in the FileTree via public `gitStatus`,
    density, search, selection, and model APIs. BridgeWeb may own the
    Git-status filter popover as local chrome because the current DeepWiki/local
    Pierre source pass did not identify a public DiffsHub filter-popover API,
    but the popover must feed the real FileTree/projection state and must not
    create a CSS-only filtered tree.
- Keep file-tree row density and icon discipline close to DiffsHub: compact
  stable rows, proportionate folder chevrons, consistent file-type badges,
  right-aligned status letters, and selected-row contrast that remains readable
  in dark mode. Row state must come from Pierre FileTree expansion, search, and
  selection state; a local CSS-only selected row or fake folder disclosure is a
  failed proof even when the screenshot looks close. Target observations from
  the DiffsHub Node PR reference are ~24px tree rows, a narrow ~12px right status
  column, compact row glyphs, small chevrons with `aria-expanded`, tiny folder
  change markers, and no oversized row padding. The latest browser lane
  measured tree rows at about 24px high with 13px text, 24px line-height,
  roughly 6px horizontal padding, pointer cursor, `user-select: none`, and a
  distinct selected-row state with `aria-selected="true"`.
- Preserve app-sidebar pointer behavior: file rows, folder disclosure controls,
  and CodeView file headers are controls, not selectable text. Browser proof
  must reject `cursor: text`, unexpected text selection, hidden selected rows,
  and any folder row whose disclosure paint is out of sync with
  `aria-expanded`.
- Configure Tree compact density, prepared/presorted input, stable ordering,
  and `fileTreeSearchMode: 'expand-matches'`. Start with Pierre
  `density: 'compact'`; if measured BridgeWeb rows are not close to the
  DiffsHub 24px target in browser and WKWebView, use Pierre's public
  `itemHeight`/style-variable controls to tune the row height and record the
  measured result.
- Use Pierre's public FileTree selection/reveal contract for row clicks:
  expand hidden ancestors through item handles before `scrollToPath`/focus,
  then drive CodeView item scrolling through the CodeView controller. A file
  click that only updates local selected CSS state is not sufficient.
- Configure CodeView through Pierre-owned item and layout APIs: item
  `collapsed` state plus version increments for header toggles,
  `renderHeaderPrefix`/`renderHeaderMetadata`/`renderCustomHeader` or the
  equivalent public header hook for the designed header, and CodeView `layout`
  options for internal padding/gaps rather than ad hoc CSS overrides.
- Added files must be represented as visible CodeView file content after
  content-handle hydration. Empty added-file placeholders are allowed only while
  content is explicitly pending.
- CodeView content hydration stays metadata-first: selected files hydrate on the
  hot path, and a bounded visible-window lane hydrates only the currently
  rendered CodeView items. Do not regress to either eager full-package content
  loading or selected-only hydration that leaves visible added files blank.
- Configure worker-backed CodeView highlighting through the Pierre React worker
  pool path. Worker-disabled fallback proof cannot satisfy the DiffsHub-class
  product row.

Proof:

- shadcn CLI setup proof records the exact commands used, generated file paths,
  and any documented fallback for unavailable Base UI primitives. For the
  installed shadcn CLI, the Base UI/Mira selection is represented by
  `style: "base-mira"` in `BridgeWeb/components.json`; do not add unsupported
  schema fields just to make the base explicit.
- `pnpm --dir BridgeWeb run typecheck` proves generated imports and any alias
  changes are valid.
- Component tests assert review chrome composes generated shadcn/Base UI
  primitives or Bridge wrappers over those primitives; bespoke standalone
  button/popover/menu/input implementations cannot satisfy this row.
- Theme proof records AgentStudio/Pierre token mapping and shows the
  resulting rail/popover/search/tree/canvas colors in browser and native
  screenshots.
- Unit/browser tests assert no native `select`.
- Browser tests assert search expands matches, filters update tree, hunk
  expansion works, added-file content is visible after hydration, row click
  scrolls CodeView, and custom headers exist.
- Browser tests assert a mounted file header toggles `collapsed` state without
  exposing a text cursor or selecting header text.
- Screenshot compares repaired chrome against the target grammar, including an
  open Git-status filter popover, an open/active search affordance, selected
  rail row, and a tree crop showing row icons/status alignment.
- Native nonblank proof is not visual-parity proof. The visual proof packet must
  explicitly separate:
  - smoke/native render unblocked
  - large fixture loaded
  - rail toolbar/search/filter chrome matches the compact DiffsHub/AgentStudio
    grammar
  - file tree rows and disclosure controls are compact and interactive
  - file click scrolls CodeView to the selected item
  Sidecar findings may inform this checklist, but screenshots and tests from
  the main execution loop are the gate.
- Visual comparison must be explicit, not impressionistic: attach the DiffsHub
  Node PR reference crop and the BridgeWeb crop, then list pass/fail deltas for
  toolbar icon scale, filter popover width/offset, menu row height, status badge
  box, selected checkmark alignment, tree row height, disclosure chevrons,
  selected row contrast, and file-click-to-CodeView-scroll behavior.
- DiffsHub reference captures used for pass/fail comparison must live inside
  the same repo-local proof packet as the BridgeWeb captures, for example
  `tmp/bridge-viewer-visual-proof/<timestamp>/diffshub-reference-*.png`.
  Machine-global `/tmp/diffshub_*.png` screenshots are scratch only and cannot
  be authoritative proof. The proof packet must record the source URL, theme
  setting, viewport, capture time, and file paths for every reference crop.
- Browser proof records bounding boxes for search/filter buttons, popover size,
  menu row height, badge/checkmark geometry, separator spacing, menu roles, item
  count, row cursor/user-select style, selected-row `aria-selected`, folder
  `aria-expanded`, search result row-count delta, and `Clear filter` presence.
  The artifact must include freshly captured DiffsHub reference screenshots in
  that same repo-local proof packet. Stale external screenshots may inform
  diagnosis but cannot satisfy the visual-parity row.

### Task 6: Worker-Backed Rendering Proof

Write surfaces:

- `BridgeWeb/src/review-viewer/workers/pierre/*`
- `BridgeWeb/src/review-viewer/workers/markdown/*`
- `BridgeWeb/src/review-viewer/markdown/*`
- `BridgeWeb/tsdown.config.ts`
- asset audit scripts if packaging changes.

Implementation:

- Keep CodeView syntax highlighting in Pierre worker pool.
- Keep markdown rendering in the markdown worker lane.
- No main-thread Shiki/markdown fallback for product proof.
- Record worker-mode flags in performance rows.
- Preserve markdown security while touching dev harness, worker, or preview
  code:
  - DOMPurify sink remains in the preview component.
  - Links and media remain inert.
  - Unsafe `href`, `src`, `srcset`, `file:`, `data:`, `javascript:`, remote,
    and `agentstudio://` attributes are stripped.
  - `parseBridgeContentResourceUrl` validation is required before markdown
    preview content is fetched/rendered.
- Helper worker probes are allowed for diagnosis, but they do not satisfy
  product worker proof. Product proof requires one Browser Mode integration
  test and one benchmark row to use the default packaged worker path, or an
  explicit split if Browser Mode cannot support that product path.

Proof:

- Worker-backed Browser Mode integration renders visible CodeView.
- Worker-backed performance row has `codeViewWorkerPoolEnabled: true`.
- Build/audit proves worker assets are packaged.
- Build/audit proves packaged app assets reject external runtime imports while
  allowing intentional local Catppuccin Mocha theme metadata and preserving
  explicit Shiki core/engine/language loading for syntax highlighting.
- Markdown sanitizer/render-mode tests remain green.
- Browser markdown scenario asserts sanitized preview has no active link,
  image, media, or unsafe resource attributes.

### Task 7: Durable Browser Performance Artifact And Verifier

Write surfaces:

- `BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx`
- `BridgeWeb/scripts/bridge-viewer-browser-benchmark-runner.ts`
- `BridgeWeb/scripts/bridge-viewer-browser-benchmark-runner.unit.test.ts`
- `BridgeWeb/package.json`

Implementation:

- Persist or capture structured benchmark rows.
- Add verifier that fails on missing scenarios, missing fixture metadata,
  missing worker flags, missing correctness assertions, invalid samples, p95
  over budget, or percentile drift.
- Store artifacts under `tmp/bridge-viewer-browser-benchmark/` by default, not
  under `BridgeWeb/src`.
- Preserve the current browser benchmark runner's `requiredScenarioIds` as the
  minimum PR-readiness floor. At the time of this plan, that includes:
  `cold-package-push`, `warm-tree-select`, `warm-added-file`,
  `warm-hunk-expand`, `warm-search-expand-matches`, `warm-filter-switch`,
  `warm-projection-chip-switch`, `medium-streaming-append-delta`,
  `large-cold-package-push`, `worker-backed-cold-package-push`,
  `warm-markdown-preview`, `failure-content-unavailable`,
  `stale-generation-drop`, and `scroll-ownership`.
- Add large-specific selection/scroll scenario rows required by Tasks 3 and 4.
  These may be new scenario ids or explicit large-fixture variants, but the
  artifact must clearly show `fixtureClass: 'large-diffshub'`.
- The mandatory floor must include large-fixture semantic select, large
  CodeView scroll ownership, and large rail scroll ownership rows, for example
  `large-semantic-select`, `large-scroll-ownership`, and
  `large-rail-scroll`. Renaming is allowed only if the verifier still proves
  those three capabilities by fixture class and correctness ledger.
- Large projection, search, reveal, select, and filter benchmark rows must
  record whether the projection work ran on the worker lane. A synchronous
  product-runtime fallback is a failing PR-readiness signal unless the scenario
  is explicitly a tiny-fixture/unit-only case.
- If any existing required scenario is intentionally removed, the plan must be
  revised again with the removal named, justified, and covered by compensating
  proof. Do not silently shrink the scenario contract.

Proof:

- `pnpm --dir BridgeWeb run test:benchmark:browser` passes and writes/prints
  structured rows.
- Verifier passes against the artifact.
- Runner unit tests pin the full required scenario contract and fail if rows
  are missing, fixture class/delivery/worker modes drift, content URLs escape
  the Bridge resource lane, or reported percentiles do not match raw samples.
- Artifact includes `medium-streaming-append-delta`, `stale-generation-drop`,
  `warm-markdown-preview`, and `failure-content-unavailable` rows.
- Artifact includes one Node-PR-class stage row for
  `large/browser/huge-diff.ts` or a documented Node-equivalent generated path,
  including per-stage timings for reveal/search, click/select, content fetch,
  CodeView update, and scroll.
- Browser benchmark artifacts are still lower-layer proof. They must not be
  treated as a substitute for the native real-worktree stage timings required
  by Task 8.

### Task 8: Native AgentStudio Debug Proof

Write surfaces:

- Generated BridgeWeb app assets.
- `tmp/bridge-viewer-visual-proof/<timestamp>/`
- Swift IPC diagnostics only if current diagnostics cannot prove state.
- Focused Bridge IPC service/contract files if semantic control is missing.

Implementation:

- Build packaged assets.
- Add or finish semantic IPC control before native large-performance proof. The
  required product namespaces are:
  - `bridge.review.*` for load/refresh/package/mode/facet/select/reveal/scroll/collapse review
    item actions
  - `bridge.fileTree.*` for search, facets, reveal, and tree state
  - `bridge.fileView.*` for source/markdown render-mode requests
  - `bridge.telemetry.*` for debug snapshot/flush of Bridge/Pierre telemetry
- Required command groups before native repeatable proof are at least:
  `bridge.review.load`, `bridge.review.refresh`, `bridge.review.getPackage`,
  `bridge.review.setMode`, `bridge.review.setFacets`,
  `bridge.review.selectFile`, `bridge.review.revealFile`,
  `bridge.review.scrollToFile`, `bridge.review.prepareWindow`,
  `bridge.review.expandFile`, `bridge.review.collapseFile`,
  `bridge.fileTree.search`, `bridge.fileTree.setFacets`,
  `bridge.fileTree.revealPath`, `bridge.fileView.setRenderMode`,
  `bridge.telemetry.snapshot`, and `bridge.telemetry.flush`. Exact names may be
  refined only by updating the specs and tests first. Native proof must cover
  these semantic capabilities without command palette UI, raw WebKit
  evaluation, event-bus command routing, or IPC-returned hot bodies.
- IPC must route through AgentStudio IPC target resolution to a Bridge pane or
  Bridge capability port. It must not open command palette UI, publish
  command-events on the event bus, expose raw WebKit evaluation, or bypass
  Bridge content-handle validation.
- Launch the debug app through existing debug/observability runner.
- Open the real large Bridge worktree/package path by default, including the
  current required fixture at
  `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
  on branch `luna-338-pierreshikitrees-review-viewer`. A deterministic native
  substitute is allowed only as additional evidence and only if it uses
  packaged assets plus the normal Bridge package push/content/custom-scheme
  path; a dev/mock fixture pane cannot be the sole product proof.
- Capture render state, package state, scroll/selection diagnostics, and visual
  screenshots.
- The AgentStudio debug proof is the outer loop for this plan. It must run
  after Vite/browser proof is green and must not use the Vite dev server as its
  renderer.
- Treat markdown as an active native-path blocker until this real debug pane
  proves markdown preview rendering through the packaged/manual Bridge path.
  Browser markdown tests, mocked markdown fixtures, and small-smoke screenshots
  are required lower layers, but they do not close this acceptance gate.
- If the current native proof uses the real large worktree instead of the
  mocked fixture, record its item count, visible/hidden counts, additions,
  deletions, and any omitted optional-path edge cases so the browser fixture and
  native proof can be compared without pretending they are identical.
- Record stage timings for the real package/worktree path: package push, tree
  render/search/reveal, file select, CodeView hydration/render, markdown
  render, and scroll responsiveness. Slow stages are product findings, not
  proof-runner noise to hide behind larger timeouts.
- Use Victoria Stack as the source of truth for native performance proof. JSON
  artifacts and screenshots are useful sidecars, but the pass/fail evidence for
  performance must include Victoria-backed logs, metrics, or traces correlated
  to the IPC-driven stages.

Proof:

- IPC integration tests show Bridge-scoped commands can load/refresh a package,
  select/reveal a file, search/filter the tree, fetch content, request markdown
  preview, and capture telemetry without command palette UI or raw WebKit
  evaluation.
- IPC render state reports app root and review shell present, page errors zero.
- Package state reports large item counts and expected fixture/worktree data.
- Screenshots show large viewer, scrolled CodeView, scrolled rail, filter/search
  state, added-file content, markdown preview, and failure/unavailable UI.
- Scroll/selection diagnostics and scripted native interaction geometry proof
  show file selection changes visible content and both scroll owners move
  independently. IPC diagnostics alone are not enough for this row: the native
  proof must record header-top offsets before/after file selection and
  collapse/expand, with screenshot or measured geometry attached.
- Stage artifact for `agent-studio.bridge-start` on
  `luna-338-pierreshikitrees-review-viewer` records package push, tree
  render/search/reveal, file select, CodeView hydration/render, markdown
  render, and scroll responsiveness timings.
- IPC/package-state evidence plus `agentstudio://resource/content/...` activity
  proves the native pane used the real Bridge content path, not only a mock
  fixture banner.
- Victoria query artifacts prove the same run emitted debug-scoped Bridge/Pierre
  telemetry for the measured stages and worker/markdown lanes.

### Task 9: Review And PR Readiness

Run implementation review after code proof:

- `shravan-dev-workflow:implementation-review-swarm`

Then PR wrapup:

- `shravan-dev-workflow:implementation-pr-wrapup`

Required gates:

```bash
pnpm --dir BridgeWeb run typecheck
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run test:browser
pnpm --dir BridgeWeb run test:benchmark:browser
pnpm --dir BridgeWeb run build
pnpm --dir BridgeWeb run check
mise run bridge-viewer-benchmark
mise run lint
mise run test -- --filter Bridge
git diff --check
```

If Swift IPC/debug runtime is touched:

```bash
mise run test -- --filter AgentStudioIPCBridgeServiceTests
```

If broad app behavior is touched:

```bash
mise run test
```

## Split/Replan Triggers

- Packaged Pierre worker cannot load in Browser Mode with current dependency
  graph.
- Markdown worker cannot satisfy asset self-containment audit.
- Browser performance is too noisy to enforce budgets without a runner change.
- Native debug app cannot capture screenshots after browser proof is green.
- Large fixture reveals a Bridge package/content model mismatch rather than a
  frontend UX issue.

## Rollback And Recovery

- Dev harness is isolated behind dev bootstrap and query params; revert it
  without changing packaged Bridge runtime.
- Fixture/test-support changes can be reverted independently from product UX.
- Header/chrome changes are BridgeWeb-local.
- Generated BridgeWeb assets should be regenerated from source, not edited by
  hand.

## Historical Partial Checkpoint: 2026-06-19 Dev-Server Proof

This checkpoint records useful evidence from an earlier browser-loop pass, but
it is not accepted DiffsHub-class proof after the 2026-06-19 reset. Treat these
values as regression context only. The current gate is the proof matrix above:
real-worktree dev-server behavior, DiffsHub side-by-side visual comparison,
geometry assertions, markdown rendering, added-file full content, no-jump
collapse, file-click-to-top alignment, and shadcn/Catppuccin visual parity.

Historical commands from that partial checkpoint:

```bash
pnpm --dir BridgeWeb run fmt
pnpm --dir BridgeWeb exec tsc --noEmit --pretty false
pnpm --dir BridgeWeb exec vitest run src/review-viewer/chrome/bridge-review-chrome.unit.test.tsx src/review-viewer/shell/review-viewer-shell.integration.test.tsx src/review-viewer/code-view/bridge-code-view-panel-scroll.unit.test.tsx
pnpm --dir BridgeWeb run test:dev-server
pnpm --dir BridgeWeb run test:dev-server:worktree
pnpm --dir BridgeWeb run proof:visual:dev-server
```

Observed historical proof values:

- Large fixture: `codeViewScrollHeight = 1153975`,
  `codeViewScrollTop = 1000143`, worker pool ready, markdown fixture reachable,
  selected file `Sources/BridgeViewer/NewPanel.ts` in the synthetic
  `large-diffshub` fixture only.
- Real worktree fixture: selected `.github/workflows/ci.yml`, loaded `19721`
  characters and `557` lines, worker pool ready, package handle text remains
  scrubbed.
- Visual artifacts:
  `tmp/bridge-viewer-visual-proof/2026-06-19T17-00-07-679Z-dev-server`.

Still not accepted by the DiffsHub-class visual gate:

- Any top review scope strip remains failed evidence unless it is removed or
  rebuilt as compact integrated shadcn/Base UI chrome on the same
  AgentStudio/Pierre Mocha surface. The preferred placement for review-mode
  controls is the right rail or same-plane app chrome, not a detached strip.
- Main CodeView file sections need clearer DiffsHub-like boundaries, sticky
  behavior, and collapse/expand affordances.
- CodeView file headers must not stack redundant icons. The accepted header
  grammar is collapse affordance plus Pierre-owned file icon/path; do not add a
  Bridge status badge or extra Bridge file-kind icon before the path.
- File-click selection must quickly align the target file header to the top or
  sticky threshold of the scroll viewport, like DiffsHub. It must not smooth
  scroll for long enough to race hydration, snap back, drift, or jump when the
  selected file is collapsed or expanded.
- Large fixture tree-click behavior must be consistent for all visible file
  rows. Clicking a file row must resolve to a review item, update selected
  content state, and scroll the corresponding CodeView header into the viewport.
- Fixture-specific path checks must resolve a target from the active fixture or
  real worktree DOM. `Sources/BridgeViewer/NewPanel.ts` belongs to the
  synthetic large DiffsHub fixture, not the real-worktree fixture, and must not
  appear in real-worktree proof as a hardcoded expectation.
- The browser proof must continue to check added-file full content, markdown
  rendering, right-rail compact controls, and filter/search behavior before new
  Swift IPC expansion becomes the critical path.

Parallel IPC checkpoint:

- Existing-handle Bridge IPC methods now have focused proof for Bridge-pane
  target canonicalization and typed `unsupported target` errors for non-Bridge
  panes.
- `bridge.review.load` remains app/layout-scoped because it opens/loads Bridge
  review state without an existing pane handle.
- Focused IPC proof currently green:

```bash
swift test --filter AgentStudioIPCBridgeServiceTests
swift test --filter AgentStudioIPCRegistryAuthorizationTests
swift test --filter AgentStudioIPCClientCoreTests
```

## Next Workflow

Run `shravan-dev-workflow:plan-review-swarm` against this reset, then execute
with `shravan-dev-workflow:implementation-execute-plan` only after accepted
plan-review findings are addressed. Current reset state lives under
`tmp/workflow-state/2026-06-19-bridgeweb-diffshub-shadcn-reset/`.
