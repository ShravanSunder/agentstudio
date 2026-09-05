# Production website quality review

Status: focused fixes verified in [draft PR #326](https://github.com/ShravanSunder/agentstudio/pull/326).
Whole campaign not accepted or deployed.

## Scope

Inspect https://getagentstudio.dev/ in Chrome for responsive layout defects,
media alignment, palette inconsistency, and repetitive or vague copy. Preserve
the approved design system and product facts. Deliver focused fixes in a PR.

## Observations

- At the narrower desktop viewport with DevTools docked (Chrome reported
  1144 × 1017), the slideshow's selector rail is taller than its image. The
  image is top-aligned, leaving a large unbalanced gap below it.
- At 390 × 844, the slideshow changes height substantially between the wide
  Watch folders/Command bar images and portrait Parallel agents/Files images.
  The following section jumps. All states need inspection before selecting
  a remedy that preserves readable, uncropped product evidence.
- The drawer description repeats its summary: both say related tools stay
  attached to their task.
- Current blue is the shared #89B4FA brand token. No palette replacement is
  justified by the initial inspection.
- At 320px the hero's forced non-wrapping lines clip "agents" and "nothing"
  at the right edge. The section's overflow hiding conceals the excess text.
- First selection of some uncached PNGs briefly shows an empty glass panel
  before the image appears. This was observed in production, not measured as
  a network-performance benchmark.
- The phone Saved layout/Pane Zoom comparison emphasizes a toolbar label and
  cropped terminal text rather than demonstrating the layout change. It
  needs a purpose-made media replacement, not additional CSS cropping.

## Acceptance

Media must remain uncropped and vertically centered when its column is taller.
Compact title, image, and caption remain separate surfaces. Any spacing fix
uses existing Tailwind utilities and component ownership. Copy retains shipped
facts while removing repetition. Check every affected state on desktop and
phone, then independent review and appropriate automated checks.

## Work

- [x] Open production in Chrome; inspect initial desktop and phone states.
- [x] Inspect all five production slideshow states at 390px and 1600px;
  inspect supporting rows, both layout-toggle states on phone, and footer.
  Inspect 320px hero and intermediate desktop media alignment.
- [x] Confirm bounded fixes from current source and record acceptance criteria.
- [x] Implement and inspect local results: balanced phone headline wrapping,
  vertical image centering, and non-repetitive drawer copy.
- [x] Independent visual/copy assessment of the changed headline, centered
  image, and drawer wording; no new defect found in supplied evidence.
- [ ] Full implementation/release readiness: aggregate check is blocked;
  full release matrix and formal implementation-review coverage remain open.
- [x] Run required checks; record unrelated blocker below.
- [x] Commit, push, and create draft PR #326 with evidence. Implementation
  checkpoint: `5d29af186`.

## Fixes and proof

Hero uses existing Tailwind phone variants to allow balanced wrapping. The
desktop line composition and approved wording remain unchanged. Slideshow
media uses grid alignment in its owning image column. Images retain intrinsic
size/aspect ratio, with no crop, stretching, or replacement asset. Compact
title, image, and caption surfaces remain separate.

Drawer copy is now: "Give each task a main pane. Keep its related terminals and
tools together in an attached drawer." README's pane/drawer section supplies
both facts. The independent reviewer read all 544 lines of the pinned
copywriter skill and confirmed fact preservation and removal of repetition.

The permanent browser regression observes all five selected images at 320,
390, 900, 1144, 1280, 1440, and 1600px. It checks actual text bounds rather than
document overflow alone, plus loaded media, page overflow, and desktop image
centering. It failed on the original 320px headline, then passed after the fix.
Sequential actions are intentional because one browser page owns viewport and
selection; the lint exception is scoped to that stateful loop.

Manual Chrome proof includes production 390px/1600px all-state walkthroughs,
the 320px before/after hero, local 1144px all-state centering, and local
1600px/390px drawer copy. Device-toolbar scaling is an inspection limitation;
exact viewport geometry is additionally checked by the browser regression.

Private local evidence directory:
`/private/tmp/agentstudio-website-quality-2026-09-04/`.
Screenshots: `production-320-hero.png`, `local-320-hero.png`,
`local-1144-watch-folder.png`, `local-1600-drawer.png`, `local-390-drawer.png`.
Independent visual receipt: `visual-only-result.md`.

The first reviewer strayed beyond its read-only visual packet into test
execution and was stopped. Its output is not accepted review evidence. The
replacement assessment ran with read-only enforcement from an isolated
directory and returned only the requested screenshot/copy findings.

## Palette findings

The shared palette remains unchanged. Calculated opaque-token contrast:
primary/canvas 6.26:1; muted/canvas 7.82:1; faint/canvas 5.08:1;
button ink/primary 8.31:1. These calculations do not certify every translucent
glass combination. No specific palette defect was established in this pass.

## Validation

- Website check: exit 0; 53 unit tests and 22 browser tests pass; capture
  verification and pixel audit pass; strict Astro check passes.
- Final lint and format checks: exit 0, zero website warnings/errors.
- Production build: exit 0; seven static pages and player contract verified.
- Cloudflare build, discovery verification, and prebuilt dry run: exit 0.
  Dry run read 90 assets; no deployment performed.
- Repository aggregate `mise run test`: exit 1 during BridgeWeb integration
  vendor verification. Missing old temporary worktree directories and stale
  shared Ghostty resources block the prerequisite. Swift lint and architecture
  checks passed; 1,764 BridgeWeb unit tests passed before the blocker. No
  unrelated infrastructure was modified.

Logs live under `tmp/2026-09-04-website-quality/` in this worktree.

## Remaining quality work

- Compose consistent phone media dimensions without shrinking readable
  product proof or adding large empty bands. Current mixed aspect ratios
  still make the section below jump when switching slides.
- Replace the weak layout-toggle phone still with accepted behavioral proof.
- Investigate cold-image switching with transfer/decode measurements before
  choosing preload or delivery-format changes.
- Owner review of the complete campaign and release matrix remains required.

These findings are not claimed fixed by this PR. This checkpoint preserves
the existing visual direction while correcting independently provable defects.
