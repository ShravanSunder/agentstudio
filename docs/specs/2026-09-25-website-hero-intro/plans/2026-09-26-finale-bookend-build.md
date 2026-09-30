# Plan: the finale "bookend" with a split-pill CTA (slice 12)

Author: the orchestrator. **Owner-approved 2026-09-26:** concept A "bookend", round 2, **V1 split pill** ("let's do V1"). The visual reference is `/private/tmp/agentstudio-finale-storyboard/` (the round-2 V1 frames and videos, when present; `inject-finale.js` is the reference implementation of the motion). It builds on 10j (the rail ends at the CTA) and replaces the 10b pulse.

## Final CTA section (hard cutover of `FinalGitHubCallToAction.astro`)
- **Content, top to bottom:**
  - the app icon in the bookend (below);
  - "Agent Studio" (the existing display title);
  - **the split pill**;
  - "Requires macOS 26 or later." (small, faint).
- **Remove:** the sub-copy line, the two-line install code box, the "Install with Homebrew" eyebrow (never shipped), the mono tagline, and the old standalone Star button.
- **The split pill:** one pill in the `.floating-glass-material` class, with a full radius and two halves split by a 1px divider.
  - **Left half:** `★ Star on GitHub`, the primary treatment, linking to `marketingCopy.githubUrl` (the repository).
  - **Right half:** `⧉ Copy install`, a recreation-kit copy icon. It uses the existing install-command controller logic to copy `installCommandText` (both brew lines), shows "Copied ✓" for 2s, and exposes an aria-live status plus an aria-label from `marketingCopy`.
  - All labels live in `marketingCopy`.
  - Phone: one row, with the labels shortening to `★ Star │ ⧉ Copy` only if the row can't fit (measured, no wrap).
- **The rail end is a git node:** the rail's final branch (10j) ends at the **pill's left edge, vertical centre**, and the end is drawn as the rail's terminal merge node (a ring in the incoming lane colour, an inner dot in the mainline colour, a halo pulsing once), touching the pill's edge. Declare the pill as the rail target in markup (DOM contract; no id special cases). Nothing is drawn below it.

## The bookend motion (plays once when the section enters view; reduced motion shows the final state)
Beats from the storyboard, ≈2.4s:
| t | beat |
|---|---|
| 0.00 | A mini terminal card (the hero window's glass style, `>_`) stands in front of the fanned icon stack (−9°/−6°/−3° steps, as in the hero) |
| 0.35 | The rail's branch reaches the git node at the pill (on the existing reveal) |
| 0.55 | **The border trace:** a bright segment in the branch colour runs once around the pill outline, clockwise from the node (0.6s), leaving the border lit at 60% |
| 0.95 | The ★ draws (stroke-dash 0.3s), then fills (0.15s) |
| 1.40 | The terminal card folds into the stack, and the fan settles into the exact app-icon composition (0.8s, `power3.inOut`); the final frame shows the real `app-logo-transparent.svg` |
| 2.40 | Stillness |
- It triggers on the existing `topology-end-reached` event (10b's event); drop 10b's ring pulse (replaced by the trace).
- It follows the scene rules: a paused timeline owned by a small host (the same pattern as `hero-intro-playback.ts`), no layout shift (all elements pre-sized in the settled markup), and a settle on resize or skip.

## Tests (TDD; no time waits)
- The split pill's structure and labels come from marketingCopy, and the Star href is the repository.
- The copy half writes the exact two-line text and shows the "Copied" status.
- The end node touches the pill's left edge (±1px) at 390, 1280 and 1920, with ring/dot sizes equal to the rail's merge-node vocabulary, and nothing below it.
- Reaching the end triggers the bookend once; the final state has the app logo visible, the trace settled and the ★ filled; reduced motion shows the final state with no timeline.
- There's no layout shift during the bookend (the section height and footer top stay constant).
- One row on phone.
- CTA copy contract tests are updated for the removed elements.

## Proof
Production CDP frames at the beat times (1600 and 390) paired against the storyboard V1 frames; `finale-1600.mp4` / `finale-390.mp4` at 60 fps. Gates: 3 consecutive green full checks (checking load with `uptime` first; wait if the 1-minute load is > 40) + build. Commit 'Close the page with a bookend and split-pill call to action', append 'slice12 done' to STATUS.md, and don't push.
