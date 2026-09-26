# Website motion build: implementation plan

Status: ready, 2026-09-23. Governing design:
[2026-09-23-website-motion-narrative.md](../2026-09-23-website-motion-narrative.md)
(decisions D1–D7, scene contract, loop-while-centered, page structure).
Concept frames: `tmp/2026-09-23-motion-storyboard/v3/` (final Concept B).
Branch: `website/next-updates`. All work lives in `web/` unless stated.

Every lane reads first: repo `AGENTS.md`, `web/AGENTS.md` (TypeScript-only
source, Tailwind-first, hydration rules, a11y, reduced motion, test rules),
the governing design above, and this plan.

## Shape

```text
 P0 contracts (1 agent, sequential) ── commit on website/next-updates
   │
   ├── A chapter rail          (worktree, parallel)
   ├── B chapter surface + playback + hero   (worktree, parallel)
   └── C recreation kit + scenes             (worktree, parallel)
   │
 D integration (after A, B, C merged): page composition, retire old
   sections, copy pass, full check, visual proof
```

Lanes A–C own **disjoint folders**. The only shared files are the P0
contracts, which lanes import and never edit. A lane that needs a
contract change stops and reports to the orchestrator.

## P0: contracts (sequential, first)

Owns: `web/package.json`, `pnpm-lock.yaml`, and the new files below.

1. Add `gsap` (latest 3.x) as a dependency with `pnpm --dir web add gsap`.
2. `web/src/motion-scenes/scene-contract.ts`:

```ts
import type { gsap } from "gsap";

export type SceneId = "chapter-many-agents" | "chapter-context-with-task" | "chapter-find-and-focus";

export interface SceneBuildOptions {
  readonly width: number;
  readonly height: number;
  readonly seed: number;
}

export interface SceneStep {
  readonly stepId: ChapterStepId;
  readonly timelineLabel: string;
}

export interface SceneModule {
  readonly sceneId: SceneId;
  readonly steps: readonly SceneStep[];
  // Adds tweens to a PAUSED host-owned timeline. Markup is rendered in its
  // settled (final) state; tweens use from()/fromTo() so the timeline's end
  // equals the no-JS markup. Pure function of t; synchronous; no
  // requestAnimationFrame, Math.random, Date.now, performance.now,
  // gsap.utils.random.
  buildScene(root: HTMLElement, timeline: gsap.core.Timeline, options: SceneBuildOptions): void;
}

export function createSeededRandom(seed: number): () => number; // mulberry32
```

   (`ChapterStepId` is imported from the chapter catalog.) Unit-test
   `createSeededRandom` for determinism.
3. `web/src/motion-scenes/scene-registry.ts`: `resolveSceneModule(sceneId:
   SceneId): SceneModule | undefined` backed by an empty
   `ReadonlyMap<SceneId, SceneModule>`. Lane C fills it; nobody else edits it.
4. `web/src/chapters/chapter-catalog.ts`: typed, immutable catalog of the 5
   chapters. Copy strings come from `marketing-copy.ts`. Step copy
   **reuses the existing approved strings** (`marketingCopy.stories.*`,
   `marketingCopy.featureDetails.items`). Chapter titles use the design
   doc's working titles, added under a new `marketingCopy.chapters` key.

```ts
export type ChapterId = "many-agents" | "context-with-task" | "find-and-focus" | "review" | "come-back";
export type ChapterStepId =
  | "parallel-agents" | "watch-folders" | "navigation"
  | "task-drawers" | "git-context" | "files"
  | "quick-find" | "pane-zoom"
  | "review-diff"
  | "persistence";

export type ChapterStage =
  | { readonly kind: "scene"; readonly sceneId: SceneId; readonly proofImage: ImageMetadata; readonly proofAlt: string }
  | { readonly kind: "still"; readonly image: ImageMetadata; readonly phoneImage: ImageMetadata; readonly alt: string }
  | { readonly kind: "video"; readonly source: string; readonly poster: ImageMetadata; readonly label: string };

export interface ChapterStep {
  readonly id: ChapterStepId;
  readonly label: string;
  readonly description: string;
  readonly phoneDescription: string;
}

export interface Chapter {
  readonly id: ChapterId;
  readonly eyebrow: string; // "Chapter 1"
  readonly title: { readonly beforeAccent: string; readonly accent: string; readonly afterAccent: string };
  readonly steps: readonly ChapterStep[];
  readonly stage: ChapterStage;
}

export const chapterCatalog: readonly Chapter[];
```

   Stages: chapters 1–3 are `scene` (proof images: `parallel-agents.png`,
   `pane-drawer.png`, `command-bar.png`). Chapter 4 is a `still`
   (`review.png` + phone crop). Chapter 5 is a `video`
   (`session-restore.mp4` + poster). Unit-test the catalog: unique ids,
   every step label is non-empty, and scene steps match the catalog order.
5. `web/src/chapters/chapter-dom-contract.ts`: the DOM attribute names every
   lane uses, as exported constants (no string literals elsewhere):

| Constant | Attribute | Placed by | Meaning |
|---|---|---|---|
| `railAnchorAttribute` | `data-rail-anchor="<hero\|chapterId>"` | B (hero eyebrow, chapter eyebrow) | rail dot is vertically aligned to this element |
| `railSurfaceTargetAttribute` | `data-rail-surface-target="<id>"` | B (hero app frame, chapter glass) | wide/laptop: branch joins this element's left edge |
| `railMediaTargetAttribute` | `data-rail-media-target="<id>"` | B (hero app frame, chapter media stage) | phone: branch drops into this element's top edge |
| `playbackStageAttribute` | `data-scroll-playback-stage` | B (media stage) | autoplay progress is measured from this element |
| `sceneRootAttribute` | `data-scene-root="<sceneId>"` | C (scene markup root) | ScenePlayback mounts the module here |
| `sceneStepTargetAttribute` | `data-scene-step="<stepId>"` | C (optional, within scene) | step-scoped elements for scene authors |

Proof: `pnpm --dir web run lint`, `fmt:check`, `typecheck`, `test:unit` all
pass. Commit on `website/next-updates`. Done when committed.

## Lane A: chapter rail

Owns: new `web/src/chapter-rail/`, `web/src/site-shell/FullPageTopologyBackdrop.astro`
(replaced), deletion of `web/src/topology-lab/`, its tests
(`tests/full-page-topology-*.test.ts`, `tests/topology-scroll-reveal.browser.test.ts`),
and the `data-topology-mainline-anchor` reference in `Hero.astro`. **Hard
cutover:** the old right-side topology is removed, not kept beside the rail.

Build:
- `chapter-rail-layout.ts`: pure function
  `layoutChapterRail(props: ChapterRailLayoutProps): ChapterRailLayout`.
  Input: viewport width, page height, and measured rects for every
  `data-rail-anchor`, `data-rail-surface-target` and `data-rail-media-target`.
  Output: rail x, the rail path, and one node per anchor (y centered on the
  anchor), with one branch path per node. Wide/laptop: the branch goes node → git
  elbow → target's **left edge** at the node's y. Phone (the site's `phone`
  breakpoint): node → right → git elbow → down into the media target's
  **top edge**. Geometry uses the existing git language: vertical lanes, one
  quarter-radius elbow, no curves beyond that.
- `ChapterRail.astro` + `chapter-rail-controller.ts`: one full-page SVG
  (`aria-hidden`, `pointer-events: none`), measured on load/resize/font-load
  with one owning lifecycle. The current node is the chapter whose anchor is
  nearest above the 40% viewport line: blue `#89b4fa` ring with filled center.
  Earlier nodes are filled muted grey; later ones are hollow. The current
  chapter's branch and its target's hairline brighten (set
  `data-rail-current` on the target element; lane B styles it).
- Stroke/color tokens: main lane desaturated primary, optional short
  decorative branches in muted `--color-parallel`/`--color-glyph`, matching
  `v3/B-*` frames. No icons.
- Visible at all widths, including phone (the old backdrop hid below a
  breakpoint). Rail x: inside the left gutter. Content column offset is lane
  B's concern; A reads positions, never sets layout.
- Reduced motion: no transitions; state still updates.
- Tests: unit tests for `layoutChapterRail` (node y alignment, left-edge vs
  top-edge branch selection by breakpoint, current-node selection) and one
  browser test mounting a fixture with anchors, asserting node count and
  branch endpoints within 1px of targets.

Proof: `pnpm --dir web run lint`, `fmt:check`, `typecheck`, `test:unit`,
`test:browser` pass in the lane worktree. Commit on the lane branch.

## Lane B: chapter surface, playback, hero

Owns: new `web/src/chapters/ChapterSurface.astro`,
`web/src/chapters/chapter-step-controller.ts`,
`web/src/home-page/scene-playback.ts`,
`web/src/home-page/scroll-material-surface-controller.ts` (edit),
`web/src/home-page/scroll-autoplay-video-controller.ts` (edit only to extract
the interface), `web/src/home-page/Hero.astro` (rewrite).

Build:
- Extract `SurfacePlayback { synchronize(progress, autoplayEnabled); dispose() }`
  from the video controller with **no behavior change**. Existing tests
  must keep passing unchanged.
- Glass controller: when a surface contains `data-scroll-playback-stage`,
  compute playback progress from **that element's** bounds with the same
  20%/80% bookend math. Material lift/visuals still use the surface. This
  fixes the height cap described in the design doc ("Loop while centered").
- `ScenePlayback` implements `SurfacePlayback` for `data-scene-root` using
  `resolveSceneModule`. It creates a paused timeline, calls `buildScene`, and
  mirrors the video semantics exactly: play at ≥ start progress, pause below
  stop progress, on complete reset to 0 and replay after the replay delay
  while still centered, manual intent wins. It emits the current step
  whenever the timeline passes a step label. Reduced motion or an unresolved
  module: never builds tweens and leaves the settled markup.
- `ChapterSurface.astro`: a glass surface (`ScrollMaterialSurface`) with a copy
  pane (eyebrow with `data-rail-anchor`, title with accent, step list on a
  small vertical dotted lane) and a stage pane (`data-rail-media-target`,
  `data-scroll-playback-stage`, a named `stage` slot). The glass carries
  `data-rail-surface-target` and styles `[data-rail-current]` with the lit
  hairline. Layout: wide/laptop = content offset right of the rail gutter,
  copy ~35% | stage ~65%; phone = eyebrow/title beside the rail, then the stage
  full width minus the rail gutter, then steps (per `v3/B-chapter-phone*`
  and the design doc diagram).
- Steps follow WAI-ARIA tabs (port the proven semantics from
  `product-plate-controller.ts`: roving focus, arrows/Home/End,
  `aria-selected`, disabled static contract before enhancement). Selecting
  a step seeks the scene to its label and plays. Timeline progress updates
  the selected step without moving focus. `still` stages with several steps
  switch images; `video` stages have one step.
- `Hero.astro` rewrite: rail anchor on the eyebrow; existing copy and
  `InstallCommand` unchanged; a 16:10 app frame (`data-rail-surface-target`
  + `data-rail-media-target="hero"`) holding `parallel-agents.png` now, with a
  `<video>` slot ready for the K1 loop (poster-first, `ScrollAutoplayVideo`).
  The frame must **peek above the fold** at 1440×900 and 1280×800. Remove the
  CSS planes.
- Tests: browser tests for step tabs (keyboard, selection, invalid id keeps
  the last valid), ScenePlayback with a test-local fake `SceneModule` (plays
  when centered, pauses when leaving, loops after the delay, manual pause wins,
  reduced motion = no tweens), and stage-measured progress on a surface taller
  than the viewport.

Proof: same commands as lane A. Commit on the lane branch.

## Lane C: recreation kit + scenes

Owns: new `web/src/recreation-kit/`, new
`web/src/motion-scenes/scenes/`, and `web/src/motion-scenes/scene-registry.ts`
(fill only).

Build:
- Kit components (Astro, static, typed props, fixture data separate from
  markup): `AppWindow`, `AppToolbar`, `Sidebar` (repo → worktree → pane
  rows), `Pane`, `PaneGrid`, `Drawer`, `AgentTerminal` (lines with
  `data-line` for typing), `CommandBar`, `DiffView`, `FileTree`.
- Look: faithful to current captures in `web/src/assets/captures/`
  (`parallel-agents.png`, `pane-drawer.png`, `command-bar.png`, `files.png`).
  Token source: the app's semantic theme as the site projects it
  (`web/src/styles/global.css`) plus `docs/architecture/bridge/bridgeweb_design_token_architecture.md`
  for pane/terminal colors. Add kit-scoped CSS variables with source comments.
  Don't import the BridgeWeb stylesheet (`web/AGENTS.md`).
- Fixture text hygiene: curated neutral agent output and `git` lines only.
  No quota/usage banners, permission-mode labels, personal paths or emails,
  or invented metrics.
- Three scenes (markup component + module each):
  - `chapter-many-agents`: steps parallel-agents (panes appear, two agents
    type), watch-folders (sidebar repos/worktrees populate), navigation (the
    sidebar filter types a query and the list narrows).
  - `chapter-context-with-task`: task-drawers (drawer slides up under the agent
    pane with `git status`), git-context (branch/PR context appears), files
    (file tree + source view).
  - `chapter-find-and-focus`: quick-find (Cmd+P opens, query types, jumps to
    a pane), pane-zoom (focused pane expands and the others yield).
  Each scene's markup is its **settled final state**; the module uses
  from()/fromTo() tweens with labelled beats matching `SceneStep.timelineLabel`,
  total 8–14 s, loop-safe (the end state is stable).
- Register the three in `scene-registry.ts`.
- A dev-only visual review page `web/src/pages/lab/scenes.astro` (noindex,
  excluded from the sitemap) rendering each scene in a 16:10 stage with
  play/scrub controls, for contact-sheet review. Lane D deletes it before
  release.
- Tests: unit tests that each module's labels match its declared steps and
  that `buildScene` is deterministic (the same seed gives the same tween list);
  a banned-API check (grep test) over `motion-scenes/`.

Proof: same commands as lane A. Also produce a contact sheet: screenshots of
each scene at each step label at 1280×800 and 390×844, saved under
`tmp/2026-09-23-motion-build/lane-c/`. Commit on the lane branch.

## Lane D: integration (after A, B, C are merged)

Owns: `web/src/home-page/HomePage.astro`, `marketing-copy.ts` (chapters
copy), removal of `web/src/product-plate/` (plate, controller, fixture,
state, PersistenceProof if unused) and `SupportingFeatureRows.astro` plus
their tests, `FinalGitHubCallToAction.astro` (it must include the install
command), `web/src/pages/lab/`, and README image references (verify they
are unchanged).

- Compose: Hero → 5 `ChapterSurface`s from `chapterCatalog` (scene stages
  mount lane C markup; still/video stages render images/`ScrollAutoplayVideo`)
  → final CTA with install command → footer. `ChapterRail` in `SiteShell`.
- Copy pass on chapter titles and any new strings using
  `web/.agents/skills/ai-copywriter/SKILL.md`, preserving README facts.
  Record coverage in the receipt.
- Remove the lab page and verify `sitemap.xml` has no lab route.
- Full proof: `pnpm --dir web run check` green; `pnpm --dir web run build`
  green; then `mise run test` from the repo root before any PR.
- Visual proof is a separate Sol operator procedure (orchestrator-dispatched):
  screenshots at 1920×1080, 1280×800, 390×844 compared with `v3/B-*`.

## Gated / follow-up (not in this build)

- Chapter 4 annotations + compare-worktree steps: blocked on the owner's
  README decision (annotations still listed under "Next").
- Inbox notifications step in chapter 1: needs a capture and README check.
- K1 hero loop and K2–K4 proof clips: after tonight's capture session;
  drop-in replacements for the stills.
- `web/AGENTS.md` and spec amendments: orchestrator-authored after
  integration.
