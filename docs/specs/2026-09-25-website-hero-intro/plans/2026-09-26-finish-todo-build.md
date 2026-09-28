# Plan: finish the TODO before merge (slice 10), after slice 9

Author: the orchestrator. The owner (2026-09-26): "I want to see the whole thing with the tree changes and the entire todo list done… use the workhorses to finish… the trio for all images: render (HTML), then real image or video. Real *new* videos come after merge and deploy, coordinated with a media organizer." Branch `website/hero-intro`. Do the sub-slices in order, one commit each, TDD, and no time waits (follow `agent-studio.ci-improvements/tmp/ci-speed/2026-09-26-good-test-criteria.md`).

## 10a. The rail ends at the vertical centre of the last glass (the held slice 3.2, now released)
Implement slice 3.2 exactly as written in `2026-09-25-rail-and-chapter-steps-build.md` §3.2, adapted to the current modules:
- `topology-end-geometry.ts` returns the last chapter glass's `(top + bottom) / 2`.
- `topology-lane-planning.ts` staircases the open lanes, so the innermost lane merges into the mainline **at the final row** (one column per merge, one dot per row).
- The final node is a merge dot with `terminal: true`: the ring and core plus the terminal halo, pulsing once on reveal.
- Nothing is drawn below the final node.
- Delete `TopologyEndMeasurement`, `measureEnd`, `railEndSectionAttribute`, `railEndMarkAttribute` and their use in `FinalGitHubCallToAction.astro` (hard cutover).
- Rewrite `topology-end*.ts` tests for this rule at 390, 1280 and 1920.

## 10b. The final CTA pulses when the rail finishes
In `FinalGitHubCallToAction.astro`, add a primary **"Star on GitHub"** button (link: `marketingCopy.socialLinks` GitHub URL; the label goes in `marketingCopy`, not inline) above the install box, using the site's primary-button style.
- When the rail's final merge node is revealed (the reveal module already knows it: dispatch an `topology-end-reached` event from `topology-scroll-reveal.ts` once, when the end node becomes revealed), the button plays **one** pulse: a ring expanding from its border, 900ms, primary blue fading out. It pulses once per page view, never loops, and doesn't pulse under reduced motion.
- Test (browser): scrolling to the end dispatches the event once, and the button gains `data-pulsed`. Clicking it navigates to the GitHub URL (assert the href). Under reduced motion there's no animation.

## 10c. The trio beat for every chapter: rendered HTML scene, then a real image or video
Every chapter's stage plays **rendered HTML scene → real proof**. Three chapters already do this (the scene plus `proofImage`). Add the missing two:
- **"Review" (today a still only):**
  - New scene module `chapter-review`, following `motion-scenes/scenes/chapter-many-agents/` exactly: a fixture, the scene, an Astro file, the registry, the scene-bundle build, the scene-contract rules (no rAF/random/Date, seeded).
  - Content: a recreation-kit `AppWindow` with a `DiffView`: the diff lines appear, one changed line highlights, and a comment thread opens on that line with a short Markdown comment, like the shipped annotations feature.
  - Then the proof: the real `review.png` (phone: `review-phone.png`).
  - The stage kind becomes `scene` with `proofImage`.
- **"Come back" (today a video only):**
  - New scene `chapter-come-back`: an `AppWindow` with two panes running. The window "closes" (it scales and fades), a short beat passes, and it reopens with the same panes and a terminal process still running (a counter continues).
  - Then the proof: the real `session-restore.mp4`.
  - Extend the stage union with `kind: "scene"` + `proofVideo` (a typed discriminated union; the proof layer plays the video as the proof beat, keeping today's video controls).
  - A hard cutover of the old video-only stage for this chapter.
- The chapters' step pills stay as they are (steps ≠ beats). The fill tracks steps. For single-step chapters, the pill is absent as today.
- Tests: scene module unit/contract tests like the existing scenes; a browser test that each chapter plays the scene and then shows its proof (image or video), and that the proof holds the stage between loops.

## 10d. CI runner compatibility
The marketing CI job moves to Ubuntu with `CHROME_BIN` set. In `web/vitest.config.ts`, launch Playwright with `executablePath: process.env.CHROME_BIN` when it's set, and otherwise `channel: "chrome"` as today. Same for any test server or global setup that launches Chrome. There are no other CI edits (the CI session owns the workflow files).

## 10e. Merge main, and local proof
Merge `origin/main` into `website/hero-intro` (read both sides of any conflict; web/ changes should be minimal). Then run the **full website gates 3× green** (`pnpm --dir web run check` + `build`). **Stop there and report.** The orchestrator runs the repo-wide `mise run test` itself for the PR's local proof.

## Proof and report
Production-build CDP frames:
- the page bottom at 390, 1280 and 1920 (the rail end plus the CTA before and after the pulse);
- the review and come-back chapters at their scene and proof beats (1600 and 390);
- a short video of scrolling to the end at 1600 (the pulse).

Update RESULT.md (`Slice 10a…10e`), append 'slice10 done' to STATUS.md, and don't push.

## 10h. Step control, "git branch" design (OWNER-CONFIRMED 2026-09-26: option A, the label is an offshoot from the active dot using the same rail curve)
The owner's direction, with their sketch: "the outside git connects; the text should move and be after the branch, using the git branch curve."
```
 rail ────●─────────●─────────◉          ← the rail branch CONTINUES into the step line (no gap, no dot at the join)
                              │
                              ╰── ( Find your way around )   ← a short branch from the ACTIVE dot: down, then the
                                                               rail's corner curve to the right, into a small glass label
```
- **Replace the glass step pill** with: a bare step line drawn with the rail's exact stroke, width and colours, with the steps as commit dots at equal spacing (68px desktop, 22px phone). States: done = filled, current = ring + halo, next = hollow. The segment fill tracks the current step (autoplay and click). No glass behind the dots.
- **The active label:** from the active dot, a branch drops down one short row, then turns right using the **owner's rail corner algorithm** (`full-page-topology-paths.ts`, the same cubic as every rail bend), ending at a small glass label (`.floating-glass-material`, pill radius) that sits **to the right of the active dot**. Only the active step's label shows. On a step change, the old branch and label fade out (150ms), the new branch draws from the new dot (240ms stroke-dash), then the label fades in. Reserve the row's height so nothing moves, and reserve the width so the label never overflows the column (clamp; the label may flip to the left of the dot only if it would overflow, and say so in RESULT.md).
- **The rail connects into the step line at every width:** the chapter's rail branch ends exactly at the step line's left end (desktop: the line sits above the glass; phone: below the glass), with the corner algorithm and no port dot. This **replaces** both the slice-4 pill target and the phone glass-top target for multi-step chapters (hard cutover of that geometry). Single-step chapters keep their current glass targets.
- The real step buttons remain the interactive elements: the dots are the buttons (hit area ≥ 24px, keyboard left/right, aria current), and the label is text, not a second button.
- Remove the old pill-only code and CSS that becomes dead; the shared `.floating-glass-material` stays (the header and the label use it).
- Tests:
  - the branch end equals the step line's left-end point (±1px) at 390, 820, 1024 and 1600;
  - equal dot spacing;
  - the label's left edge sits right of the active dot, and moves with the step;
  - no path intersects any text rect;
  - constant row height across steps;
  - clicks and autoplay move the fill and the label;
  - reduced motion: no draw animation, and the final state shows at once.
- Visual reference: `/private/tmp/agentstudio-pill-arc/frames/*C2b*` and the owner's sketch above. Differences from C2b: the label goes to the right of the active dot, after a down-then-right branch, and the rail connects into the line's start.

## 10i. Scene opening frames pass the media layout audit (a media-lead request, board activity 2113)
The media lead renders our scene bundles for social through HyperFrames, and its layout audit fails on the opening frames. Fix these in the scene modules (the website's own first frames look messy too):
1. **`chapter-find-and-focus` @ t≈0.17s:** the command bar is already visible, semi-transparent, while the panes are still entering; its "sidebar-filter" chip overlaps pane text (9 runs occluded). The command bar must enter only **after** the panes settle. While the bar is open over pane text, set `data-layout-allow-occlusion` on the **covered pane text container** with timeline `set`s on at the bar-open label and off at the bar-close label (HyperFrames reads the flag on the covered text's ancestors).
2. **`chapter-many-agents` @ t≈0.16s:**
   - (a) The first pane's entering text is occluded by the adjacent pane during the entrance. Stagger or clip the pane entrance so the panes never overlap.
   - (b) The sidebar label `agent-studio.sidebar-grouping` is clipped with an ellipsis. It's truthful app truncation, so mark that label element `data-layout-allow-overflow`.
3. **Check the new `chapter-review` and `chapter-come-back`** for the same class of issue in their first ~0.3s: no pane-over-pane or overlay-over-text overlap, and any intended overlay flagged as above during its window only.
4. **Proof:**
   - Run `npx --yes hyperframes@0.8.64 check` against a bundle mount of each of the five scene bundles, following the media repo's example project at `/Users/shravansunder/Documents/dev/project-media/agent-studio-media.production-system/videos/scene-clips/` (read it, don't edit it); all five must pass.
   - If the npx download is blocked in your sandbox, record the exact error, and the orchestrator runs it.
   - Also keep the existing scene tests green.
Snapshots of the failures: `/Users/shravansunder/Documents/dev/project-media/agent-studio-media.production-system/videos/scene-clips/snapshots/{c1-website-lead,c3-website-lead}/`.

## 10j. The rail ends at "Star on GitHub" (owner 2026-09-26; supersedes 10a's end rule)
Owner: "the final one goes to Star on GitHub? … below the last picture looks weird now." Their screenshot shows two problems: the staircase of lane merges beside the last glass, and a Y-split where one lane forks both into the last glass and back into a neighbouring lane.
- **The end target is the final CTA's "Star on GitHub" button:** the mainline continues past the last chapter, down to the CTA, and finishes with one branch (the owner's rail corner curve, one column × one row) into the button's **left edge at its vertical centre**, with no port dot. Nothing is drawn below that branch. Declare the button as a rail target in markup (for example an anchor id `final-cta` with `data-rail-target-edge="left"` via the existing DOM contract). Don't special-case ids in the geometry.
- **Lanes close BELOW the last glass**, not beside it: each open lane merges into its inner neighbour one row at a time in the gap between the last glass's bottom and the CTA (one column per merge, one dot per row), so only the mainline reaches the CTA. The last glass's branch forks from a lane's straight run: **no Y-split** (a node never both merges and branches).
- **The pulse (10b)** fires when the reveal reaches the button branch's end (the existing `topology-end-reached` event now keys off that end).
- **Hard cutover:** remove the last-glass-centre end rule and its merge-ring terminal from 10a; update the topology-end tests to the new end at 390, 1280 and 1920. Include a unit fixture proving there's no Y-split (no node is both a merge target and a branch source in the same row).
- **Vibrancy check:** when scrolled so the CTA is centred, the whole final branch is in the coloured band (above 75%).
- The intro staircase, the scroll reveal (not stepped; the owner decided stepping on scroll is a bad idea) and 10h's step-line connection all stay as specified.

## 10k. Remove the time-coupled waits in web tests (routed from the CI test-quality hunt)
The source list is `/Users/shravansunder/dev/agent-studio-worktrees/test-hunt/tmp/test-hunt/fix/routed-website.md`: 8 accepted P7 findings, each with a recipe. Apply every recipe:
- `vi.waitFor` polling → await the owner's exact signal (a matchMedia change, a MutationObserver on the published attribute or dataset, the clipboard promise, `animation.finished`);
- `waitUntil: "networkidle"` → a DOM-ready navigation plus the exact selector, font or layout readiness signal;
- the header's rAF sampling loop with a 10s timer → the mutation plus `animation.finished`;
- `site-header-browser-global-setup.ts` → keep the ready/exit listeners, with no test-owned timers: the 5s timer may already be gone since slice 9, so verify; and replace the 2s SIGKILL delay race with awaiting the child's exit after SIGTERM, relying on the runner's hang bound.
Keep every test's claim identical (the coverage is kept, not traded; see `agent-studio.ci-improvements/tmp/ci-speed/2026-09-26-good-test-criteria.md`). Proof: `grep -rn "waitFor(\|networkidle\|setTimeout" web/tests` shows none of the listed sites remain (list any intentional survivors with a reason), and 3 consecutive green full checks. Do it after 10j, before 10e. Commit 'Await exact signals instead of polling in website tests'.

## 10m. Rail curve fixes plus the step-control A/B comparison (owner 2026-09-26, PRIORITY: do it before 11d)
1. **The step offshoot curves the wrong way.** `chapter-step-controller.ts:181` uses `localForkPath` (horizontal first, then down, a ┐ shape). It must be a **drop then turn** (└ shape): from the active dot's centre, go straight DOWN, then the rail's corner curve turns RIGHT into the label (the same cubic proportions as `localForkPath` 0.9/0.08/0.1, oriented vertical-then-horizontal; add a named `localDropTurnPath` in `full-page-topology-paths.ts` rather than inlining). The offshoot leaves the dot vertically, with no horizontal lead-out along the step line.
2. **The final branch into the split pill** (owner: "make Star longer or skip one column, but not stepping all of them"): today it's a long flat run then a sharp jog. Make it:
   - (a) **widen the Star half** of the split pill so the pill's left edge sits closer to the rail (keep the pill centred as a whole only if the proportions still look right; otherwise left-align the pill group with the section content column so its left edge is within about 2 rail columns of the mainline);
   - (b) the final branch forks from the mainline/lane with **one corner bend that may span two columns** (the single allowed "skip one column" exception, the final CTA branch only) and runs straight into the node;
   - (c) the node's y sits exactly **on a row**, level with the pill's centre;
   - (d) **no right-angle jogs** anywhere.
3. **Guard test (new, permanent):** a unit or browser test that parses every rail and step path `d` and fails on any sharp corner (an `L`/`H`/`V` segment meeting another at ~90° without a cubic between them). Every bend must be the owner's cubic. The allowed flat runs are the straight lane and the final approach.
4. **Step-control A/B, "see it for real" (TEMPORARY, remove the loser after the owner picks):**
   - **B (the default):** the bare step line with the fixed └ offshoot into the small glass label.
   - **A:** one larger glass capsule (`.floating-glass-material`, full radius) containing the dot line AND the label area. The offshoot drops from the active dot and turns right into the label text, which inside the capsule gets **its own small dot before the text** (for example `● Files`).
   - A is selected by `?steps=capsule` on the URL (read once at load; the data attribute lives on the chapter's steps root).
   - Keep the rail connecting into the line start for both.
   - Mark this in code with a `TEMPORARY A/B` comment and a RESULT.md note so it gets removed as a hard cutover once the owner picks.
Proof: frames at 1600 and 390 for B and A (the `many-agents` and `context-with-task` chapters, the step 1 and step 3 states) plus the final CTA at 1600, 1280 and 390, with the guard test red before and green after. Commit 'Fix rail curve orientation and final CTA branch; add step-control A/B', append 'slice10m done'.
