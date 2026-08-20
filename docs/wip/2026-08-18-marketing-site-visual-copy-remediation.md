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

### 2026-08-20 phone carousel hierarchy correction

Owner review rejected the stacked carousel because the wide title and caption
block dominates each slide while portrait crops remove product context. Below
the existing 900px `site-edge` breakpoint, one compact composition owns the
title, complete image, and caption. The desktop selector and image geometry
remain unchanged.

- [x] Replace the tall stacked selector with one compact selected-story row.
- [x] Place the selected product image immediately after the title row at the
      full available plate width.
- [x] Use the complete uncropped 16:10 capture in portrait. The previously
      accepted 4:5 phone derivatives are rejected by owner review because they
      remove too much workspace context.
- [x] Place exactly one matching short caption after the image.
- [x] Use the existing active-surface plane, white index and title, white
      arrows, and one primary-blue selection rail. The desktop rail is inset
      from the rounded corner; the responsive rail fills the title boundary.
- [x] Prove the responsive composition at `899x900`, the desktop rail at the
      exact `900x900` system boundary, and all five stories at
      `390x844`, including title, image, caption,
      arrow navigation, no overflow, and no image/caption mismatch.
- [x] Prove the desktop plate remains unchanged at `1600x1000` with its 280px
      selector rail, hidden arrows, and no responsive caption.
- [x] Obtain independent visual and copy verdicts from all ten responsive
      renders. Visual remediation passes after aligning Tailwind, semantic CSS,
      and the controller to strict `<900px`. Copy remediation passes after all
      five captions were shortened to a consistent one-line phone rhythm.
- [x] Run format, lint, strict Astro and TypeScript checks, capture verification
      and pixel audit, 12 unit tests, 40 browser tests, static build, diff check,
      and zero-warning local console inspection.

Current result: `READY FOR OWNER REVIEW`. Deployment remains blocked on owner
approval and the release SOP.

### 2026-08-20 installed Beta slideshow replacement pass

This is the current image-and-copy lane. Earlier capture acceptance does not
override these results.

- [x] Reject all five current website slideshow images after independent
      source, desktop, and phone review. Parallel work, Pane drawer, Review,
      and Git/PR fail source-story quality. Quick Find's old source is clean but
      its copy overclaims the visible scope. All five fail rendered text
      readability at the current desktop and phone sizes.
- [x] Shorten and separate the five slideshow claims through the complete
      project-local copywriter gate. Each line now owns one outcome and remains
      grounded in the current README and product-marketing context.
- [x] Capture a replacement full-screen Review source from the installed Beta
      at native `1280x800` points and `2560x1600` Retina pixels. The global
      Agent Studio sidebar is hidden; the continuous AGENTS.md diff, complete
      Review toolbar, and complete Changed Files tree are visible. Source
      SHA-256:
      `d47a107954f01c7caa1934599c1a0484e038835c5b0e6bce1ce36ec022910819`.
- [x] Capture a replacement Quick Find source from the same installed Beta
      geometry. The global sidebar is hidden; the native sheet, recent
      repositories, and `> cmd · $ pane · # repo` scope legend are visible;
      there is no cursor, wallpaper, white backing, or clipped sheet edge.
      Source SHA-256:
      `f16982cc16a21acefb16a47311f89e505afd427b863af3bc63923cb1ef744cc5`.
- [x] Accept a focused Quick Find phone derivative from the untouched master.
      It retains the complete native sheet and narrow parent context. SHA-256:
      `991a51e4ce862f596736451f4a3b25d0ecfb94b5e83c7887abbb95ade9bbd848`.
- [x] Replace the rejected Review center crops with a right-anchored crop that
      keeps the complete Changed Files tree and adjacent diff context. Parallel,
      Drawer, and Git/PR use clean left-anchored crops around one complete
      relationship; Quick Find keeps its centered complete-sheet crop. Phone
      copy narrows to the evidence each crop preserves.
- [x] Reject extra treatment on Quick Find because the native sheet already
      supplies the correct focus hierarchy. Reject extra Review dimming because
      it does not materially improve the already-focused source.
- [x] Capture replacement Parallel work, Pane drawer, and Git/PR sources from
      the owner-prepared Beta workspace after native UI control is available.
      Parallel shows All Panes with already-running Antigravity and Codex.
      Drawer hides the global sidebar and uses one compact attached Git-status
      terminal. Git/PR filters By Repo to the PR-linked worktree and shows
      explicit PR 201 beside branch context.
- [x] Inspect every owner-prepared Beta tab through Computer Use before capture.
      Reject `lots of terminals` for generic shells and empty regions. Reject
      `codex` for authentication warnings, a failed resume, and unrelated chat.
      Keep `skills changes` as purpose-made Review context. Clear the existing
      Codex pane's visible terminal buffer without prompting or restarting it,
      then move that already-running pane beside Antigravity.
- [x] Verify the installed Beta's current sidebar evidence through Computer
      Use. All Panes exposes Antigravity, Codex, shell, and Review panes, while
      By Repo exposes real branch, changed-line, ahead or behind, and PR state.
      PR 201 was verified against GitHub before its terminal and native PR
      control were admitted as evidence.
- [x] Open the existing agent-studio drawer with the global sidebar hidden and
      reject the persisted maximum-height state. Set the documented native
      `drawerHeightRatio` to `0.35` from the focused existing drawer terminal,
      repopulate it with concise real Git status, and accept only the resulting
      compact state.
- [x] Adopt images, responsive crops, alt text, and per-capture manifest
      provenance only after all
      five replacement sources pass as one suite. Mixed old/new provenance is
      not accepted.
- [x] Obtain independent source, copy, desktop-render, phone-crop, and
      phone-render acceptance. Pass 5 accepted all five stories and the
      campaign as `READY FOR OWNER REVIEW` with no remaining slideshow-quality
      correction.
- [ ] Render all five accepted states at desktop and phone sizes, obtain owner
      approval, then run the complete release proof. Local production desktop
      and phone rendering, 36 browser tests, capture audits, build, and
      site-origin console inspection pass; owner approval and deployment remain
      open.

Current result: `READY FOR OWNER REVIEW`. The repository serves the atomic
five-image replacement locally with five responsive phone assets. Deployment
remains blocked on owner approval and the release SOP.

### 2026-08-20 current owner review: screenshot and frame quality

This is the active checklist. Historical checked rows below do not override an
open row here.

- [ ] Reinspect all six current source assets at 100 percent, including enlarged
      alpha/corner composites on both checkerboard and `--product-ground`.
- [ ] Click and visually inspect all five product states at `1600x1000` and
      `390x844` in local production and the exact deployed Cloudflare version.
- [ ] Replace any screenshot with a white/bright corner, opaque backing,
      double border, synthetic mask, mismatched radius, accidental crop, or
      image-to-panel gap. Passing four exact corner pixels is necessary but not
      sufficient.
- [x] Make every full app window fit the product-image boundary with all four
      native edges visible; do not use CSS clipping, radius, `object-fit: cover`,
      or a marketing frame to hide a bad source.
- [x] Reject and replace Pane drawer if the drawer overwhelms the frame, hides
      the named agents, or contains unrelated/mostly empty output.
- [x] Recapture Review in unified diff mode with the global repository sidebar
      hidden, the Review Changed Files sidebar fully visible, one readable
      selected file, and the originating agent terminal still readable beside
      it.
- [x] Keep exactly two primary panes in every showcase capture. Sidebars are
      context surfaces, not additional panes.
- [x] Keep recognizable already-running agent UI visible in every primary
      capture. Capture preparation may arrange panes but must not start, prompt,
      interrupt, or steer an agent without a separate explicit owner handoff.
- [x] Apply the global-sidebar visibility matrix deliberately: Parallel shows
      Pane/All Panes; Git/PR shows By Repo beside two agent/terminal panes;
      Drawer, Quick Find, Review, Files, Pane Zoom, and full-screen views hide
      the Agent Studio sidebar. Review and Files keep their own file tree.
- [x] Reject the Git/PR capture if it reuses Review or Files merely to fill the
      second pane. It must show repository context beside two meaningful
      agent/terminal panes.
- [x] Extend browser proof to activate and measure Parallel work, Pane drawer,
      Quick Find, Review, and Git context at desktop and phone widths. Exercise
      Before close and Restored in the supporting persistence row. No
      default-state inference.
- [x] Run the project-local copy skill against every visible line only after the
      screenshots prove their claims; do not rewrite copy to excuse weak pixels.
- [ ] Rebuild local desktop/phone/source/corner contact sheets from the exact
      post-fix commit and reject the suite if one state fails.
- [x] Remove the unexplained full-width divider between the product showcase
      and the following content; section spacing owns that transition.
- [x] Verify the product showcase ends with exactly one visible boundary. Reject
      any deployed state showing the rounded plate border plus a second
      full-width section rule or empty bordered strip beneath it.
- [x] Replace CTA-specific spacing with shared content/action/section rhythm
      tokens; prove the hero install block has deliberate space above and below
      at desktop and phone widths.
- [x] Resolve header/footer shell-radius asymmetry. The resting header is a
      complete dark-glass box without a gap above the site frame; after
      scrolling, that same element contracts into a centered floating pill.
      The footer is a complete dark-glass box using the floating header's exact
      24px radius.
- [x] Correct product-selector color semantics. Inactive story numbers use a
      muted neutral; the selected story number and selection rail use primary
      blue `#89b4fa`. Reserve peach `#ef9f76` for intentional parallel,
      related, or background context rather than applying it to every index.
      Click all five states and verify the selected/inactive hierarchy at
      desktop and phone widths.
- [x] Remove every empty product-panel region beneath showcase media. Exercise
      all five selected states at `1600`, `1440`, `1360`, `1350`, `1200`, and
      `390px`; the visible image bottom must equal its owning panel bottom
      within one CSS pixel.
- [ ] Replace the numbered secondary-feature accordion with restrained
      Herdr-inspired rows: human-readable explanation on the left and one
      relevant visual proof on the right. Remove the repeated `01`–`04`
      numbering/card pattern. Use an approved product still when a state is
      enough; use a short silent HyperFrames loop when motion is the proof.
      Every loop must derive from an approved current capture, fit the shared
      media boundary, render deterministically, and provide an equivalent
      reduced-motion still. Do not add placeholder animation or decorative
      motion without a product claim.
- [ ] Run format, lint, strict typecheck, capture audits, unit tests, all-state
      browser tests, static build, and zero-warning console inspection.
- [ ] Deploy only the accepted exact commit, then repeat the full deployed
      walkthrough and record the Cloudflare version and rollback route.

The previous deployed 1600px Drawer, Review, and browser-coverage failures are
resolved in local source. The exact Cloudflare deployment and deployed
walkthrough remain open. Full-window phone captures fit but their internal UI
text remains too small to serve as detailed phone proof without a focused
derivative or loop.

Release decision remains `NOT VERIFIED` until every row above has proof.

Current implementation evidence:

- The shell morph passes the focused two-project Playwright contract and the
  complete 34-case desktop/mobile browser suite. Exact 1600x1000 visual proof
  is stored under
  `/private/tmp/agentstudio-website-verification/current-working-tree/glass-shell/`
  as `resting-header.png`, `floating-header.png`, and `footer.png`.
- Review source replaced with the 2560x1600 unified-diff capture derived from
  source SHA-256 `9f29a173039e04f1946523e25481f97403ff625a3f77774df4518864677655da`.
  The normalized website asset SHA-256 is
  `fcbb61927148a093b75cdaebae57d6f6cd329338a01e5d5d9bcfc3e21418f9ec`.
- Review desktop proof passes: global Agent Studio sidebar hidden, Review file
  tree visible, unified diff readable, existing Claude start screen visible,
  no double section divider. Evidence:
  `/private/tmp/agentstudio-website-verification/current-working-tree/local-development/1600/review.png`.
- Review phone fit passes but readability remains open: the complete image fits
  without overflow, while internal agent/diff/file-tree text is too small at
  the full-window 390px presentation. Evidence:
  `/private/tmp/agentstudio-website-verification/current-working-tree/local-development/390/review.png`.
- Git context now uses By Repo beside two existing populated Codex and Claude
  panes with branch, changed-line, and ahead/behind status. It contains no
  Review or Files pane and no agent was started, prompted, interrupted, or
  steered. The source SHA-256 is
  `8eab0a39bacb1f86a3e6e8f15855ca08a57f736f323ccf1c100b1bb1013b7e74`;
  the normalized website asset SHA-256 is
  `ca8e6f1b85fb722fedadd7020efd77a93fcdbeb0961ffb0489d1611862a753c4`.
- Pane drawer now hides the global sidebar, retains two existing agent panes,
  and shows one compact attached drawer with real `git status --short
--branch` output. The source SHA-256 is
  `bf30f15de6c1c533db3ee9257c2b09e3d8aed9cde721c36681436c7f8ca33860`;
  the normalized website asset SHA-256 is
  `45bc035952b4bcc0d5784612b2fb467fdcf2473550cf10fac901474c0896b879`.
- Quick Find now hides the global sidebar and shows a real `$ agent` pane/tab
  query over the same two-agent workspace without executing a result. The
  source SHA-256 is
  `5e9a38172895799ae16a2ae436674c99320ebd7b63eeb29cd8cb4e5f0741913d`;
  the normalized website asset SHA-256 is
  `ca1f2ae0bc73a7b17d9373723eda2b419632a3fa395dbf248d728d8fa7239cde`.
- Spacing/divider proof passes in the 30-case desktop/mobile browser suite:
  the showcase-to-details gap is at least 80 pixels and the following CTA has a
  zero-width top border. Current desktop/phone disclosure screenshots are at
  `local-development/1600/feature-details.png` and
  `local-development/390/feature-details.png` under the evidence root above.
- Independent current-diff review found no P0 defects. Accepted open P1 gates:
  Git/PR source cutover, Drawer/Quick Find sidebar recapture, Review phone
  readability, and complete per-capture provenance/no-agent-control receipts.

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

### 2026-08-20 capture and presentation rejection

The later six-image suite is also rejected. Earlier checked capture rows record
historical execution, not current acceptance. The current files show generic
shells, large empty regions, no recognizable coding-agent sessions, weak or
contaminated corner treatment, and an invalid half-size persistence layout.

- [x] Apply the source-pixel, crop, fit, readability, campaign-meaning, and
      two-plane approval gates from the mandatory verification SOP.
- [x] Produce one clean Parallel work calibration frame with real Claude Code
      and Codex sessions before recapturing the other states.
- [ ] Resolve the exact meaning of `Agy`; do not substitute `aider` silently.
- [x] Replace Pane drawer with a useful populated drawer attached to one named
      agent task.
- [x] Replace Quick Find with a native, populated sheet over the same credible
      named-agent workspace.
- [x] Replace Review with a named agent beside a readable changed-files tree
      and populated diff.
- [x] Replace both persistence sources from one matched named-agent restart
      sequence.
- [x] Replace the persistence two-column layout with one full-scale frame at a
      time and an accessible Before/Restored control.
- [ ] Inspect all source corners at 100 percent and all rendered states in local
      development, local production, and the exact Cloudflare deployment.
- [x] Create current desktop, phone, source, and magnified-corner contact sheets.
- [ ] Keep release status `NOT VERIFIED` until every source and rendered state
      passes.

The detailed reasoning and shot directions live in
`tmp/2026-08-20-website-proof-system-rethink.md`.

Current recovery evidence:

- Parallel work is a provisional calibration candidate, not final campaign
  acceptance. The fresh 2560x1600 source shows real routed Codex and Claude Code
  sessions doing separate read-only work, preserves native alpha-zero corners,
  and is normalized to sRGB. The 1600px website render is structurally clean,
  but the Codex identity and agent output still need an owner-level readability
  decision at final scale.
- Quick Find passes the current source and 1600px render review. It uses the
  real `$ agent` pane scope over the same Codex and Claude Code workspace. The
  full-window region capture preserves the native sheet and background pixels,
  uses the matching window alpha boundary, and has no white corner wedges.
- The first Pane drawer rehearsal was rejected because two drawer children
  competed for focus. The accepted replacement closes the redundant child and
  shows one populated Git file-status drawer attached to the active task, with
  the Codex and Claude Code work visible behind it.
- Review shows the real CI workflow diff and Changed Files tree beside Claude
  Code in the same `fix/sidebar-grid-alignment` worktree with PR #313 visible.
- `pnpm --dir web run audit:captures` now passes all six sources and is part of
  the regular `check` chain. It decodes every PNG, requires the canonical sRGB
  chunk, rejects embedded non-canonical ICC profiles, and asserts alpha zero at
  all four native-window corners.
- The persistence website component now shows one complete full-width frame at
  a time through an accessible Before/Restored control. The matched clean
  sequence used PID 23948 before close and PID 31000 after relaunch with the
  same isolated data root. The same five tabs, All Panes grouping, Review file,
  Claude Code worktree, PR #313, and terminal session returned.
- Local production proof lives under
  `/private/tmp/agentstudio-website-verification/working-tree/`. All five states
  were clicked at 1600x1000 and 390x844. Single-image panels measured
  1012x632.5 CSS pixels with no unused panel area. Persistence measured
  1012x680.5 with one 1012x632.5 visible image plus the 48px state control.
  Site-origin console warnings and errors were empty. Contact sheets cover all
  desktop states, phone states, six full-resolution sources, and all four
  magnified corners of every source.

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

### Owner visual corrections after live review

- [x] Replace the purple selector fill with Ghostty charcoal and retain only
      the blue active rail.
- [x] Remove the horizontal gap between the selector rail and product image.
- [x] Preserve screenshot alpha so rounded capture corners never flatten white.
- [x] Apply one deliberate 40/80/40 content, section, and content spacing rhythm.
- [x] Keep Homebrew installation only in the hero.
- [x] Put one official-mark GitHub button in the closing lockup.
- [x] Prove the footer shows the Agent Studio icon at left and visible GitHub/X
      icons aligned at the far right.
- [x] Re-run desktop/mobile screenshots, interaction checks, Cloudflare build,
      deployment, and live verification before closing these corrections.

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
- Live owner-correction proof (2026-08-20): Cloudflare version
  `7bdfb2f8-9b46-462e-8774-24654ee4f98d` preserves the 40/80/40 desktop and
  32/64/32 phone rhythm, charcoal selection, edge-to-edge image geometry, and
  alpha PNG corners. Brave Shields had hidden the conventional
  `footer-socials` wrapper only on the remote origin; renaming it to the neutral
  `footer-profile-links` wrapper and using the plain accessibility label
  `Shravan Sunder profile links` removes that cosmetic-filter collision. Final
  remote Brave proof shows both 18x18 GitHub/X footer icons aligned right, one
  hero install control, one closing GitHub button, no document overflow, and
  zero site-origin console warnings or errors.

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
