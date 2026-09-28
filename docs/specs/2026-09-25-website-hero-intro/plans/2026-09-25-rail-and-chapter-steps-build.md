# Plan: rail endings, no ports, chapter step pills, rail vibrancy (slices 3–5)

Author: the orchestrator (main). Branch: `website/hero-intro`, the same PR as slices 1–2. **Status: drafted while the owner is AFK. Coding waits for the owner's go** (their open question is whether code may run ahead of their review of the renders).

The owner-directed changes and their approved renders:
- **Step pill** (round 11): `…/tmp/2026-09-24-intro-storyboard/production-storyboard/frames/C-*.png`, `video/chapter-steps-*.mp4`.
- **Rail** (round 12/12b): `frames/R-*.png`, `video/rail-vibrancy-*.mp4`.
- **Reference implementation:** `production-storyboard/inject-chapters.js` and `inject-rail.js`. Port their behaviour, not their DOM-patching style.

Each section below is marked *confirmed* (the owner said so in chat) or *provisional* (the orchestrator's choice, visible in the render the owner hasn't reviewed yet).

## Mental model
```
chapter-dom-contract.ts ── attribute names shared by chapters and the rail
        │
ChapterSurface.astro ─── [steps root wrapper]
        ├─ ChapterStepPill.astro   (the step list moves here; data-rail-step-pill-target)
        └─ glass (ScrollMaterialSurface; title, stage, step panels)
        │
topology-lab/
  full-page-topology-layout.ts        measure DOM → TopologyPageMeasurement (+ stepPill rect)
  full-page-topology-composition.ts   orchestration only (after the split)
  topology-attach-geometry.ts   NEW   where each branch enters its target (glass | pill)
  topology-lane-planning.ts     NEW   worktree lanes: open, run, staircase-merge to the end
  topology-end-geometry.ts      NEW   the end row = the last glass's vertical centre
  topology-scroll-reveal.ts           per-frame render: fog + current + vibrancy mask
  FullPageTopologyArtwork.astro       SVG: source group, grey <use>, colour <use> under a mask
```
**Why the split comes first:** `full-page-topology-composition.ts` is already **611 lines**, and slices 3 and 4 both grow it. Per the repo's craft rules (over 600 lines is a smell, over 900 means refactor), extract by responsibility before changing behaviour. It's a pure move with identical output, proven by the existing unit and browser suites passing unchanged.

## Slice 3: the rail endings, and no port dots (rail only; no chapter markup changes)
3.0 **Split, no behaviour change** (its own commit):
- Move `attachXFor` and the wide/stacked attach-row search into `topology-attach-geometry.ts` (composition.ts:167–175 and 450–545).
- Move `planWorktreeLanes` and its merge-path helpers into `topology-lane-planning.ts` (199–255, 330–340).
- Move `topologyEndY` into `topology-end-geometry.ts` (262–278).
- Composition keeps `composeFullPageTopology` as the orchestrator.
- Gate: `pnpm --dir web run check`, with zero test edits.

3.1 **No port dots** *(confirmed)*. Hard cutover:
- Delete the `node-port` circle's creation and positioning (layout.ts:236–242, 388–392), its CSS (Artwork.astro:146–172), and `updatePortDraws` / `data-port-drawn` (reveal.ts:118–135).
- Rename `TopologyRoute.portNode` to `targetPoint` (it still records where the path must end), and delete the port-node radius.
- Keep the attach path's final point exactly on the target edge.
- Tests to rewrite:
  - `full-page-topology-layout.test.ts:377–425`: assert the path's last point equals `targetPoint` on the edge.
  - `full-page-topology-layout.browser.test.ts:129–133`, `topology-node-vocabulary-browser-command.ts:48–79` and its test at `:82–95`, and `chapter-surface-browser-command.ts:187–219`: assert that **no** `[data-topology-port-node]` exists, and that the rendered path's end point (from `getPointAtLength(total)`) lies on the target edge within ±1px.

3.2 **The end is the last glass's vertical centre** *(orchestrator's recommendation; the owner asked "end in the centre?", and the render is awaiting the owner's OK)*:
- `topologyEndY` returns `(lastGlass.top + lastGlass.bottom) / 2`, and `page.height − rowUnit` only when there's no glass.
- Hard cutover: delete `TopologyEndMeasurement`, `measureEnd` (layout.ts:137–155), `railEndSectionAttribute` and `railEndMarkAttribute` (chapter-dom-contract.ts:14–18), and their use in `FinalGitHubCallToAction.astro`.
- **Lanes merge down to the end:** `planWorktreeLanes` gets an `endRow` (= `finalRow`) in place of `closeBelowY`. Lanes staircase so the **innermost lane merges into the mainline at `finalRow`** and each outer lane merges one row earlier into its inner neighbour. That keeps one column per merge and one dot per row. The last chapter's attach branch must fork above the first merge row; if a layout can't fit that, the lanes close the old way, and a unit case documents it.
- The **final node** is a merge dot with a new `terminal: true` flag, so `createRowNode` (layout.ts:266–296) renders the merge ring and core **plus** the terminal halo, with a single reveal pulse. With no lanes (phone, one line), the final node is today's `end` kind.
- **Nothing is drawn below the final node**, including the mainline path (the path ends at `finalRow`'s y).
- Tests: rewrite `topology-end-browser-command.ts` and `topology-end.browser.test.ts:15–32`. At 390, 1280 and 1920, the end node's y equals the last glass's centre (±1px); nothing lies below it; with lanes, the final node is a merge with a halo; there's no CTA dependency. Add unit fixtures in `full-page-topology-layout.test.ts` for the staircase (lanes 1–4) and the no-room fallback.

## Slice 4: chapter step pills *(confirmed: a pill above the glass, the floating-header material, the branch into the pill with no dot, the title fixed and the step text switching)*
- **Contract:** `chapter-dom-contract.ts` gets `railStepPillTargetAttribute = "data-rail-step-pill-target"`.
- **Shared material:** extract the floating header's glass material (SiteShell.astro, `.site-header[data-visual-state="floating"]`: gradient, `rgb(30 30 46 / 88%)`, border `rgb(137 180 250 / 38%)`, backdrop blur and saturate, shadows) into **one shared class in `global.css`**. The header's floating state and the pill both use it. There's one source of truth, and a test asserts the pill and the floating header compute the same background, border colour and backdrop-filter.
- **`ChapterStepPill.astro` (new):** a capsule 40px high with a 4px inner padding and a full radius. It holds the moved step buttons: a dot plus a 14px label, `text-ink-faint`. The current segment gets a sliding inner highlight (`rgb(137 180 250 / 14%)`, 220ms ease-out, and no transition under reduced motion) and a ring dot with a halo. On phone (< 38.75rem) it shows dots only, plus the current step's label, with no wrap and no horizontal scroll.
- **`ChapterSurface.astro`:** a new wrapper element carries `data-chapter-steps-root`. It contains the pill (16px above the glass, left-aligned to the title) and the glass. The step list moves into the pill; the step panels stay in the glass (wide: under the title in the copy column; stacked: under the picture). Chapters with one step render no pill.
  - The controller needs no logic change, because its root only has to contain both the list and the panels (evidence: chapter-step-controller.ts:45–72). Verify the scene's `sceneStepReachedEventName` still reaches the root: the root is now an ancestor of the glass, so bubbling still works, but confirm with a test.
- **Rail target *(provisional)*:** the pill's **left edge at its vertical centre**, at every width (as rendered in round 11).
  - Measure `stepPill` in `measureAnchors` (layout.ts:99–127); a chapter with a pill uses it in place of `surface` as its attach target.
  - In `topology-attach-geometry.ts`, add a pill rule. The attach row is a **forced row at the pill's centre y**, added to `measureTopologyRows` the same way anchor rows are forced today (model.ts:87–112). The fork row is the row above it, which keeps the one-column × one-row bend. The attach band inset doesn't apply to pills.
  - `targetEdge` stays `"left"`.
- **Tests:**
  - `chapter-surface-browser-command.ts`: replace `stepListInGlass` with `stepListInPill === true` and `stepPanelsInGlass === true`.
  - A pill material equality test.
  - The branch path's end point lies on the pill's left-centre (±1px) at 1600, 1280, 820 and 390.
  - Clicking each segment changes `data-step-state` and the visible panel.
  - Keyboard arrows move between segments.
  - Check `tests/chapter-step-controller.browser.test.ts` for nesting assumptions before editing.

## Slice 5: rail vibrancy *(confirmed: full colour down to 0.75 of the viewport height, greying across the bottom quarter, live; the current node and branch glow)*
- **`FullPageTopologyArtwork.astro`:** the drawn content (mainline, routes, row nodes) becomes one source `<g id="topology-rail-source">`. Inside the existing reveal-mask layer, render:
  - `<use href="#topology-rail-source" filter="url(#topology-rail-grey)">`: an `feColorMatrix` with saturate 0, then RGB brightness 0.7;
  - then `<g mask="url(#topology-rail-vibrancy-mask)"><use href="#topology-rail-source"/></g>`, where the mask is a `userSpaceOnUse` linear gradient: white down to the colour line, fading to black at the viewport bottom.
  - Follow the verified structure in `inject-rail.js`. Reveal attributes set on source nodes must style both copies; add a browser test proving it (a node revealed in the source is revealed in both `<use>` copies).
- **`topology-scroll-reveal.ts`:** in the existing per-frame `renderReveal`, set the gradient's y1/y2 to `scrollY + 0.75·innerHeight − artworkTop` and `scrollY + innerHeight − artworkTop`. There's no new listener and no new rAF. Under reduced motion, remove the mask (full colour) and hide the grey copy.
- **Glow:** `updateCurrentNodes` also sets `data-topology-current-branch` on the current node's incoming route group. CSS gives the current node and that branch `drop-shadow(0 0 6px <lane colour at 35%>)`.
- **Tests:**
  - browser: at 1600 and 390, sample route pixels (or computed mask geometry) at viewport y 0.5, 0.87 and 0.99. Colour equals the baseline, is in between, and is under 5% saturation, respectively.
  - Reduced motion is full colour.
  - The render work stays inside the existing single rAF per frame (assert one pending frame; no timing assertions, per the repo's no-wall-clock rule).

## Gates and proof (every slice)
- `pnpm --dir web run check` and `pnpm --dir web run build` both exit 0.
- CDP screenshots of your own preview build compared against the storyboard frames: C-*, R-* and L-*.
- Videos for slices 4–5 in the style of the storyboard's capture scripts.
- One commit per slice (3.0 split, 3.1 ports, 3.2 end, 4 pill, 5 vibrancy); no push.

## Boundaries
- Only `web/` and this spec folder.
- **Out of scope:** the scroll decision (Become vs Rise, pending the owner), the empty left column in wide chapter glasses (pending the owner), and the graph-theme palette.
- Anything contradicting this plan or the renders comes back to the orchestrator with evidence: what was assumed, what was found, what it means.
