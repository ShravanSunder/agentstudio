# Plan: chapter layout "G7 hybrid": the pill above the picture on desktop, below it on smaller screens (slice 6)

Author: the orchestrator. Branch `website/hero-intro`, the same PR. **Owner-approved 2026-09-26** ("yes to G7, let's build it"), with these owner corrections applied:
- the order is **responsive** (owner: "for desktop the pill can be above the picture"):
  - **≥ 64rem (1024px, the existing stacked breakpoint): title → pill → glass (picture) → caption**;
  - **< 64rem: title → glass (picture) → pill → caption**.
  It's one set of components; only the pill's position changes (CSS order/grid areas, no duplicated markup);
- **the pill carries the step names**, and the caption does **not** repeat the title or the step label. **Keep the caption simple: the description only**;
- the caption uses **curved borders** and the terminal-grey "active item" surface;
- the step line **fills as the chapter autoplays** through its steps and videos;
- **remove the "Real capture" badge**;
- no side text column in the glass (the picture gets the full width);
- no port dots anywhere; the title, glass, pill and caption share one left edge;
- nothing jumps (constant heights, no layout shift).

The visual reference is the prototype frames `/private/tmp/agentstudio-layout-variants/frames/*-G7-separated-caption-*.png` (390, 820, 1024×768, 1280×800, 1600, 2560) **plus the owner's corrections above**. The prototype's caption still shows an eyebrow and label; drop both.

## Structure (hard cutover; no old layout kept)
```
<article class="chapter-section" id=…>
  <div data-chapter-steps-root>                        ← wrapper; the controller root
    <h2 data-rail-anchor>title</h2>                    ← OUTSIDE the glass
    <ChapterStepPill/>                                 ← DOM before the glass; desktop shows it above,
                                                         < 64rem CSS moves it below; multi-step only
    <ScrollMaterialSurface data-rail-surface-target>   ← the glass holds ONLY the stage
      stage (scene / capture / video), full glass width, aspect kept
    </ScrollMaterialSurface>
    <div class="chapter-caption">step panels</div>     ← description only
  </div>
</article>
```
Spacing, desktop: title → pill 14px; pill → glass 14px; glass → caption 12px. Smaller screens: title → glass 20px; glass → pill 14px; pill → caption 10px. The DOM order is title, pill, glass, caption on BOTH; the < 64rem order moves the pill below the glass with CSS (for example grid-template-areas), so keyboard and reading order stay sensible. The title's glyph stem, the glass's outer edge, the pill's left edge and the caption's left edge share one x (±1px). Single-step chapters render title → glass → caption with no pill.

## Components
1. **`ChapterSurface.astro`:** the structure above. Delete the 35/65 copy grid and the in-glass title and panels.
2. **The glass stage:** full width. **Remove the "Real capture" badge**: delete its render in the proof layer and the `realCaptureLabel` copy key and its uses (hard cutover). The show-then-prove playback itself is unchanged.
3. **`ChapterStepPill.astro`:** today's pill (the floating-glass material, a dot plus a label per step, the sliding highlight): above the glass at ≥ 64rem, below it under 64rem.
   - **The labels live here.** At ≥ 38.75rem all labels show (the current one bright). On phone, only the current label shows, alongside the dots.
   - **Progress track:** a 1px hairline behind the dots, `rgb(255 255 255 / 12%)`. Its filled part is the primary blue from the first dot to the **current** dot, with a 300ms width transition (none under reduced motion). Completed dots are filled, the current dot has the ring and halo, and later dots are hollow.
   - The fill follows the controller's current step, whether that comes from a click or from autoplay (the scene's step-reached events).
4. **The caption, `.chapter-caption` (new, in `ChapterSurface.astro` or a small `ChapterCaption.astro`):**
   - Surface: background `#282c34`, border `1px solid var(--color-line)`, **radius 20px (curved)**, padding 18px 22px (desktop) / 16px 18px (phone), inner top highlight `inset 0 1px 0 rgb(255 255 255 / 4%)`. No blur, no gradient.
   - Content: **the description only**, 16px / 1.55, `text-ink-muted`, max 70ch. No eyebrow, no label, no title.
   - Behaviour: exactly one panel is visible. The caption's `min-height` equals the tallest step's description at that width (measured or computed in CSS), so switching never moves anything below it. The text crossfades over 180ms (none under reduced motion).
5. **Rail (hybrid):**
   - **≥ 64rem:** the branch enters **the pill's left edge at its vertical centre** (keep slice 4's pill target and forced attach row as they are).
   - **< 64rem:** the pill sits below the picture, so the branch enters **the picture glass's TOP edge at its left** (the existing stacked drop-corner inset rule). The pill isn't a rail target there.
   - Single-step chapters (no pill): the glass's top edge on smaller screens, and the glass's left edge as today on desktop.
   - Everywhere: no port dot, the owner's corner algorithm, and the chapter mainline node aligned with the title's first line.
6. **First image (orchestrator default, flagged to the owner):** make it match. The hero app frame glass, then a caption card (the same caption style) holding the hero description in place of today's centred text below the frame. The branch enters the frame's top edge. The new picture/video for it comes later.

## Tests (TDD: write each red first)
- `chapter-surface` browser at 390, 820, 1024, 1280, 1600 and 2560:
  - y-order: title < pill < glass < caption at ≥ 1024; title < glass < pill < caption below 1024;
  - a shared left x (±1px);
  - no element inside the glass other than the stage;
  - zero "Real capture" text on the page;
  - exactly one visible description;
  - the caption height constant across every step click (±0.5px), and the next section's top unchanged across clicks;
  - the pill label behaviour (all vs current) per width;
  - the progress fill width equals the distance from the first to the current dot centre (±1px) after each click and after an autoplay step.
- Topology: the branch path's end point is on the pill's left-centre at ≥ 1024 and on the glass's top edge below 1024 (±1px); no port node.
- Keep the existing gates: `pnpm --dir web run check` + `build` exit 0, **three consecutive green full checks** (the flake rule), no timeout raised.

## Proof
CDP frames of your own build at the six sizes for "many-agents", "context-with-task" and one single-step chapter, paired against the G7 reference frames, with every difference listed. Also a video `chapter-g7-1600.mp4` and a `-390` version showing autoplay advancing the fill and caption with nothing jumping. Update RESULT.md under "Slice 6", commit (one commit, or two if the rail cutover is cleaner separate), append 'slice6 done' to STATUS.md, and don't push (the orchestrator pushes after verifying).
