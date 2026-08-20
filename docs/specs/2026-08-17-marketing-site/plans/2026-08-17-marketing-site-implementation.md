# Agent Studio Marketing Site Implementation Plan

## Canonical plan record

```text
plan path: docs/specs/2026-08-17-marketing-site/plans/2026-08-17-marketing-site-implementation.md
originating planner: plan-implementation
planning result: ready
governing planning basis:
  kind: reviewed-three-artifact-design
  Requirements: docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-requirements.md
  Specification: docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-specification.md
  Program Design: docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-program-design.md
  review result: Cursor Grok 4.6 High session 74150, mode-complete three-artifact result needs-revision
  focused review result: Cursor Grok 4.6 High session 30bde178-b648-4eaf-ae12-6c0e4a3abb9f, two findings ready-for-remediation
  parent-verified remediation: current Specification, Program Design, and web/AGENTS.md anchors covering pre-enhancement operability, verified product projections, TypeScript config scope, page-local chrome, screenshot count, and persistence composition
  current applicability: website-marketing at 8fd35de2c7df7f3f7841e81ecdb577ebb09a7f9a plus the uncommitted governing artifacts at this plan path
delivery context:
  requested terminal: plan-only
  delivery grouping: single:marketing-site
  PR topology: not-applicable
```

## Goal

Deliver the first Agent Studio marketing homepage as a TypeScript-first Astro static site deployed to Cloudflare Pages. The page must communicate organized parallelism through a claim-first hero, real product video/poster, a progressively enhanced clickable workspace, four screenshot-backed proof sections, and current install/GitHub actions.

## Scope

- Create one independent Astro project rooted at `web/` without moving or renaming the existing README-only `web/images/` files.
- Produce one six-master WebsiteCaptureSuite from a dedicated debug Agent Studio fixture before product imagery is integrated.
- Reuse the repository's Node 26.5, pnpm 11.14, strict TypeScript, Oxlint, Oxfmt, Vitest, and browser-proof conventions where they fit Astro.
- Add Tailwind CSS v4 through its current Vite integration; keep product-plate and brand-specific styles in semantic CSS.
- Add one checked-in `VerifiedProductProjection` and a verification boundary for current product sources.
- Build the hero, install actions, video/poster behavior, interactive workspace, four screenshot sections, and page-local chrome.
- Add local quality/test/build tasks, aggregate test integration, CI validation, and Cloudflare Pages preview/production delivery.
- Capture production-equivalent browser and deployment evidence for the obligations named below.

## Non-goals

- No native Agent Studio, BridgeWeb runtime, Bridge protocol, persistence, release packaging, or app behavior changes.
- No React dependency in the initial site.
- No server rendering, Cloudflare adapter, direct Cloudflare Vite plugin, Worker entry point, bindings, API, authentication, analytics, storage, personalization, or website persistence.
- No documentation migration, blog, changelog, or new multi-page information architecture.
- No automatic adoption of current README, token, icon, screenshot, or media values into published marketing output.
- No large video binary committed to Git.

## Current repository evidence

- `web/` contains only `AGENTS.md` plus four README PNGs; there is no existing website runtime or package.
- `README.md` owns shipped claims, Homebrew instructions, planned-versus-shipped boundaries, and all four current image paths.
- `BridgeWeb/package.json`, `BridgeWeb/tsconfig.json`, `.oxlintrc.json`, `.oxfmtrc.json`, and browser test configuration establish the adjacent frontend conventions.
- `.mise.toml` owns root task composition; `[tasks.test]` currently runs Swift, architecture, BridgeWeb, and diff gates.
- `.github/workflows/ci.yml` owns pull-request validation and has no website lane.
- `.gitignore` already covers `tmp/` and `node_modules/`; it needs website-specific generated output coverage.
- `AppStyles.swift`, `bridge-app.css`, `AppIcon.svg`, `AppLogoTransparent.svg`, the dedicated WebsiteCaptureSuite, and the approved external video identity are the named current owners consumed by verification, not by production rendering. Existing `web/images/` remain README/reference assets only.

## Fixed implementation decisions

- Astro owns static page composition and produces `web/dist/`.
- `astro.config.ts` uses static output and `@tailwindcss/vite`; no Cloudflare or React integration is installed.
- Website application source and executable JavaScript/TypeScript configuration use `.ts`, `.tsx` only if React is later authorized, and `.astro`; no `.js`, `.jsx`, or `.mjs` source.
- JSON/YAML manifests, lockfiles, CSS, and workflows remain valid declarative formats.
- Production page content consumes only checked-in projections.
- Product-source verification compares projections with owners and blocks promotion on mismatch; it never rewrites projections.
- The unenhanced demo exposes only Parallel work. Selector buttons are disabled, outside the focus order, and have no live tab semantics until complete validation succeeds.
- Controller activation is one synchronous transition after validation; it preserves focus and restores the disabled static contract on failure.
- Persistence is a single static split panel containing labeled Before close and Restored frames.
- The screenshot narrative has exactly four sections, one per existing README image. Persistence remains plate/video proof.
- Navigation/Footer are page-local chrome only: identity, in-page anchors, install, and GitHub. They introduce no routes.
- Cloudflare Pages serves static output. Production branch is `main`; the initial Pages project name is `agentstudio`, subject only to provider availability. A later custom domain changes configuration/metadata, not architecture.

## Planned website structure

```text
web/
├── AGENTS.md
├── package.json
├── pnpm-lock.yaml
├── astro.config.ts
├── tsconfig.json
├── .oxlintrc.json
├── .oxfmtrc.json
├── vitest.config.ts
├── playwright.config.ts
├── scripts/
│   └── verify-product-sources.ts
├── src/
│   ├── pages/index.astro
│   ├── layouts/SiteShell.astro
│   ├── components/
│   │   ├── Hero.astro
│   │   ├── InstallActions.astro
│   │   ├── ProductVideo.astro
│   │   ├── InteractiveWorkspaceDemo.astro
│   │   ├── ScreenshotProofSection.astro
│   │   └── FinalInstallCallToAction.astro
│   ├── content/
│   │   ├── product-source-projection.ts
│   │   ├── product-copy.ts
│   │   ├── demo-fixture.ts
│   │   └── website-capture-manifest.ts
│   ├── demo/
│   │   ├── demo-state.ts
│   │   └── demo-controller.ts
│   ├── styles/
│   │   ├── tokens.css
│   │   ├── global.css
│   │   └── product-plate.css
│   └── assets/
│       ├── brand/
│       │   ├── app-icon.svg
│       │   └── app-logo-transparent.svg
│       └── captures/
│           ├── parallel-work.png
│           ├── pane-drawer.png
│           ├── quick-find.png
│           ├── review.png
│           ├── persistent-before.png
│           └── persistent-restored.png
├── tests/
│   ├── product-source-projection.test.ts
│   ├── demo-controller.test.ts
│   └── website.browser.test.ts
└── images/
    └── existing four README PNGs remain in place
```

The exact co-location of small unit tests may follow established Astro/Vitest convention without changing ownership or proof.

## Obligation and proof inventory

| Obligations | Owning change | Observable proof | False-green risk |
| --- | --- | --- | --- |
| R1, R10, R12 | Astro/tooling foundation | Static `dist/`, Astro check, strict TS, built HTML with client module blocked | Build passes while primary content depends on JS |
| R14, U8 | VerifiedProductProjection | Owner mismatch, missing asset, and stale video identity all fail promotion without rewriting projection | Verifier checks only manifest shape or current HEAD is adopted silently |
| R2, R8, R9 | SiteShell, Hero, InstallActions, brand projection | First viewport, exact install/GitHub actions, current brand sources | Attractive hero with wrong command or obsolete claim |
| R3, R4 | ProductVideo and page composition | Real poster/video, autoplay/reduced-motion/offscreen/error behavior | Poster exists but source is absent; autoplay proof ignores reduced motion |
| R5, R6 | Fixture, static plate, DemoController | JS-disabled/delayed/failing init, keyboard semantics, five valid states, invalid state | Enhanced tests pass while pre-enhancement controls pretend operable |
| R7 | ProductProofStory | Four exact assets, intrinsic/responsive rendering, alt text, README references unchanged | New copies render while README paths silently break |
| R11 | All UI owners | Browser accessibility plus desktop/mobile visual evidence | Automated DOM assertions miss unreadable crops or focus appearance |
| R13 | CI and Cloudflare Pages | PR preview URL, `main` production deployment, rollback visibility | Local build is mistaken for Cloudflare runtime proof |

## Slice graph

```text
S1 Website foundation
  ──► S2 Visual design board and capture contract
        ──► S3 Dedicated debug capture suite
              ──► S4 Verified product projection
                    ──► S5 Static shell, hero, install, and media
                          ──► S6 Interactive image plate
                                ──► S7 Screenshot story and responsive composition
                                      ──► S8 Repository integration and Cloudflare delivery
```

These edges are required. Each downstream slice consumes markup, tokens, content, or proof seams established by the preceding slice. No parallel implementation lane is planned because the slices converge repeatedly on `index.astro`, semantic styles, fixture content, and browser proof.

## S1 — Establish the Astro and quality foundation

Obligations: R1, R10, R12; U6.

Write surfaces:

- `web/package.json`, `web/pnpm-lock.yaml`
- `web/astro.config.ts`, `web/tsconfig.json`
- `web/.oxlintrc.json`, `web/.oxfmtrc.json`
- `web/vitest.config.ts`, `web/playwright.config.ts`
- minimal `web/src/pages/index.astro` and `web/src/styles/global.css`
- `.gitignore` entries for `web/dist/`, `web/.astro/`, and website test artifacts

Implementation:

- Pin Node `^26.0.0`, `packageManager: pnpm@11.14.0`, and the resolved dependency graph in `web/pnpm-lock.yaml`.
- Install Astro, Astro check support, Tailwind v4 plus `@tailwindcss/vite`, TypeScript, Oxlint/Oxfmt, Vitest, and Playwright test tooling. Do not install React or a Cloudflare adapter/plugin.
- Extend the strict BridgeWeb TypeScript baseline for Astro rather than copying React-specific settings.
- Define scripts for install-independent `check`, `typecheck`, `lint`, `fmt`, unit test, browser test, full test, build, preview, and development.
- Ensure the minimal page's meaningful content is present in built HTML with client scripts disabled.

Pre-change signal: approved scaffold/config exception; no behavior exists to make red first. The first proof is a deliberately minimal static page.

Focused proof:

- dependency inspection proves React, `@astrojs/cloudflare`, and `@cloudflare/vite-plugin` are absent;
- Astro and strict TypeScript checks pass;
- lint/format checks pass;
- unit test harness boots;
- static build produces nonempty `web/dist/index.html` containing the minimal page content.

Stop/replan if current Astro or Oxc tooling cannot satisfy `.astro` checking/formatting without adding a second conflicting formatter. Resolve the tool boundary explicitly before authoring product UI.

## S2 — Approve the visual design board and capture contract

Obligations: R3, R5, R7, R9, R11, R14; U2, U3, U5, U8.

Write surfaces:

- `docs/specs/2026-08-17-marketing-site/2026-08-17-marketing-site-visual-design.md`
- `docs/specs/2026-08-17-marketing-site/website-design-board.html`
- website capture manifest schema and operator packet under the website spec/capture working boundary

Implementation:

- Lock page anatomy, token roles, typography, spacing, responsive layouts, screenshot focal points, image-switcher states, motion, and reduced-motion treatment.
- Review desktop, phone, and all five plate-state keyframes before capturing.
- Convert the accepted board into one mechanical capture matrix; do not let the capture operator make design decisions.

Proof:

- owner visual review of the complete board;
- every image slot names a master, focal area, visible product claim, and mobile crop strategy;
- capture matrix resolves 1440×900 points, 2880×1800 pixels, 2× scale, sRGB PNG, and one fixed app geometry.

Stop if any plate state or section still needs layout or crop judgment from the operator.

## S3 — Produce the dedicated debug capture suite

Obligations: R5, R7, R9, R14; U2, U3, U8.

Write surfaces:

- `web/src/assets/captures/*.png`
- `web/src/content/website-capture-manifest.ts`
- ignored capture evidence under `tmp/website-capture/`

Implementation:

- Build and launch one dedicated debug Agent Studio bundle from the website worktree with verified executable, bundle identifier, PID, isolated data root, and window identity.
- Seed the approved deterministic fixture without copying personal or production state.
- Set the window to 1440×900 points and preserve the same theme, sidebar width, chrome, typography, and pane density for all states.
- A Luna xhigh operator uses Sky to stage each of the six bounded shot packets. Peekaboo may provide PID-targeted control fallback only after a fresh UI snapshot.
- For each shot, use `peekaboo window list --pid <verified-pid> --json`, bind the returned CoreGraphics window ID to that PID, and capture the window ID with `--retina`, `--format png`, and screenshot-only output. Record the untouched 2880×1800 source PNG, its embedded ICC profile, and SHA-256. Do not rely on the generic AX title `AgentStudio` as the selector.
- Convert a copy of each source through ColorSync to sRGB IEC61966-2.1 without resizing. Record the conversion command/profile identity and normalized SHA-256; only the normalized copy becomes the HyperFrames master.
- Record process generation A before the first capture. After `persistent-before.png`, close only its verified PID, relaunch the same executable/bundle/data-root lineage, record process generation B, and reverify its new PID and window identity. Capture the untouched restored state before any UI action and classify every equivalence field. If window bounds are the only allowed delta, normalize the verified window to 1440×900 points without changing workspace state, refresh the window binding, and capture `persistent-restored.png`. Refresh every Sky/Peekaboo state reference after relaunch.
- Build one reusable HyperFrames FocusIsolation composition from the approved masters. It owns four fixed contextual-scrim segments around each rectangular focal region, the optional one-pixel logical focus rail, and settled still snapshots; it does not duplicate or filter the product image.
- Export website emphasis assets from approved settled HyperFrames frames and record source master, focal mask, treatment settings, frame time, output geometry, and SHA-256.
- Reject/retake any image with inconsistent geometry, focus, content density, personal data, cursor, notification, transient animation, or unreadable feature state.

Proof:

- six-source/six-master manifest with identical geometry/build/fixture fields, per-shot PID-to-window-ID binding, source and normalized ICC identities/hashes, and a derivative manifest for the shared HyperFrames treatment;
- image inspection confirms dimensions, color profile, and readable focal regions;
- treatment comparison confirms that product pixels inside each focal mask match its untouched master and that every non-focal region uses the same scrim settings;
- before/restored comparison records window geometry, selected tab, ordered pane arrangement, drawer membership and expanded state, visible session anchors, and every product-owned restore difference as `match`, `allowed delta`, or `failure`;
- capture evidence records both verified process generations and proves that no stale PID, window identifier, or accessibility snapshot crossed the restart boundary;
- no existing user app process was targeted or modified.

Stop if the dedicated debug identity cannot be proven, the fixture cannot be isolated, or the app cannot produce the approved states without product-code changes.

## S4 — Create and enforce VerifiedProductProjection

Obligations: R8, R9, R14; U4, U8.

Write surfaces:

- `web/src/content/product-source-projection.ts`
- `web/src/content/product-copy.ts`
- `web/src/assets/brand/app-icon.svg`
- `web/src/assets/brand/app-logo-transparent.svg`
- `web/src/styles/tokens.css`
- `web/scripts/verify-product-sources.ts`
- `web/tests/product-source-projection.test.ts`

Red-first cases:

- projected install command differs from `README.md`;
- projected primary differs from `AppStyles.primaryHex`;
- projected semantic surface differs from the named `bridge-app.css` role;
- approved icon/logo copy content identity differs from its named owner;
- any capture master or derivative differs from its capture manifest;
- promotional video lacks immutable URI, content hash, poster identity, or approval provenance;
- verification mismatch attempts to rewrite the projection.

Implementation:

- Define a readonly, schema-validated projection with one owner class per value group.
- Keep campaign wording in `product-copy.ts`, with explicit shipped-claim basis identities rather than parsing README copy at render time.
- Compare source text values where they are stable contracts and content hashes where assets are binary/vector copies.
- Treat `AppStyles.primaryHex` as the primary owner; named BridgeWeb roles as surface/text owners; `AppIcon.svg` as stacked-plane palette/geometry owner; `AppLogoTransparent.svg` as the transparent logo owner.
- Record the capture-suite build/fixture/geometry identities and every image SHA-256.
- Record external video URI plus SHA-256 and poster identity. Do not download or choose a replacement during verification.
- Make the website build consume only projection values and approved copies.

Focused proof:

- unit tests cover every mismatch and missing-provenance case;
- verifier succeeds on the current sources;
- verifier failure leaves projection files byte-identical;
- projection-to-owner coverage enumerates claims, install, tokens, icons, images, poster, and video.

Integration gate: rebuild the minimal S1 page from projected identity/color/copy. Confirm no current-owner file is imported or parsed by page rendering.

Stop/replan if the approved launch video and poster lack immutable provenance by the time S5 begins. The page may temporarily render the approved poster during development, but R4 and release readiness remain open.

## S5 — Build static shell, hero, install actions, and media behavior

Obligations: R2, R3, R4, R8, R9, R11; U1, U2, U4, U5.

Write surfaces:

- `web/src/layouts/SiteShell.astro`
- `web/src/components/Hero.astro`
- `web/src/components/InstallActions.astro`
- `web/src/components/ProductVideo.astro`
- `web/src/components/FinalInstallCallToAction.astro`
- `web/src/pages/index.astro`
- `web/src/styles/global.css`, `web/src/styles/tokens.css`
- focused unit/browser tests

Red-first cases:

- built first viewport lacks any required R2 field;
- install command/GitHub destination differs from projection;
- clipboard denial hides or mutates the command;
- reduced-motion mode autoplays;
- video source failure collapses or blanks the product frame;
- off-viewport or hidden-document video continues nonessential playback;
- page-local chrome introduces an unauthorized route.

Implementation:

- Keep the shell Astro-native and static. Navigation/Footer contain only identity, in-page anchors, install, and GitHub.
- Render the install command and GitHub link before enhancement; attach a bounded typed clipboard controller with explicit success/failure status.
- Render native video with approved source, poster, muted/playsinline/loop behavior, explicit play/pause control, off-viewport/document-hidden pause, and reduced-motion poster-first initialization.
- Preserve poster and copy on source/autoplay failure.
- Establish Agent Studio's constrained frame, stacked-plane geometry, focus blue, parallel peach, glyph cyan, system typography, and product-first hierarchy from the projection.

Focused proof:

- unit tests cover typed media/clipboard state transitions where logic is isolated;
- browser tests cover clipboard allowed/denied, reduced motion, source failure, offscreen pause, and static HTML fallback;
- manual Chrome inspection captures the first viewport at the supported desktop and phone widths and verifies text, focus, controls, and product readability.

Stop/replan if the hero composition requires runtime media generation, server negotiation, or an unapproved committed video binary.

## S6 — Implement the progressively enhanced image plate

Obligations: R5, R6, R11, R12; U2, U3, U5, U6.

Write surfaces:

- `web/src/components/InteractiveWorkspaceDemo.astro`
- `web/src/content/demo-fixture.ts`
- `web/src/demo/demo-state.ts`
- `web/src/demo/demo-controller.ts`
- `web/src/styles/product-plate.css`
- `web/src/assets/captures/*.png`
- controller and browser tests

Red-first cases:

- JavaScript disabled or module blocked exposes focusable/operable selectors;
- delayed initialization changes focus;
- root-contract failure partially enables the plate;
- activation failure leaves mismatched selector/panel state;
- valid states do not produce exactly one selected control and exposed panel;
- unknown state changes the last valid state;
- keyboard arrows, Home/End, Enter/Space, focus, or ARIA relationships fail;
- state change modifies URL/storage/network/filesystem/native app;
- persistence introduces nested state or implies live restoration;
- timers continue while hidden or under reduced motion.

Implementation:

- Define a closed discriminated union for the five states and immutable mappings to manifest-verified capture assets.
- Render real capture images; do not recreate app panes, terminals, command palette, or Review UI in HTML.
- Astro renders Parallel work as the only exposed panel. Selectors are native disabled controls without tab roles and outside the focus order.
- Controller validation performs no DOM writes. It verifies all state ids, unique controls, panel correspondence, and default-state invariants.
- One synchronous activation installs listeners/ARIA/roving focus and removes disabled state while preserving current focus.
- Any activation exception runs one rollback restoring disabled selectors, no live tab contract, and only Parallel work exposed.
- Use event delegation only if it keeps ownership and cleanup simpler than per-control listeners; do not add a store or framework.
- Persistent workspace renders the two manifest-verified Before close and Restored masters simultaneously in one labeled panel.
- Derived active-agent/status presentation reads from the one selected demo state; no duplicate selected stores.

Focused proof:

- unit tests cover validation, state reduction, invalid input, reselection, and rollback;
- production-built browser tests cover static, delayed, successful, partial-failure, keyboard, AT attributes, focus-preservation, reduced-motion, and hidden lifecycle;
- manual Chrome proof clicks every state, completes the keyboard sequence, and confirms the URL remains unchanged.

React revisit gate: stop and return to Program Design if implementation needs nested independently stateful controls, asynchronous data, substantial conditional DOM creation, shared page state, or a custom lifecycle/store to remain understandable. Do not add a parallel React path.

## S7 — Add the four capture-derived stories and finish responsive composition

Obligations: R3, R7, R9, R11; U2, U3, U5, U8.

Write surfaces:

- `web/src/components/ScreenshotProofSection.astro`
- `web/src/pages/index.astro`
- semantic/global/component styles
- image and browser tests

Implementation:

- Create exactly four sections in this order: Parallel work, Pane drawer, Quick Find navigation, Review.
- Generate art-directed derivatives from the four matching capture masters; record source master, focal region, output dimensions, and hash.
- Preserve existing `web/images/` files only for README compatibility; do not render them as website production proof.
- Use projected copy and explicit dimensions, responsive `sizes`, useful alternative text, and feature-preserving crops.
- Keep persistence out of the screenshot list.
- Complete the page rhythm from hero to plate to screenshot proof to final install without equal-weight card grids.

Red-first cases:

- section count/order or file mapping differs from R7;
- README references no longer resolve;
- mobile crop loses the feature named by its section;
- alternative text repeats generic marketing copy rather than describing the proof;
- layout produces overflow, unreadable text, invisible focus, or contrast failure at supported widths.

Focused proof:

- static tests assert the closed section/asset mapping and README reference preservation;
- production browser tests cover supported responsive widths and image load failures;
- manual Chrome contact sheet captures wide desktop, laptop, tablet, and phone layouts in one current build;
- manual inspection verifies every screenshot's focal product feature and text contrast.

Integration gate: run the complete production page with JavaScript enabled and blocked. Both journeys reach every static section and final install action; only the plate state switching and clipboard enhancement differ.

## S8 — Integrate repository gates and Cloudflare Pages delivery

Obligations: R1, R10, R13, R14; U6, U7, U8.

Write surfaces:

- `.mise.toml`
- `.github/workflows/ci.yml`
- website deployment workflow or documented Cloudflare Pages Git integration, choosing one source of deployment authority
- `web/package.json` scripts and lockfile as required by final gates
- `.gitignore`
- a concise website deployment runbook if external Pages configuration is not fully represented in Git

Implementation:

- Add `website-install`, `test:website:check`, `test:website:unit`, `test:website:browser`, `test:website`, and `website-build` mise tasks rooted at `web/`.
- Add `mise run test:website` to the root aggregate before Swift tests without changing existing BridgeWeb/Swift gate semantics.
- Add an independent Linux website CI job using Node 26.5, pnpm 11.14, the `web/pnpm-lock.yaml` cache key, frozen install, source verification, checks, tests, and static build.
- Configure Cloudflare Pages with production branch `main`, build rooted at `web/`, output `dist/`, and pull-request preview deployments. Prefer native Pages Git integration unless a repository-owned deployment workflow is required for auditable secrets/project selection; do not configure both.
- Use the default Pages production URL until the owner selects a custom canonical domain. Record the chosen Pages project identity; if `agentstudio` is unavailable, stop for the owner-visible alternative rather than silently changing public identity.
- Make promotion depend on VerifiedProductProjection verification and all website gates.
- Preserve rollback to the preceding successful Pages deployment.

Focused proof:

- root `mise run test:website` passes from the monorepo root;
- root aggregate includes and actually executes the website gate;
- website CI job passes on the current SHA and publishes a nonempty static artifact;
- pull request receives a reachable Pages preview URL showing the current SHA;
- preview inspection repeats the key static/interactive/media/accessibility/visual checks against the deployed artifact;
- production deployment from `main` and rollback visibility are demonstrated before release completion.

Stop/replan if Cloudflare requires SSR/Workers, runtime bindings, or a direct Vite plugin for any selected behavior. Those are Specification/Program Design expansions, not deployment fixes.

## Final integration and completion gate

The implementation is complete only when one current production-equivalent build supplies all evidence below:

1. Source projection verification passes and proves no automatic adoption path.
2. Static HTML remains useful with client code blocked.
3. Hero video/poster, reduced motion, offscreen lifecycle, and error fallback work.
4. Every plate state works by pointer and keyboard; pre-enhancement controls are honest and rollback is complete.
5. Four screenshot sections use derivatives of their matching WebsiteCaptureSuite masters and remain readable at all supported widths; the historical README image paths remain unchanged and continue to resolve only for README consumers.
6. Astro/TypeScript, Oxlint/Oxfmt, unit/browser tests, static build, `git diff --check`, and the root aggregate pass.
7. Manual Chrome evidence covers desktop/phone layout, keyboard focus, reduced motion, every plate state, video controls, and product readability.
8. A Cloudflare Pages pull-request preview serves the reviewed commit and production deployment/rollback proof exists for `main`.

Passing lower layers must be reported separately from any missing visual, deployed-runtime, or production proof. No local build or mocked browser result substitutes for Cloudflare preview evidence.

## False-green risks

- The verifier validates its own manifest but never opens named source owners.
- A site build succeeds while copy or tokens are parsed directly from current owner files.
- Enhanced plate tests pass while disabled/module-failure states still expose fake controls.
- DOM assertions pass while real focus appearance, image crops, or video controls are unreadable.
- A poster renders while the approved video source or immutable identity is absent.
- Browser tests run against development mode instead of the production static build.
- README image links pass in the website but break on GitHub.
- CI produces `dist/` but the Pages preview serves another commit or prior artifact.
- Cloudflare preview success is reported as production deployment/rollback proof.
- React or Workers dependencies enter transitively without an explicit boundary decision.

## Stop and replan conditions

Return to Specification or Program Design before continuing if:

- a sixth product state, fifth screenshot, additional route, documentation surface, or new product claim is required;
- verified source ownership cannot be represented without automatic adoption or mutable external selection;
- the approved video lacks a stable URI/hash/poster identity;
- the product plate crosses the documented React-island threshold;
- any selected behavior requires SSR, Workers, bindings, authentication, analytics, or persistence;
- Cloudflare Pages cannot satisfy the static preview/production contract;
- required accessibility or visual proof cannot observe the production-built surface;
- implementation would change native app, Bridge, persistence, or release owners.

## Plan result

This is a `ready` plan for the `plan-only` terminal. It authorizes no implementation, external Cloudflare mutation, tracking mutation, PR creation, push, or merge. A later executor must revalidate the governing artifacts, completed review plus parent-verified remediation, branch/HEAD, repo instructions, media provenance, and environment before changing product code.
