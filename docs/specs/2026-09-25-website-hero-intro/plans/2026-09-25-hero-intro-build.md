# Plan: the website hero intro ("one window", dealt from the icon)

Author: the orchestrator (main). Branch: `website/hero-intro` (worktree `/private/tmp/agentstudio-hero-intro`). There's one PR for the whole redesign. This plan covers **slices 1–2**; slices 3–5 get their own plans once their renders are approved.

## Sources of truth (read these first)
- The owner-approved design and every correction: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.website-marketing/tmp/2026-09-24-intro-storyboard/PRODUCTION-STORYBOARD-BRIEF.md` (layout rules, Amendments 1–3), plus `CHECKLIST.md` beside it.
- The verified reference implementation: `…/tmp/2026-09-24-intro-storyboard/production-storyboard/inject-hero.js` (pane markup and CSS, transcript variants, sampled colours) and `frames/L-*.png` (what the result must look like). Port from it; don't re-invent it.
- The real TUI references: `…/tmp/2026-09-24-intro-storyboard/refs/claude-code-real-startup.png`, `codex-real-startup.png`.
- The repo rules: `web/AGENTS.md` and the existing modules this plan names.

## Mental model
```
Hero.astro (layout only)
 ├─ eyebrow, h1                                  (unchanged)
 ├─ <HeroTerminalWindow/>   settled final markup: icon stack + window (Claude | Codex)
 │     └─ <script> initializeHeroIntroPlayback(root)
 │            hero-intro-playback.ts  WHEN: play once, skip, resize, reduced motion
 │            hero-intro-scene.ts     WHAT: a pure GSAP timeline into the settled markup
 ├─ install row: <InstallCommand/> + description   (existing component, unchanged)
 └─ app frame (unchanged in slices 1–2; slice 5 decides Become or Rise)
```
- **CSS owns the final layout, at every size.** The markup rendered by Astro *is* the end state. With no JavaScript, or with reduced motion, the page looks exactly like the final frame.
- **The scene** only tweens from computed start values *to* that layout (`fromTo`/`from`), on a paused, host-owned timeline. It never creates layout.
- **The playback host** owns time: it plays once on load, a user scroll/wheel/touch/key finishes it, a resize during play finishes it (`progress(1)`), a resize after it does nothing, and **nothing ever rewinds**. When the timeline completes, it clears every inline style the scene set (`clearProps: "all"` on the scene's targets), so CSS alone holds the layout from then on.

## Slice 1: the canvas, the hero layout, and the settled terminal window (no motion)
Files (new unless noted):
1. `web/src/styles/global.css` (edit): `--color-canvas: #191b1f`. Then grep the other canvas-colour copies (`SiteShell.astro`, `topology-lab/FullPageTopologyArtwork.astro`); update any that must match, but **leave** the social/banner templates in `scripts/` alone (they're separate marketing assets).
2. `web/src/hero-intro/hero-terminal-transcripts.ts`: typed transcript data, the only place the transcript text lives. Model the rows as a discriminated union, for example `{ kind: "user-band" | "assistant-text" | "tool-call" | "tool-result" | "diff-row" | "codex-action" | "codex-detail" | "codex-prose" | "blank"; … }`, each with `tiers: readonly TranscriptTier[]`, where `TranscriptTier = "full" | "compact" | "phone"`. The content is exactly Amendment 1 of the brief.
3. `web/src/hero-intro/ClaudeCodePane.astro`: the startup header (the pixel mascot as SVG rects, `#e6714e`; `Claude Code v2.1.281` / `Opus 5.5 · Claude Max` / `~/agent-studio`), the transcript rows from the data, and the footer (rule, `❯ ▌` block cursor, rule, auto-mode line).
4. `web/src/hero-intro/CodexPane.astro`: the bordered fit-content startup box, the transcript, and the pinned input band plus the segmented status line.
5. `web/src/hero-intro/HeroIconStack.astro`: the 3 icon planes (geometry and colours from `web/src/assets/brand/app-icon.svg`) in **one container** (`data-hero-icon-stack`), so the stack moves and tilts as a unit. Its settled pose: peeking at the window's top-left corner, tilted −2° (desktop peek 30–40px, phone 12–16px).
6. `web/src/hero-intro/HeroTerminalWindow.astro`: the stack plus the window (`data-hero-terminal-window`). It has `role="img"` and an `aria-label` describing the scene; the panes inside are `aria-hidden`.
   - Window border: the site glass boundary, 1px `rgb(137 180 250 / 38%)`, with the `--scroll-material-radius` radius.
   - Fill: `#282c34`.
   - Divider: 1px.
   - **Height is content-sized (no fixed height), so no line can ever clip.**
   - Codex is hidden below 64rem.
   - Transcript tiers via CSS: rows carry `data-transcript-tier` attributes. `@media (width < 38.75rem)` shows only phone rows. `@media (width >= 64rem) and (height < 56.25rem)` hides full-only rows (the compact tier). Tune the height threshold only with the browser-test evidence below.
7. `web/src/hero-intro/hero-intro-dom-contract.ts`: every data-attribute name shared by the markup, the scene and the playback, in the style of `chapters/chapter-dom-contract.ts`.
8. `web/src/home-page/Hero.astro` (edit): the order is eyebrow, h1, `<HeroTerminalWindow/>`, install row, app frame.
   - **Install row:** `InstallCommand` at its natural width plus the description. The description sits beside the install box at ≥ 64rem (vertically centred, 40px gap, max-width 34rem) and under it below that.
   - **Window edges:** the window's left and right edges equal the app frame's (same container and padding).
   - **Glow:** a full-bleed, unclipped radial `#282c34 → transparent` behind the copy and the window, with **no straight edge anywhere** and no horizontal page overflow.
9. Remove anything the new layout makes dead; don't leave parallel old paths.

Slice 1 tests (browser mode, page-level, in the style of `tests/chapter-surface.browser.test.ts` + `*-browser-command.ts`):
- Settled layout, with reduced motion forced, at 390×844, 820×1180, 1024×768, 1280×800, 1366×768, 1440×900, 1512×982, 1600×1000, 1728×1117, 1920×1080 and 2560×1440. Assert:
  - every transcript row's rect is inside the window's padding box;
  - the install box's bottom ≤ the viewport height;
  - the window's left and right equal the app frame's (±1px);
  - exactly one cursor element;
  - `scrollWidth === clientWidth` (no horizontal overflow);
  - there's no Codex pane below 1024;
  - the canvas's computed background is `rgb(25, 27, 31)`.
- Unit (`hero-terminal-transcripts.test.ts`): every row has at least one tier; the phone tier contains the Bash call and the ready line; the compact tier drops the earlier exchange; there's exactly one cursor row.

## Slice 2: the intro motion (the choreography is Amendment 3 of the brief, t = 0 → 5.6s)
- `web/src/hero-intro/hero-intro-scene.ts`: `buildHeroIntroScene(root: HTMLElement, timeline: SceneTimeline, options: SceneBuildOptions): void`, reusing the types from `motion-scenes/scene-contract.ts`. It follows the scene-contract rules: synchronous; no requestAnimationFrame, Math.random, Date.now, performance.now or gsap.utils.random; `fromTo`/`from` into the settled markup. The only DOM reads are the start rects, read once at build.
  - Beats:
    - the copy rises in;
    - the front plane slides in;
    - the rears deal out;
    - the `_` blinks;
    - the **stack tilts as a unit to −6° then settles at −2°**;
    - the **4th plane** is dealt out from behind the front plane (a scene-created element, removed on completion) and **expands into the window's rect** (it resizes rather than scales; the stroke goes 5px `#89b4fa` → the glass boundary);
    - the window content types in: Claude's input typing, then the user band; the Bash spinner `✶ Brewing… (esc to interrupt)`; `⎿ ✓ Ready. Copy it below ↓`;
    - the install rises, then the description;
    - the glow blooms.
  - Its complete target list is exposed, so the host can clear props.
- `web/src/hero-intro/hero-intro-playback.ts`: `initializeHeroIntroPlayback(root): HeroIntroPlayback`.
  - Reduced motion, or a document hidden at load: settle immediately.
  - Otherwise: build a paused timeline and play it once.
  - Finishing triggers:
    - `wheel`, `touchstart`, `keydown` and `scroll` (passive) finish it;
    - a `resize` while playing finishes it;
    - on complete: `clearProps` on all targets, remove the 4th plane, set `data-hero-intro-state="settled"` and dispatch a `hero-intro-settled` event (a real completion signal, so tests never poll).
  - It never rewinds.
- `HeroTerminalWindow.astro`: a `<script>` that initializes the playback for its root.

Slice 2 tests:
- Browser: at 1600×1000 with motion, start the intro, change the viewport to 1100 wide mid-timeline, then await `hero-intro-settled`. Assert: no element under the root carries an inline `style` that the scene set; the window rect equals a fresh reduced-motion load at 1100 (±1px); the timeline progress is 1. After settling, a resize back to 1600 leaves no inline styles and equals a fresh load at 1600.
- Browser: reduced motion settles with no timeline created; a keydown mid-intro settles it.
- Unit/browser: `buildHeroIntroScene` on a fixture builds a paused timeline whose end equals the settled markup (seek to the end, and the computed rects equal the settled ones).

## Proof and gates (all must exit 0)
- `pnpm --dir web run check` (lint, fmt, typecheck, captures, unit, browser), then `pnpm --dir web run build`.
- Headless Chrome screenshots of your own preview build at the 11 slice-1 viewports, settled, into `tmp/hero-intro-proof/` in the worktree, plus intro videos at 1600 and 390 and the resize video (in the style of the storyboard's `capture.mjs`). Compare them with the storyboard's `frames/L-*.png`, and list every visible difference.

## Boundaries
- Write only inside `/private/tmp/agentstudio-hero-intro/web/` and `/private/tmp/agentstudio-hero-intro/docs/specs/2026-09-25-website-hero-intro/`. Nothing outside the website.
- Chapters, the rail, and the scroll (Become/Rise) are **out of scope** here (slices 3–5). Don't touch `topology-lab/`, the `chapters/` markup, or the app frame's behaviour.
- The decisions are the owner's; if something in this plan contradicts the brief or reality, stop and report the evidence (what was assumed, what you found, what it means). Don't improvise around it.
- Commit per slice on `website/hero-intro` (signed if possible; after two signing failures `--no-gpg-sign`; never `--no-verify`). Don't push.
