# Agent Studio Marketing Site

This directory owns the public Agent Studio marketing site and the README's product images. The repository-root `AGENTS.md` still applies; this file narrows frontend decisions for `web/`.

## Governing design

Read these before changing the website's structure, behavior, or stack:

- [Requirements](../docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-requirements.md)
- [Specification](../docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-specification.md)
- [Program Design](../docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-program-design.md)
- [Visual Design](../docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-visual-design.md)
- [Static Design Board](../docs/specs/2026-08-17-marketing-site/website-design-board.html)
- [Mandatory visual verification SOP](../docs/wip/2026-08-20-website-visual-verification-sop.md)

The current product README, semantic app theme, and canonical icon own product claims and brand evidence. Files under `web/images/` remain README/reference assets. Website product imagery comes from the approved WebsiteCaptureSuite. Herdr is prior art for hierarchy and a clickable product plate, not a source for Agent Studio copy, colors, fixtures, or accessibility behavior.

## Marketing copy

For marketing copy, titles, descriptions, CTAs, and other reader-facing prose, read and use `.agents/skills/ai-copywriter/SKILL.md`. The local skill copy is pinned to reviewed upstream commit `08b53b1ad39887cd94cbaab61cac3b6aae2d8518`.

Every subagent, advisor, or reviewer that writes, changes, or judges
reader-facing copy must read that complete project-local skill before its work
and record the coverage in its receipt. A copy verdict without that coverage is
not accepted.

The current Agent Studio README and the governing website specifications remain authoritative for shipped capabilities, terminology, install facts, metrics, limitations, and product evidence. The skill may improve framing, voice, and variants, but it must preserve those facts exactly and must not invent claims, anecdotes, proof, quotes, numbers, or SEO language. Ask for missing audience, reader-moment, story, or voice evidence instead of guessing. Repository instructions override the skill, approved house style overrides its mechanical humanizer rules, and its file mode may rewrite a file only when the user has explicitly authorized that edit.

## Technology boundary

- Astro owns page composition, static HTML, metadata, and the default component boundary.
- All authored application logic and executable JavaScript/TypeScript toolchain configuration is TypeScript. Do not add `.js`, `.jsx`, or `.mjs` application/configuration source files. Declarative JSON/YAML manifests, lockfiles, structured data, CSS, and CI/deployment workflows remain allowed.
- Tailwind CSS v4 owns general responsive layout and utility composition. Semantic CSS owns brand tokens, product-plate geometry, and campaign-specific visual behavior.
- The first release builds static output for Cloudflare Pages. Do not add `@astrojs/cloudflare`, `@cloudflare/vite-plugin`, a Worker entry point, server rendering, bindings, or runtime APIs without revised governing requirements and design.
- `BridgeWeb/` is an adjacent toolchain reference, not a website runtime dependency. Do not import Bridge transport, native app state, workers, telemetry, generated resources, or product controllers into `web/`.

## Astro and React

React is allowed. Hydration is the boundary that must be justified, not the mere presence of a React component.

### Static rendering

- Prefer `.astro` components for static page structure, content, images, video wrappers, navigation, and proof sections.
- A React component used without a `client:*` directive renders to static HTML at build time and ships no React runtime to the browser. This is acceptable when reuse or component clarity is materially better than an Astro equivalent.
- Do not rewrite a clear existing React component into imperative DOM code merely to claim that the site is React-free.

### Client interaction

- Use a small TypeScript controller when behavior is one bounded state owner over pre-rendered DOM, such as selecting one of a closed set of product-demo panels or copying the install command.
- Do not build a custom component framework, synthetic lifecycle, generalized store, virtual DOM, event bus, or synchronization layer to avoid React.
- Use a hydrated React island when the interaction has nested independently stateful controls, substantial conditional composition, asynchronous data, shared client state, or a component tree whose state transitions and tests are materially clearer in React.
- Hydrate the smallest owning island. Keep surrounding page content in Astro.
- Prefer `client:visible`, `client:idle`, or a justified `client:media` boundary. Use `client:load` only when interaction is required immediately in the first viewport.
- Do not use `client:only` for primary marketing content. Server-rendered or build-rendered HTML must remain useful before hydration.
- Never mount one page-wide React root merely for consistency.

### Decision test

Before adding or refusing React, answer:

1. Who owns the client state?
2. Can the complete initial state be rendered as useful HTML?
3. Is the behavior a closed state switch over existing DOM, or does it create and coordinate a real component tree?
4. Does a TypeScript controller remain smaller and clearer than React after keyboard, accessibility, cleanup, and tests are included?
5. What exact `client:*` boundary is required, and what works before it hydrates?

If the answers do not make one direction clear, return to the Program Design rather than improvising a new frontend architecture.

## Interactive product plate

- The initial plate is an Astro-rendered fixture enhanced by one TypeScript controller.
- Each state displays a frozen purpose-made Agent Studio capture. Do not reconstruct, redraw, or approximate app UI in HTML/CSS.
- Its approved states are Parallel work, Pane drawer, Quick Find, Review, and Persistent workspace.
- Quick Find is the approved navigation state; do not add a duplicate repository-navigation state without a Specification change.
- State changes are local and deterministic. They do not navigate, change the URL, persist state, call a backend, access local files, or connect to Agent Studio.
- Use semantic buttons/tabs and panels with visible focus, keyboard operation, `aria-selected`, and explicit control/panel relationships. Do not copy Herdr's pointer-only `div` and `span` controls.
- Before the controller validates and activates, expose only Parallel work; keep selectors disabled, outside the focus order, and free of live tablist/tab semantics. Validate the complete state/control/panel correspondence before any DOM mutation, then synchronously enable listeners, tab relationships, and roving focus without moving focus. Initialization failure restores the disabled static contract.
- Exactly one selector and one panel are current at a time. Unknown state identifiers preserve the last valid state.
- Ambient timers and status activity are illustrative presentation only. Stop them while hidden and when reduced motion is requested.
- If controller complexity crosses the React threshold above, migrate this one boundary to a React island; do not add a parallel controller path.
- Persistent workspace must present Before close and Restored evidence at a
  readable scale and fill the product plate without a dead region. Do not
  preserve a static split when it makes both images small or leaves the lower
  half empty. The replacement presentation pattern requires owner-approved
  design before implementation; do not add autoplay or simulated restoration.

## Product proof

The page uses two complementary proof surfaces:

1. recognizable Agent Studio imagery in the hero, replaced by the approved
   silent website loop when that shared launch asset is ready;
2. one clickable product plate that owns the complete Parallel work, Pane
   drawer, Quick Find, Review, and Persistent terminal sessions explanation.

Do not repeat those five stories in long-form sections below the plate. After
the clickable explainer, proceed directly to the final install call to action.
Product footage and screenshots must remain readable rather than becoming
tilted decoration.

Preserve the existing `web/images/` paths because the root README references them directly. Do not use them as final website imagery or move/rename them without updating and verifying every README consumer.

## Capture suite

- Capture every website product image from one fresh dedicated debug Agent Studio build, isolated data root, and deterministic fixture workspace.
- Use one 1280×800-point window captured at 2× scale as 2560×1600 sRGB PNG masters.
- Keep every campaign state to two or three readable primary panes. Four narrow
  panes and large empty pane fields fail the campaign-image contract.
- Freeze sidebar width, toolbar/window chrome, theme, typography, pane density, fixture repositories/worktrees, terminal content, and capture method across the suite.
- Required masters: `parallel-work.png`, `pane-drawer.png`, `quick-find.png`, `review.png`, `persistent-before.png`, and `persistent-restored.png`.
- Use a Luna xhigh operator only with an exact capture packet. Verify build, executable, bundle identifier, PID, isolated data root, and window identity before any UI action. Never attach to an existing app process.
- The operator uses Sky only after loading `computer-use:computer-use` and targeting the dedicated bundle identifier. Peekaboo may provide control fallback with a fresh snapshot and the same PID/window boundary.
- Use Peekaboo to resolve the current CoreGraphics window ID from the verified PID, then capture that window ID with Retina PNG output. Never rely on the generic AX window title as the sole selector. Preserve the untouched source and record its embedded ICC profile/hash; convert a copy through ColorSync to the canonical sRGB IEC61966-2.1 master without resizing.
- Exclude cursor, desktop background, notifications, personal paths, credentials, unrelated apps, random shell history, and unstable activity.
- Record build revision, fixture identity, process generation, PID-to-window-ID binding, capture dimensions, scale, source and normalization profiles, window geometry, source state, and source/master SHA-256 values for every shot.
- Generate focus-isolation stills through the shared HyperFrames composition: one untouched master plus four uniform scrim segments around the approved rectangular focal region. Keep one scrim/edge treatment across the campaign and change only the recorded region. Never duplicate, filter, blur, recolor, regenerate, rewrite, or reconstruct app pixels.
- Generate responsive and long-form crops from approved masters or HyperFrames emphasis outputs. Never recapture a different window geometry for mobile or section variants.

## TypeScript and state

- Use strict, explicit types and discriminated unions for UI state variants.
- Keep fixture data immutable and separate from the controller that interprets it.
- Derive selected presentation from one authoritative state. Do not synchronize duplicate selected-workspace, selected-tab, and selected-agent stores.
- Validate DOM lookup and fixture identifiers at the boundary. An invalid selection must not produce mismatched controls and panels.
- Client state is transient. Do not add local storage, cookies, URL state, or cross-session persistence without a specification change.
- Clean up listeners, observers, timers, and media reactions through one owning lifecycle.

## Styling system

- Project current Agent Studio semantic tokens into website-owned CSS variables with source comments or tests. Do not import the entire BridgeWeb product stylesheet.
- Publish from one checked-in typed product-source projection. It records owner paths, last-verified revisions or hashes, approved brand copies, screenshot identities, and immutable video provenance. Build and preview render from that projection; verification compares it with current owners but never rewrites or silently adopts owner changes.
- Treat README claims/install facts, AppStyles and named BridgeWeb semantic roles, `AppIcon.svg`, approved web icon/logo copies, `web/images/`, and the immutable promotional-video reference as distinct owner classes. A mismatch blocks promotion while leaving the last-verified projection and preceding deployment unchanged.
- `#409CFF` denotes current, focused, selected, or interactive state.
- `#EF9F76` denotes parallel, related, or background work.
- `#74C7EC` is a scarce logo or glyph detail.
- Use Tailwind v4 `@theme` for tokens that should create utilities and `:root` variables for semantic values that should not.
- Derive marketing geometry from the canonical icon's softened overlapping
  planes. Use a restrained radius system for the shell, product frame, and
  controls; do not turn the page into rounded-card or pill UI. Preserve native
  macOS geometry inside captured product UI.
- Avoid generic gradient text, floating blobs, glass-card grids, pill-heavy chrome, and decorative 3D unrelated to organized parallelism.

## Accessibility and motion

- The static page, default product screen, installation command, and primary actions must work before client enhancement.
- Follow the WAI-ARIA tabs pattern when the selector behaves as tabs, including arrow keys, Home/End, activation semantics, and roving focus.
- Color is never the only selection, status, or focus signal.
- Respect `prefers-reduced-motion` in CSS, TypeScript, timers, observers, and media. Reduced motion shows the hero poster first and does not autoplay video.
- Video playback remains controllable. Media failure preserves the poster and surrounding explanation.
- Maintain WCAG AA contrast for rendered text and controls.

## Verification boundary

Follow the mandatory visual verification SOP for every website styling,
product-image, responsive-layout, or deployment change. Verification must open
all five product states locally and on the deployed site; the default state
never proves the suite.

Website work is incomplete until the changed scope has evidence for:

- Astro and strict TypeScript checking;
- formatting and linting with the repository's Oxlint/Oxfmt conventions;
- static production build output;
- interactive-demo state and invalid-state behavior;
- keyboard and accessibility semantics;
- reduced-motion and media failure behavior;
- desktop and narrow-screen visual proof;
- unchanged README image references;
- Cloudflare preview deployment when deployment configuration is in scope.

Tests, mocks, or a successful static build do not replace browser interaction and visual proof for the product surface.
