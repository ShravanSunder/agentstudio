# Plan: the step-line countdown ring, the commit hop, one blue, and the finale alignment (slice 13)

Author: the orchestrator.

**Owner decisions (2026-09-27):**
- the bare line (B), "bare line looks better";
- the countdown ring on the active dot (S2), "this one is the best";
- one blue, "the colour is not consistent, blue is fine";
- the commit hop (T4), "I like this best";
- the dwell is "x ms or as long as the video or animation is";
- the hop animation and travel take "250 ms or less, we control it".

**Orchestrator defaults the owner didn't contest:** the lanes feeding a step line are blue; a click jumps and shows a paused state.

**Owner, the finale:** "maybe all left align?" and "icon and agent studio in one line, then buttons?"

The live reference is the round-2 mock page (the orchestrator has it; the behaviour is fully specified below). Every rule here is binding; a question comes back to the orchestrator with evidence.

## 13a. Hard cutover: remove the capsule variant (A)
- Delete the query switch in `web/src/chapters/ChapterSurface.astro` (lines ~89–93: `stepControlVariant` and `root.dataset["stepControlVariant"]`).
- Delete the "TEMPORARY A/B" comment and every `[data-step-control-variant="capsule"]` rule in `ChapterStepLine.astro` and `web/src/styles/global.css` (~line 86).
- Delete the `.chapter-step-active-label__dot` element and its CSS.
- Delete `tests/step-control-variant-browser-command.ts` and `tests/step-control-variant.browser.test.ts`. Move any assertion from them that still describes the bare line (B) into the chapter step-controller browser test, and keep that assertion.
- Afterwards, `rg -n "capsule|stepControlVariant|step-control-variant" web/src web/tests` returns nothing.

## 13b. One blue from the fork to the line
- **Lanes feeding a step line:** every worktree lane that carries an attach branch into a step line (an anchor with `stepLine`) takes the `main` accent. Derive this from the DOM contract / anchor data in lane planning (`topology-lane-planning.ts`); no chapter-id special cases. Lanes that feed no step line keep `worktreeAccents`.
- **The attach branch into a step line** is one solid `main`-accent stroke from its fork to the step line: no gradient start (the "accent of the lane the port leaves, where its gradient starts" field isn't used for step-line targets). The grey vibrancy and opacity masks keep working as now (colour to 75%, grey to 90%, gone by 95%).
- **The step line itself** is unchanged in colour:
  - the passed segment and the current dot are `--color-primary`;
  - the track and the drop-turn branch are primary at 46%.
- **Don't add a fork node.** (The mock showed a small ring at the fork. Add it only if it satisfies the existing one-dot-per-row and rail-node guard tests without changing them; otherwise leave it out and say so in RESULT.md.)

## 13c. The countdown ring (S2)
**Markup (pre-sized, no layout shift):**
- One ring element in `ChapterStepLine.astro`: an SVG with a track circle and a progress circle, positioned by the controller at the current dot's centre (the same measured centre `renderSelectedStep` already computes).
- Radius 11px, stroke 2px. Track `rgb(255 255 255 / 8%)`; progress `--color-primary`, round cap, starting at 12 o'clock and running clockwise.
- The existing 13px current-dot styling stays inside it.
- Phone (< 38.75rem): radius 10px.

**Dwell, the owner's "as long as the video or animation is":**
- Add a pure, unit-tested function in a new module `web/src/chapters/chapter-step-dwell.ts`:
  - `computeStepDwellSeconds(props: { labelTimes: readonly number[]; timelineDuration: number; proofSeconds: number; replayDelaySeconds: number }): readonly number[]`
- **Step i < last:** `labelTimes[i+1] − labelTimes[i]`.
- **The last step:** `(timelineDuration − labelTimes[last]) + proofSeconds + replayDelaySeconds`.
  - `proofSeconds` is the proof video's real `duration` when the surface has a proof video with loaded metadata, and 0 otherwise.
  - The replay delay is `scene-playback.ts`'s `replayDelayMs / 1000`. Export that constant rather than duplicating it.
- **No minimum-dwell floor:** the scene's own timing wins. (This is a recorded decision; don't hold the timeline.)

**The progress signal:** extend the scene → chapter contract in `chapter-step-events.ts`. Add one event, `scene-step-timing`, dispatched on the scene root and bubbling to the chapter root. Its detail:
- `{ stepId, dwellSeconds, elapsedSeconds, running: boolean }`.

`scene-playback.ts` dispatches it:
- when a step is reached (`reportStep`), and on every phase change (`playing`, `paused`, `awaiting-replay`, `settled`);
- on proof-video `play`/`pause`/`loadedmetadata`, and when the replay timer starts.

`elapsedSeconds` is exact: `timeline.time() − labelTimes[i]`, or for the last step during the proof beat, the time since the timeline completed (the video `currentTime`, plus the replay timer's elapsed part). No polling.

**Ring animation:** the controller drives the ring with one Web Animation on the progress circle's `stroke-dashoffset`, with duration `dwellSeconds`. On each timing event it sets `currentTime = elapsedSeconds`, then plays it if `running`, otherwise pauses it. It never drives the ring with its own timer.

**Hidden when nothing will switch:**
- reduced motion, a settled or unregistered scene, or a failed build (`running` is false with no timeline);
- chapters without a scene.

## 13d. A click jumps and shows a paused state
- **Clicking a non-current step:** keeps today's behaviour (`chapter-step-requested` → the scene seeks and becomes `manual-pause`).
- **The paused state:** the step line gets `data-step-playback="paused"`. The ring freezes at its fraction at 50% opacity, and a small pause glyph (❚❚, 9px, `rgb(155 161 173 / 80%)`) sits 16px above the current dot.
- **Clicking the current step while paused:** resumes. Dispatch a new `chapter-step-resume-requested` event on the glass; `scene-playback.ts` sets intent `auto` and plays from the current time. The keyboard path is Enter/Space on the selected tab.
- **Keep the scroll-away reset:** scrolling away still resets `manual-pause` to `auto` (the existing rule).
- **Keep the stage-corner pause toggle** (WCAG 2.2.2). Its state stays consistent with the line.

## 13e. The commit hop (T4), ≤ 250 ms in total, a fixed duration we own
On every step change (autoplay, click, keyboard, and the loop wrap from the last step to the first):
| t (ms) | motion |
|---|---|
| 0–160 | the ring (track + progress + current-dot styling) **travels** along the line from the old dot centre to the new one (`translateX`, ease-in-out). The loop wrap travels right-to-left in the same 160 ms |
| 0–120 | the old label and its drop-turn branch fold back into the old dot (the label scales 1 → 0.2 with its origin at the old dot, fading out; the branch's stroke-dash retracts) |
| 120–220 | the new drop-turn branch draws from the new dot (stroke-dash) |
| 150–250 | the new label unfolds from the branch end (scale 0.55 → 1 with its origin at its left edge, fading in) |
- This replaces today's 150/240/390 ms fade.
- Use Web Animations only: no GSAP on the step line and no timers.
- **The ring countdown restarts at 0 for the new step when the travel lands** (160 ms).
- **Reduced motion:** no hop; the new state appears instantly.
- **Keep:** zero layout shift, and the no-sharp-corners guard for the drop-turn path.

**The preview on a click jump:** a crossfade after the ring lands, 160–250 ms.
- Before the seek, clone the scene root's current frame (`cloneNode(true)`, `aria-hidden="true"`, `inert`, `pointer-events: none`, absolutely over the live scene).
- Seek the live scene, then fade the clone's opacity 1 → 0 from 160 to 250 ms, and remove it on `finished`.
- If the proof layer was showing, keep today's `instant` proof drop.
- Autoplay step changes never crossfade, because the scene's own animation carries the picture.
- Reduced motion: no clone.

## 13f. Finale: everything left-aligned, with the icon and the title on one line (owner 2026-09-27: "maybe all left align?", "icon and agent studio in one line, then buttons?")
**Layout, top to bottom, all sharing ONE left edge (the split pill's left edge, where the rail's final node lands):**
1. **One row:** the bookend icon stage, then the "Agent Studio" title, vertically centred to each other.
   - Scale the icon stage so its height equals the title's line box.
   - The gap is 0.25 em of the title size.
   - The row never wraps at ≥ 360px wide. Below that, shrink the title with the existing clamp before wrapping.
2. **The split pill** `[★ Star on GitHub │ ⧉ Copy install]`, unchanged.
3. **"Requires macOS 26 or later."**

**Also:**
- Nothing centres at any width.
- The bookend motion (the card folds into the icon, the border trace, the ★ fill) plays in the resized stage with the same beats; its final frame is the real app logo at the new size.
- Zero layout shift during the bookend.
- The rail end node still touches the pill's left edge (±1px).
- The footer below the rule is unchanged.

## Tests (TDD: see each fail first; exact signals only, no polling, no raised timeouts)
- **Unit:** `computeStepDwellSeconds`, covering the three-step case (labels 0/2.7/4.5, duration 8.9, proof 0, delay 3 → [2.7, 1.8, 7.4]) and a proof-video case.
- **Browser:**
  - the capsule is gone (13a's `rg` + `?steps=capsule` renders the bare line);
  - the attach branch into each step line and its lane compute to the main accent, with no gradient reference;
  - after the scene playback control seeks mid-step, the ring's animation `currentTime / duration` equals the expected fraction (±0.02);
  - clicking a step gives `data-step-playback="paused"` with the ring animation paused and the glyph visible; clicking the current step resumes (the scene state becomes `playing`);
  - on a step change, every animation `document.getAnimations()` reports on the step line ends by 250 ms;
  - the ring's travel keyframes run from the old dot centre to the new one, with the loop wrap going right-to-left;
  - a click-jump creates exactly one clone, which is removed after its animation's `finished`;
  - reduced motion creates no animations and hides the ring;
  - zero layout shift across a hop;
  - the finale icon, title, pill and requirement note share a left edge (±1px) at 390, 1280 and 1920;
  - the icon and the title are on one row (their vertical centres within 2px), with the icon height equal to the title line box (±2px);
  - the rail node touches the pill;
  - the bookend final state shows the logo.
- **Keep existing guards green:** the no-sharp-corners and rail-node vocabulary guards, the chapter autoplay tests, and the scene proof tests.

## Proof
- **CDP frames of a hop:** 0/80/160/250 ms at 1600 and 390, for a forward step and the loop wrap.
- **Ring:** at mid-step and in the paused state.
- **The colour join:** crops for all three chapters at 1600.
- **Finale:** at 390, 1280 and 1920.
- **Gates:** focused tests while building. Then 3 consecutive green full `pnpm --dir web run check` runs plus `build`, checking `uptime` first and waiting while the 1-minute load is > 40.
- **Finish:** commit 'Countdown ring and commit hop on the step line; one blue; left-aligned finale'; append 'slice13 done' to STATUS.md; RESULT.md 'Slice 13'; don't push.
