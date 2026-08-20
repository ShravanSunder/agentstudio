# Agent Studio marketing site visual and copy remediation

## Goal

Bring the live Astro site back to the identity already present in Agent Studio: softened overlapping planes, exact icon colors, product-specific focus treatment, and README-grounded language that a person can understand on one reading.

The local development site remains `http://127.0.0.1:4321/`.

## Settled decisions

- The canonical Agent Studio README owns shipped claims, product terminology, install commands, and feature wording.
- The website headline is the owner-approved shorter promise `Stay oriented
  without losing context.`
- `Organized parallelism` introduces the interactive product switcher. It is not decorative screenshot chrome.
- Decorative labels such as `Real Agent Studio capture`, `One workspace · Five product stories`, and `product surface` are removed.
- The header contains Agent Studio identity and the GitHub link only. In-page `Workspace` and `Review` links are removed.
- The clickable explainer owns Parallel work, Drawer, Quick Find, Review, and Persistence. The repeated long-form proof sections below it are removed.
- The top-level site frame has no gap above it.
- Side-gutter decoration disappears at narrow widths; content becomes edge-to-edge within the viewport.
- The current grid is an acceptable fallback, but a subagent will propose icon-derived alternatives before the background pattern changes.
- The website canvas uses the current app's Ghostty terminal background
  `#2e3036`, sampled as the dominant blank-terminal pixel in the native capture.
  `#24273a` remains an icon/brand token, not the page canvas.
- Marketing geometry must follow the canonical icon's softened overlapping planes. Native product captures retain their source geometry.
- Focus treatment must fit the actual UX surface. A generic rectangular rail or invented zoom is a failure.
- The README's two-step Homebrew installation remains authoritative.
- The `ai-copywriter` skill is local-only, pinned to reviewed upstream commit `08b53b1ad39887cd94cbaab61cac3b6aae2d8518`, and constrained by repository instructions.

## Checklist

This document is the canonical execution ledger. Progress updates must link to
the applicable heading below. A checked box means the source change and its
named proof both passed; editing the source alone does not complete an item.

## Owner visual rejection and reopened acceptance

The 2026-08-18 owner review rejects the previous visual acceptance. The
automated proof remains useful, but it did not prove campaign quality. The
current acceptance contract is the
[visual rubric](communications/2026-08-18-website-visual-acceptance-rubric.md).

The owner rejected all six legacy website images as one failed suite. On
2026-08-18 the six website copies, six HyperFrames masters, generated stills,
final snapshots/contact sheets, and six temporary v2 source captures were moved
to the macOS Trash. They are recoverable, but none may return to the website or
serve as an accepted source. Manifests, receipts, logs, and composition code
remain as failure evidence until the replacement suite supersedes them.

- [x] Make the clickable explainer the first product proof and remove the
  standalone hero screenshot.
- [x] Keep Parallel work selected by default so its replacement capture is the
  first product image.
- [x] Replace the rejected four-pane suite with one consistent two- or
  three-pane suite at a smaller 16:10 capture size.
- [x] Rebuild every focus treatment from the new measured UI boundaries.
- [x] Replace repeated gutter pane stamps with a restrained real grid pattern.
- [x] Use the official GitHub mark for the remaining header action.
- [x] Remove the redundant GitHub action from the final CTA.
- [x] Remove the redundant GitHub action from the hero and center the Homebrew
  install/Copy surface beneath the product description.
- [x] Use the darker Ghostty pane ground and clean alignment for install/Copy.
- [x] Art-direct `Stay oriented without losing context.` as a deliberate
  two-line desktop lockup and tighten the spacing before Organized parallelism.
- [x] Replace the footer text with the Agent Studio icon on the left and
  official GitHub/X icon links on the right.
- [x] Point footer GitHub to `https://github.com/shravansunder` and footer X to
  `https://x.com/shravansunder`.
- [x] Give Claude Opus and Cursor Grok the same final rubric and require two
  assignment-bound review receipts.
- [x] Require every copy-writing or copy-review subagent to read the complete
  project-local `ai-copywriter` skill and record the coverage in its receipt.
- [x] Re-run all automated, pixel, and live visual proof against the replacement
  assets before claiming completion.
- [x] Fetch and follow Cloudflare's current agent setup instructions from
  `https://developers.cloudflare.com/agent-setup/prompt.md` only after UI/media
  acceptance, then deploy the static `web/dist` artifact through the logged-in
  Cloudflare account and verify the live URL.

### Copywriting skill

- [x] Review upstream `ai-copywriter` package with a fresh Sol High subagent.
- [x] Install the complete skill under `web/.agents/skills/ai-copywriter/`.
- [x] Install an identical copy under Agent Studio Media `.agents/skills/ai-copywriter/`.
- [x] Add website routing constraints to `web/AGENTS.md`.
- [x] Add media routing constraints to Agent Studio Media `AGENTS.md`.
- [x] Restore and verify byte-identical project-local skill copies. The website
  formatter had changed Markdown and JSON layout inside the installed skill;
  `.agents` is now excluded from Oxfmt and the two skill trees compare cleanly.
- [x] Bind the complete-skill receipt gate to the shared final-review rubric and
  re-dispatch current copy reviewers under that gate. Geometry-only operators
  must state that they did not write or judge copy.

The owner-level checkbox above remains open until the final Claude Opus and
Cursor Grok receipts each identify the exact project-local skill path and
confirm complete coverage through that file's current end of file. The receipt
must report its actual `N/N` line count rather than rely on a count copied from
an earlier revision. Copy-inclusive verdicts without that evidence are invalid
and cannot support shipment.

### Copy hierarchy

- [x] Remove screenshot-caption filler.
- [x] Move `Organized parallelism` to the switcher introduction.
- [x] Replace `Parallel work gets a map` with the README heading `Keep parallel work separate, but visible.`
- [x] Centralize every visible line in a typed copy owner.
- [x] Use the README descriptor and value promise in the hero.
- [x] Use README feature language for the switcher.
- [x] Remove jargon such as `product stories`, `product surface`, `agent contexts`, and `one work context`.
- [x] Replace the incomplete one-line install command with the README's two-step install flow.
- [x] Remove duplicated CTA/footer metadata and keep one canonical product-trait line.
- [x] Re-run plain-language critique after implementation.

Copy-review reduction:

- Accept: current copy is plain, reader-first, and free of unsupported product
  claims or filler.
- Reject: restoring `while they work` in the headline. The owner explicitly
  selected the shorter `Stay oriented without losing context.` wording, so that
  settled copy outranks README-exact phrasing.
- Accept for the next website edit: replace the metadata title's em dash with a
  colon.
- Verified by owner instruction: footer links point to
  `github.com/shravansunder` and `x.com/shravansunder`.

### Header and responsive frame

- [x] Keep only the GitHub link in the header.
- [x] Remove the repeated proof-story sections below the clickable explainer.
- [x] Remove the top gap above the site frame.
- [x] Remove side gutters and side decoration at narrow widths.
- [x] Verify header alignment and focus state at desktop and phone widths.

Details and proof:

- Owners: `web/src/site-shell/SiteShell.astro` and
  `web/src/styles/global.css`.
- Desktop acceptance: the site frame starts at the top edge, the Agent Studio
  identity and GitHub link align, and gutter decoration does not enter the
  content canvas.
- Narrow acceptance: at `900px` and below, gutters and their decoration are
  absent rather than compressed or clipped.
- Proof: browser screenshots at desktop and phone widths, keyboard focus on the
  GitHub link, and zero horizontal overflow.
- Hero action proof: the live layout contains no GitHub link inside
  `.hero__actions`. Desktop acceptance compares the 470px install control's
  center with the full `.hero` frame center, not the narrower description
  column. At 390px the control occupies the available 339px content width with
  no horizontal overflow. Playwright asserts one exact `GitHub` navigation
  link, zero hero action links, and full-frame centering. The live 1600px proof
  measures both the `.hero` and install centers at `792.5px`, a `0px` offset;
  all 6 desktop/mobile browser tests pass.

### Icon and visual geometry

- [x] Run Cursor Grok 4.6 High taste review with the exact ACP model id.
- [x] Sample exact palette values and geometry from the canonical SVG rather than approximate them.
- [x] Replace the square hero plane stack and unrelated icon tile.
- [x] Introduce a restrained radius system for shell, product frames, controls, and buttons.
- [x] Keep structural hierarchy without turning the page into rounded-card or pill UI.
- [x] Evaluate subagent background-pattern proposals; keep the current grid if none is more ownable.

Details and proof:

- Owners: `web/src/home-page/Hero.astro`, `web/src/styles/global.css`, and the
  canonical SVG copies in `web/src/assets/brand/`.
- Geometry source: three overlapping planes with the canonical `-12deg`,
  `+7deg`, and `0deg` rotations. Marketing surfaces use restrained radii that
  echo the icon without turning every element into a card or pill.
- Palette source: `#363a4f`, `#24273a`, `#11111b`, `#151520`, `#1e1e2e`,
  `#ef9f76`, `#89b4fa`, and `#74c7ec` only where their semantic role applies.
- Canvas proof: the dominant blank-terminal pixel in the current native app
  capture is `#2e3036`. The live page body and browser `theme-color` project
  that exact value; regression coverage rejects a return to the purple
  `#24273a` canvas.
- Background decision: use sparse overlapping pane-plane stamps in wide side
  gutters if they remain quiet in the live page; otherwise retain the grid.
  Never combine both patterns.
- Proof: source-token comparison against the canonical SVG plus desktop and
  phone screenshots of the live Astro page.
- Review routing: Cursor accepted exact ACP id
  `grok-4.6[effort=high,fast=true]` but did not emit a complete verdict. Claude
  Opus fallback was blocked by an expired OAuth token. A fresh native Sol High
  reviewer completed the independent taste gate; its accepted findings were
  remediated once and sent back for verification.

### Focus assets

#### Current five-state narrative

The selector remains five states. Current sidebar work is proof for Parallel
Work, not a sixth story:

1. **Parallel Work — understand the whole workspace.** Use `All Panes` as the
   baseline overview with two or three readable panes. The live maximum-width
   website plate proved that the 100-item `By Repo` fixture becomes an
   unreadable branch list at marketing scale, while `All Panes` preserves real
   repository, branch, Git, recency, note/latest-output, and keyboard-ownership
   evidence. `By Repo` and `By Tab` remain supporting grouping controls, not
   separate marketing claims. `active` means keyboard ownership, never agent
   health or execution.
2. **Pane Drawer — keep related context attached.** Show one primary pane with
   two or three real drawer children such as terminal, Files, Review, browser,
   or build output. The drawer must read as owned by the primary pane, not as a
   generic independent bottom panel. Pane notes and Git controls may support
   the frame but do not become new stories.
3. **Quick Find — move through the workspace from the keyboard.** Open the real
   `Cmd+P` surface over the same workspace. Prefer one real `#` repository or
   worktree query; `$` panes/tabs or `>` commands may appear only if the frame
   remains readable. Do not imply global filesystem or source-code search.
4. **Review — inspect changes beside the work.** Open a real dirty worktree in
   Review with the originating terminal, Changed Files tree, and one selected
   populated diff all readable. The surface is read-only; do not imply editing,
   review comments, or planned annotation/context-return features.
5. **Persistent Workspace — return to the same work.** Capture a matched
   before/after pair from one fresh dedicated process. Preserve two or three
   persistent terminals, tabs/layout, selected context, and terminal content.
   zmx owns process continuity; SQLite owns workspace structure. Do not claim
   that temporary sessions persist.

Source authority for this narrative is the current
`agent-studio.fix-sidebar-grid-alignment` README and source. The owner accepts
the running `h4u3` debug bundle as the capture authority for this suite because
its sidebar, Git, PR, note, and pane-grouping behavior is the version intended
for main. The capture receipt records bundle identifier
`com.agentstudio.app.debug.dh4u3`, executable SHA-256
`6f53124fb6e8575e69cc0b1ce59aa1701855ae892754e72d9495eb67ce704ff4`, and the
current source checkout separately; do not infer that a later checkout HEAD
was embedded in the already-running executable.

#### Shared screenshot contract

- Every source is exactly `1280x800` logical points and `2560x1600` physical
  pixels, 2x Retina, sRGB. This 16:10 frame displays at approximately
  `976x610` inside the maximum desktop product panel beside the 280px selector
  rail; wider captures become too short and make sidebar text unreadable.
- Use the same window position, sidebar width, toolbar density, theme, font,
  fixture repositories, and capture method for the entire suite.
- Use two or three readable primary panes. No four-pane strips, empty panes,
  management controls, cursor, notifications, personal paths, unrelated apps,
  or random shell history.
- Capture untouched current app pixels. No crop, perspective, color grade,
  scrim, synthetic blue rail, glow, or baked peach/orange perimeter. Peach is
  valid only where the real app or later brand composition uses it as
  intentional parallel/background context.
- Product images render borderless inside the outer website product plate. The
  captured app chrome and the outer plate are the only frames.
- Parallel Work must pass full-resolution source inspection and a live render
  inside the real maximum-width product plate before any other state is
  captured. After that, all six final PNGs pass or fail together through one
  source contact sheet and one processed contact sheet.

- [x] Accept six replacement native captures from the current 2560x1600 suite.
- [x] Reject and remove the complete legacy image chain from live website,
  HyperFrames master/output, snapshot, and temporary source locations.
- [x] Accept a clean Parallel Work source before capturing any other state.
- [x] Inspect each accepted untouched capture and record the actual UX-surface bounds.
- [x] Quick Find: fit the focus treatment to the command surface and its native radius.
- [x] Pane drawer: fit the treatment to the real drawer boundary.
- [x] Review: preserve the real terminal-to-diff-to-file-tree reading path without an arbitrary box.
- [x] Parallel and persistence: avoid unnecessary focus rails or fake zoom.
- [x] Regenerate HyperFrames outputs and update every hash/provenance record.
- [x] Verify focal pixels remain exact and compare all six outputs as one contact sheet.

Details and proof:

- Parallel Work acceptance: untouched 2560x1600 Retina PNG, SHA-256
  `343afef132da533223a0b0ee5818e9c5bee2bc1c3d5bfb387aae54915a94e83a`, two
  panes, `All Panes`, real `y-websocket` ahead/behind status, real Agent Studio
  dirty-file output, real sidebar Git/recency/activity evidence, and no focus
  rail or added frame. The image passed full-resolution inspection and an
  uncached 1600px-wide live Astro render at 1120x700 optimized pixels inside
  the production product-plate geometry.
- Pane Drawer acceptance: untouched 2560x1600 parent-window capture, SHA-256
  `295ca6f42dfb414986f2925e79563f348f1b89a74725ac4354179e8bdfb8121e`.
  One real drawer terminal is attached to the Agent Studio primary pane and
  contains real `git diff --stat` output. The app's native drawer supplies the
  dimmed surround and bright focus; no marketing scrim or focus rail is added.
- Quick Find acceptance: 2560x1600 measured native-window composite, SHA-256
  `ae87b8655804e8f65eaf4ef13c7ab8561f9cd239fc1eac97024e9fa1d574072c`.
  macOS presents the parent workspace and Quick Find sheet as separate windows,
  so the capture freezes both native window surfaces and places the 600x456
  point sheet at its observed 340x192 point parent-relative offset. A 24-point
  alpha clip removes the capture API's white backing outside the sheet's native
  rounded corners; the Agent Studio pixels themselves are not redrawn. The
  visible query is `# agent-studio` and is not executed.
- Review acceptance: untouched 2560x1600 Retina PNG, SHA-256
  `f5795f0e0f6cac3325af9014d29346ed3d386a636d3129e0527f0b398713a79c`.
  It shows the real `fix/sidebar-grid-alignment` terminal beside a populated
  Swift diff and Changed Files tree. The repository sidebar is hidden so the
  terminal-to-diff-to-file-tree path remains readable at website scale.
- Persistence acceptance: the before frame SHA-256 is
  `f806f6e696a50def8a67ba049b9b4c505f7bd567b964263e3293ec6fce9a83c3`; the
  restored frame SHA-256 is
  `f8a30d68d749cfc77461cea6ba98bc29e0e1f971dbc956f3b1b51be61610fae5`.
  The exact h4u3 app exited normally at PID `76930` and reopened under PID
  `78182` with a new runtime identity. The same five tabs, two-pane arrangement,
  drawer and Review entries, terminal output, repository grouping, and Git
  context returned. Pre-existing h4u3 zmx session PIDs remained alive across
  the app-process restart. Both 2560x1600 images loaded in the live website
  comparison.

- Owners: Agent Studio Media
  `assets/website-product-stills/index.html` and the website copies in
  `web/src/assets/captures/` plus
  `web/src/content/website-capture-manifest.ts`.
- Source rule: every final still starts from a current, untouched Agent Studio
  capture. README screenshots are references only.
- Treatment rule: the muted surround and bright focus must follow the real UX
  surface. Quick Find follows the command palette radius, the drawer follows
  the drawer boundary, and Review keeps the terminal-to-diff-to-file-tree path
  readable without an invented rectangle.
- Consistency rule: all output stills share dimensions, crop, color handling,
  border treatment, and product-frame presentation.
- Proof: regenerate all outputs, update SHA-256 and lineage records, run the
  HyperFrames check, verify focal pixels against sources, and inspect one
  six-image contact sheet.
- Export proof: HyperFrames 0.8.4 renders the full-frame stills and contact
  sheet. All six exported still hashes match their accepted masters exactly;
  the website pipeline adds no marketing scrim or focus rail.

Current 2560x1600 capture acceptance:

- Parallel Work: rejected for four narrow panes, unreadable content, and the
  wrong default product overview.
- Pane Drawer: rejected for a giant empty drawer, excessive dimming, and a
  synthetic blue focus perimeter.
- Quick Find: rejected for excessive dimming, synthetic blue outline, and the
  old four-pane background.
- Review: rejected for over-dimming and an awkward narrow diff crop that does
  not present the terminal-to-review relationship clearly.
- Persistence pair: rejected for the giant empty drawer, four-pane background,
  and an unhelpful before/restored comparison.
- Entire suite: rejected for inconsistent framing and unexplained peach/orange
  perimeter treatment. Peach remains an approved brand color for intentional
  parallel/background context, never an automatic border around product
  footage.
- Website presentation: product images render borderless inside the outer
  product plate. The site must not add a second frame around captured window
  chrome.

### Proof and delivery

- [x] Run Astro/type-aware Oxlint/Oxfmt with zero errors and warnings.
- [x] Run Vitest state-machine tests.
- [x] Re-run Playwright desktop/mobile, JavaScript-disabled, keyboard, and
  overflow tests after the replacement stills land.
- [x] Run HyperFrames check with zero errors and warnings against the rebuilt
  2560x1600 still pipeline.
- [x] Capture replacement desktop and phone screenshots for visual acceptance;
  the existing review screenshots show the superseded page.
- [x] Keep the dev server live for owner review.

Details and proof:

- Copy proof: run the project-local `ai-copywriter` audit in embedded mode and
  preserve README facts, terminology, and approved voice.
- Quality proof: Oxfmt, type-aware Oxlint, Astro check, Vitest, and the static
  build all exit successfully with zero errors or warnings.
- Latest scoped quality run after copy-skill and metadata corrections: Oxfmt
  checked 23 files; Oxlint emitted no findings; Astro reported 0 errors, 0
  warnings, and 0 hints; Vitest passed 9/9 tests; the static build generated one
  page successfully.
- Browser proof: Playwright covers desktop, mobile, JavaScript-disabled,
  keyboard, and overflow behavior; a live Chrome sweep confirms the actual
  page rather than only test assertions.
- Product-plate fit proof (2026-08-20): selector block padding now scales from
  9px to 11px so the five-item rail and uncropped 16:10 capture share one
  baseline. Live measurements show 20.8px top / 19.2px bottom image inset at
  1600px, 21.0px top / 20.5px bottom at 1440px, and 8.8px top / 7.2px bottom
  at 390px. The 390px document has no horizontal overflow. Oxfmt, type-aware
  Oxlint, Astro check (25 files, 0 findings), capture verification (6 assets),
  Vitest (9/9), Playwright (6/6), and the static build pass. The first two
  sandboxed Playwright attempts aborted while launching system Chrome before a
  page test executed; the unchanged suite passed once allowed to manage its
  temporary headless Chrome processes.
- Production console proof (2026-08-20): clean 1440px, 1600px, and 390px loads
  have zero site-origin errors or warnings, no Astro developer toolbar, and no
  document overflow. The connected browser reported extension-origin warnings
  only; those URLs are outside the website origin.
- Persistence alt text now states the evidence visible in the paired frames:
  five restored tabs plus the same terminal panes, drawer and Review entries,
  terminal output, and sidebar grouping. It no longer implies that the same tab
  labels occupy the visible strip position in both captures.
- Media proof: the website-stills HyperFrames project passes its pinned check.
- Handoff proof: the dev server remains reachable at
  `http://127.0.0.1:4321/` after the final source state is built.
- Cloudflare proof (2026-08-20): the current official agent-setup prompt was
  fetched; its generic MCP-install step was intentionally skipped because the
  owner requires the authenticated `cf` CLI and previously removed those MCP
  registrations. `cf build` produced the Build Output Specification, the
  prebuilt dry run read 26 static assets with no bindings, and production
  deployed Worker `agent-studio-web` version
  `20835c79-23f5-41a3-b15d-54c8c4a87366` at
  `https://agent-studio-web.askluna.workers.dev`. Live 1440px and 390px browser
  proof confirms the headline, default Parallel work state, drawer switching
  without URL mutation, loaded product media, one GitHub link, no Astro toolbar,
  no document overflow, and zero site-origin console warnings or errors.

## Evidence retained

- Plain-language critique: README descriptor, value promise, product traits, mechanism, and six feature headings are the canonical copy set.
- Skill review: upstream package is safe under local constraints; its implicit in-place rewrite mode and mechanical humanizer rules may not override repository authority or approved voice.
- User references identify four concrete failures: arbitrary focus bounds, harsh square geometry, mismatched icon-plane colors, and filler labels above product imagery.
- Final website quality gate: Oxfmt and type-aware Oxlint emitted no findings;
  Astro reported 0 errors, 0 warnings, and 0 hints; capture verification passed
  for 6 assets; Vitest passed 9 tests; Playwright passed 6 desktop/mobile tests;
  and the static Astro build completed.
- Final media gate: six pixel-verified exports completed and HyperFrames 0.8.4
  check passed with 0 lint, runtime, layout, motion, or contrast findings.
