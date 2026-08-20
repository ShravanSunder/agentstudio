# Final Agent Studio website review packet

## Assignment

Independently review the current Agent Studio marketing website and all six
product images. Return `SHIP` only when every required row in the shared rubric
passes. One failed required row returns `NO-SHIP`.

This is a read-only review. Do not edit files, request or run terminal/shell
commands, operate apps, or infer product behavior from roadmap text. Use only
direct file-read, image-read, find, and text-search tools. A terminal request
invalidates the receipt even when the permission request is denied.

## Required instruction coverage

Read the complete project-local copy skill before judging any visible copy:

`web/.agents/skills/ai-copywriter/SKILL.md`

The current file has 544 lines. Your receipt must state your actual complete
coverage as `544/544` through the current EOF. If your observed line count is
different, report the observed `N/N`; never copy the expected count without
reading the file. Missing complete coverage invalidates the review.

Read the complete shared rubric:

`docs/wip/communications/2026-08-18-website-visual-acceptance-rubric.md`

## Current source and evidence

- Website worktree HEAD: `8fd35de2c7df7f3f7841e81ecdb577ebb09a7f9a`
- App source reviewed for feature claims:
  `agent-studio.fix-sidebar-grid-alignment` at
  `2b0ff02d47b447ee67393c42b2a02a65894d3a36`
- Capture bundle: `com.agentstudio.app.debug.dh4u3`
- Capture executable SHA-256:
  `6f53124fb6e8575e69cc0b1ce59aa1701855ae892754e72d9495eb67ce704ff4`
- All website capture dimensions: 2560x1600 pixels from 1280x800 point windows
- Website capture manifest:
  `web/src/content/website-capture-manifest.ts`
- Visible copy owner: `web/src/marketing-copy.ts`
- Interactive product plate:
  `web/src/product-plate/InteractiveProductPlate.astro`
- Page styling: `web/src/styles/global.css`
- Current WIP and detailed capture receipts:
  `docs/wip/2026-08-18-marketing-site-visual-copy-remediation.md`
- Source-master and processed six-image contact sheets:
  `/Users/shravansunder/Documents/dev/project-media/agent-studio-media/assets/website-product-stills/outputs/contact-sheet-sources.png`
  `/Users/shravansunder/Documents/dev/project-media/agent-studio-media/assets/website-product-stills/outputs/contact-sheet-website.png`
- Current production screenshots with no Astro developer toolbar:
  `/private/tmp/agentstudio-site-production-1440.png`
  `/private/tmp/agentstudio-site-production-1600.png`
  `/private/tmp/agentstudio-site-production-390.png`
- Six full-resolution website PNGs:
  `web/src/assets/captures/`

## Proven gates

- Oxfmt: 23 files clean
- Type-aware Oxlint: zero findings
- Astro check: 0 errors, 0 warnings, 0 hints across 25 files
- Capture verifier: 6 assets at 2560x1600 with matching SHA-256
- Vitest: 2 files, 9 tests passed
- Playwright: 6 desktop/mobile tests passed
- Static Astro build: 1 page built successfully
- Product-plate image fit: full uncropped 16:10 image with balanced panel
  insets at 1440px (21.0px top / 20.5px bottom), 1600px (20.8px top /
  19.2px bottom), and 390px (8.8px top / 7.2px bottom)
- Production console inspection at 1440px, 1600px, and 390px: zero
  site-origin errors or warnings, no Astro toolbar, and no document overflow
- Pane Drawer authority: the current `pane-drawer.png` is the owner-accepted
  native app treatment (native dimming plus the bright drawer); it is not a
  marketing overlay and must not be rejected merely for using the app's native
  drawer geometry
- HyperFrames upgraded from 0.8.2 to 0.8.4
- HyperFrames 0.8.4 check: zero lint, runtime, layout, motion, and contrast findings
- HyperFrames exports are byte-identical to all six accepted masters

## Review questions

1. Does the page satisfy every required structure, art-direction, copy, and
   interaction row in the rubric?
2. Do all six images read as one campaign at full resolution and in the live
   product plate?
3. Does each image prove its named feature with real, readable product state?
4. Are there any filler phrases, unsupported claims, jargon strings, or image
   descriptions that conflict with the visible evidence?
5. Does the desktop page feel deliberate rather than template-like?
6. Does the phone composition remain readable without horizontal document
   overflow?

## Required receipt

Return:

- reviewer identity, provider, exact accepted model id, and mode/effort;
- assignment id;
- copy-skill coverage `N/N` and rubric coverage `N/N`;
- evidence inspected;
- `SHIP` or `NO-SHIP`;
- only material failed rubric rows, each with file/evidence anchors and a
  concrete remediation;
- any unverified claim that prevented a verdict.

Do not suggest optional redesigns in a `SHIP` receipt. Do not award `SHIP` when
required evidence was inaccessible.
