# Website motion narrative

Status: draft for owner review, 2026-09-23. Amends the
[2026-08-17 marketing site](../2026-08-17-marketing-site/) design set; where the
two disagree, the owner decisions below govern once accepted.

## Problem

The home page's scroll body works; its first viewport does not. The owner wants
an intro that is fast, visually striking and unmistakably Agent Studio, followed
by a scroll story in which the product's workflows *play*.

Three facts from the current source shape the answer:

1. **The designed hero centrepiece was never built.** The visual design calls
   for a 16:10 HyperFrames product loop beneath the headline
   (visual design §Hero, §Motion; specification R4). `web/src/home-page/Hero.astro`
   ships headline, install command and three CSS planes instead.
2. **The page mixes two section systems.** Five workflows live in a tabbed
   product plate (`web/src/product-plate/`); five more live in glass feature
   rows (`web/src/home-page/SupportingFeatureRows.astro`). They look and behave
   differently.
3. **No motion is code-native yet.** Every HyperFrames composition in
   `agent-studio-media/videos/` is DOM plus a screenshot: zero SVG, canvas,
   Three or p5. The one code-native artwork is the website's own SVG worktree
   topology (`web/src/topology-lab/`), which already runs down the page from a
   hero anchor.

Reference evidence (2026-09-23, from shipped bundles):

| Site | Drawing | Motion | Lesson |
|---|---|---|---|
| onorca.dev | HTML/DOM recreation of an IDE | Motion (Framer) scripted state machine, plays when in view | Animated HTML that looks like the product reads as live |
| omp.sh | canvas-2D instant poster, then Rust/WASM WebGPU | own render loop | Paint instantly, enhance after |
| pi.dev | canvas-2D block logo; real asciinema recording | recording drives page CSS | A brand motif moment, then real proof |

## Owner decisions (2026-09-23)

| # | Decision |
|---|---|
| D1 | **Hero = motif, then proof.** The worktree topology draws in, agents fork into worktrees, and the drawing resolves into a frame holding the real app loop. |
| D2 | **Animated HTML recreation of the app is allowed in scroll chapters** (Orca approach). Reverses the "do not reconstruct app UI" rule for chapter scenes only. |
| D3 | **GSAP is the motion engine** on the site and in HyperFrames, so one scene timeline serves both. |
| D4 | **One section system: glass.** The tabbed product plate is retired as a separate component; its workflows move into glass chapters. |
| D5 | **Play, don't scrub.** Scenes autoplay when their glass surface floats, the way the session-restore video already does. |
| D6 | **Keep every existing workflow**, regrouped under chapter themes. |
| D7 | **Offset left rail** is the page structure at every size. On phone the branch enters the media glass from the top. See "Page structure". |

## Page narrative

```text
 HERO ─ headline + install readable at first paint
   │    topology draws → worktrees fork → frame fills with real loop
   ▼
 CHAPTER 1  Many agents, one map        watch folders · parallel agents
   │                                    · sidebar navigation
 CHAPTER 2  Context stays with the task  task drawers · Git/PR context
   │                                    · files
 CHAPTER 3  Find it, focus it           command bar · pane zoom/layouts
   │
 CHAPTER 4  Review where it happened    review
   │
 CHAPTER 5  Close it. Come back.        persistence (real video)
   ▼
 INSTALL CALL TO ACTION
```

All ten current workflows are placed; none is dropped. Chapter titles are
working labels; final copy goes through `web/.agents/skills/ai-copywriter/SKILL.md`.
The grouping is a proposal for owner confirmation.

## One workflow catalog, shared with media

The site's ten workflows and the media campaign's ten-video menu
(`agent-studio-media/videos/README.md`) are the same inventory. Treat them as
one catalog: each workflow has one promise, one scene module (a website chapter
step and a social clip), and one real capture (the proof).

| Chapter | Site workflow | Media video (rank) | Promise (media wording) | Evidence state |
|---|---|---|---|---|
| 1 | `parallel-work` | `parallel-agent-workspace` (2) | Run several agents without losing where each task belongs. | owner-approved top 3 |
| 1 | `watch-folder` | `watch-folder-discovery` (10) | Start with a folder and discover its repositories and worktrees. | runtime proof needed |
| 1 | `navigation` | `repo-worktree-map` (6) | Parallel work becomes a live repository/worktree map. | candidate |
| 2 | `task-tools` | `pane-drawers` (1) | Every unit of work keeps related tools attached. | owner-approved top 3 |
| 2 | `git-context` | none; the `repo-worktree-map` cutdown is the nearest | — | gap |
| 2 | `files` | `files-in-context` (7) | Inspect source files without leaving the worktree context. | runtime proof needed |
| 3 | `quick-find` | `quick-find` (3) | One keyboard interaction reaches the intended work. | owner-approved top 3 |
| 3 | `arrangements` | `pane-zoom` (8), `saved-arrangements` (9) | Focus one pane without stopping the other work. | runtime proof / fixture needed |
| 4 | `review` | `review-in-context` (4) | Review stays beside the agent and worktree that produced the changes. | storyboard exists |
| 5 | `persistence` | `persistent-workspace` (5) | Close the app without tearing down persistent work. | storyboard exists; site video shipped |

Consequences:

- **Build order follows evidence strength.** The three owner-approved videos
  (drawers, parallel agents, quick find) are the strongest-proven workflows;
  their scenes are built first and lead their chapters.
- Workflows still needing runtime proof (watch folder, files, pane zoom) get
  scenes only after the app behavior is verified. A recreation must not get
  ahead of what the app demonstrably does.
- One scene module per workflow: media renders it to a 10–30 s clip through
  HyperFrames; the site plays it live as a chapter step. Real OpenScreen clips
  remain the proof beat in both.
- `git-context` has no media video; decide whether it earns one or folds into
  `repo-worktree-map`.

## Page structure: the offset rail (owner-confirmed 2026-09-23)

Chosen from two concept rounds (`tmp/2026-09-23-motion-storyboard/`,
v2 Concept B). One vertical git lane on the **left** is the page's progress
rail at every screen size. It reads like `git log --graph`: the dot is the
commit, the chapter title is the message.

- **Geometry:** reuse the owner's tuned topology-lab geometry (git
  `721d72458:web/src/topology-lab/`). Branches are straight horizontal and
  vertical runs joined by its tight-bend corner (cubic control points
  0.9 / 0.08 / 0.1; merges mirror them). Lanes snap to its 96px column
  alignment and meet the frame edge. Loose rounded arcs "look like slop"
  (owner, 2026-09-23). No sine curves and no icons at tips.
- **Node types:** from the same code: small commit nodes (r=4) and terminal
  nodes (r=7 with halo), mapped onto the dot states below.
- **Dots:** one per chapter. Current = `#89b4fa` ring with a filled center;
  passed = filled muted grey; upcoming = hollow grey outline.
- **Wide and laptop:** glass surfaces sit offset right of the rail. The
  current chapter's dot sits level with its eyebrow and joins the glass's
  left edge with one git elbow. That glass's hairline lights blue.
- **Phone:** the rail stays vertical in the left gutter. The chapter's branch
  runs right and drops into the **top edge of the preview/video glass** (the
  media stage). Title, copy and steps sit beside the rail.
- **Hero:** the same rule. The rail starts under the nav logo; a branch joins
  the app frame (left edge on wide and laptop, top edge on phone).
- **Steps inside a chapter** sit on a small vertical dotted lane with the same
  dot states.
- **Consequence:** today's full-page topology anchors on the right
  (`local-right` routes, hero planes). Moving the rail left is a redesign of
  `web/src/topology-lab/`, not a tweak.

```text
 wide / laptop                          phone
 │                                      │
 ◉─╮ ┌─ glass ───────────────┐          ◉─╮ CHAPTER 2
 │ ╰─┤ CHAPTER 2   │ stage   │          │ │ title / copy
 │   │ ◉ step      │         │          │ ╰────────╮
 │   │ ○ step      │         │          │ ┌────────┴──────┐
 │   └───────────────────────┘          │ │ media glass   │
 ○                                      │ └───────────────┘
                                        │   ◉ step ○ step
                                        ○
```

## Chapter anatomy

A chapter is one glass surface (`ScrollMaterialSurface`) with a copy pane and a
stage pane, the same geometry the feature rows use today.

```text
 ┌─ glass surface ──────────────────────────────────────────────┐
 │ ┌─ copy pane ───────────┐ ┌─ stage pane ───────────────────┐ │
 │ │ chapter title         │ │                                │ │
 │ │                       │ │  scene: HTML recreation         │ │
 │ │ ● step 1  (current)   │ │         or video                │ │
 │ │ ○ step 2              │ │                                │ │
 │ │ ○ step 3              │ │  last beat: real capture        │ │
 │ │ step description      │ │                                │ │
 │ └───────────────────────┘ └────────────────────────────────┘ │
 └──────────────────────────────────────────────────────────────┘
```

- Steps are the chapter's workflows. They advance as the scene plays; choosing a
  step jumps the scene to that workflow. This keeps the old plate's tab
  semantics (WAI-ARIA tabs, roving focus, `aria-selected`) with autoplay added.
  The existing `scroll-material-selection-control` styling already renders the
  current-step treatment.
- **Show, then prove.** A recreated scene illustrates the workflow; each
  chapter ends on, or offers, real capture of the same workflow. Recreations
  never carry claims that real capture could not show.
- A single-workflow chapter (Review, Persistence) has one step and no selector.

## Playback: one contract, two media

The glass controller already computes each surface's progress and hands it to a
video controller (start at ≥ 0.95, stop below 0.90, replay after 3 s, manual
intent wins, reduced motion and hidden tabs stop playback). A scene becomes the
second implementation of that same slot; no second scroll system is added.

```text
 scroll-material-surface-controller   (owns progress, reduced motion,
          │                            visibility, lifecycle)
          │ synchronize(progress, autoplayEnabled) / dispose()
          ▼
   SurfacePlayback  ◄── interface extracted from ScrollAutoplayVideoController
      ├─ VideoPlayback   (today's controller, unchanged behavior)
      └─ ScenePlayback   (paused GSAP timeline + step labels)
```

**Loop while centered (owner, 2026-09-23).** Scenes reuse the video
heuristic unchanged (`scroll-material-surface-controller.ts`,
`scroll-autoplay-video-controller.ts`):

```text
 viewport ┬ 0%
          ├ 20% ── top bookend ─────┐
          │   surface fully inside  │ progress = 1 ("centered")
          ├ 80% ── bottom bookend ──┘
          ┴ 100%
 progress ≥ 0.95 → play    progress < 0.90 → pause (hysteresis)
 ended → reset to start, replay after 3 s if still ≥ 0.95   → loops
 manual play/pause wins; leaving (< 0.90) resets manual pause to auto
```

**Height constraint found in that math:** progress peaks at
`0.6 × viewport / surfaceHeight`, eased with smoothstep. A surface taller than
about 69% of the viewport never reaches 0.95, so it **never plays**. Stacked
phone chapters and tall desktop glass will exceed that. So the playback
trigger measures the **media stage** (the element the rail branch enters),
not the whole chapter surface. This matches D7's phone layout. By the same
math, today's stacked phone persistence row may never autoplay; verify this
in the prototype.

`ScenePlayback` states mirror the video's: `resting → playing → ended →
awaiting-replay`, plus manual `paused` and step-selected jumps. Because D5 is
play-on-enter, GSAP core is enough; ScrollTrigger is not needed.

Reduced motion, no JavaScript, and failure all render the scene's **settled
keyframe**: complete, static, useful HTML. That is the chapter's no-script
contract, replacing the plate's "Parallel work only" fallback.

## Scene contract (shared with HyperFrames)

One scene module, two hosts:

```ts
export interface SceneBuildOptions {
  readonly width: number; // fixed stage size, DPR 1
  readonly height: number;
  readonly seed: number; // the only randomness source (seeded PRNG)
}

export interface SceneModule {
  readonly sceneId: string;
  // Beat labels = timeline labels = chapter step ids. One label set drives
  // site step jumps, HyperFrames static-keyframe stills and the settled frame.
  readonly steps: readonly { readonly stepId: string; readonly timelineLabel: string }[];
  // Adds tweens to a PAUSED timeline owned by the host; never creates one.
  // Pure function of t (renderers seek out of order); synchronous build;
  // no requestAnimationFrame, Math.random, Date.now, performance.now,
  // gsap.utils.random; local fonts only.
  buildScene(root: HTMLElement, timeline: gsap.core.Timeline, options: SceneBuildOptions): void;
}
```

- **Website host:** `ScenePlayback` creates the paused timeline, calls
  `buildScene`, then plays, pauses and seeks it to step labels.
- **HyperFrames host:** the composition owns `window.__timelines[id]`, passes
  it to `buildScene`, and renders MP4s and poster/keyframe stills. Requires
  HyperFrames ≥0.8.7 for sub-compositions (media pins 0.8.64).
- Contract agreed with the media lead on the board, 2026-09-23 (messages
  01a0ce95 and 01a0cea6).

Ownership: the website owns scene source under `web/src/motion-scenes/`
(TypeScript, per `web/AGENTS.md`). The media repository consumes a built
bundle pinned to a recorded website revision. A shared package waits for a
second real consumer.

## Recreation kit

Every chapter scene is composed from one kit, never drawn freehand per scene:

| Component | Shows |
|---|---|
| `AppWindow` | window chrome and toolbar at captured proportions |
| `Sidebar` | repo → worktree tree, filter field |
| `Pane` / `PaneGrid` | main panes, current-pane focus ring |
| `Drawer` | task-owned drawer under a pane |
| `AgentTerminal` | scripted agent output that types |
| `CommandBar` | `Cmd+P` scopes, query, results |
| `DiffView` / `FileTree` | review diff and changed-files tree |

Rules:

- Colors, type, spacing and radii come from the app's semantic tokens as the
  site already projects them (`#409CFF` current/focus, `#EF9F76` parallel work,
  `#74C7EC` scarce glyph detail). No new palette.
- Scripted content uses fixture repositories and shipped capabilities from the
  README only: no invented features, metrics, or quotes.
- When the app's look changes, the kit changes once. Kit drift against current
  captures is checked during the website update quality SOP.

## Hero beat sheet (D1)

| Time | Beat |
|---|---|
| first paint | Headline, sub-line, install command and a **static settled topology** are all present. Nothing waits on script. |
| 0.0–0.3 s | Main line draws from the icon planes. |
| 0.3–1.1 s | Three worktree branches fork off; each tip lights up with an agent glyph. |
| 1.1–1.5 s | Branches converge into the outline of a 16:10 frame. |
| 1.5 s → | Frame shows the real app loop (poster first, video when ready). Before a fresh loop exists, the approved still. |

The topology continues down the page as it does today, so the hero motif
becomes the page's spine.

## Making it look good: the authoring loop

```text
 beat (one sentence: what the viewer must understand)
   → 3–4 static keyframes → owner review
   → motion (timeline)
   → contact sheet: frames at fixed times / steps, desktop + phone
   → review → fix → repeat
```

Agents judge taste only from rendered output. Every scene change produces its
contact sheet before it is proposed. The media repository's static-keyframe
gate applies unchanged to HyperFrames renders of the same scenes.

## Phone

A full app recreation is unreadable at 390 px. On phones each step shows a
**focused crop** of its scene: one pane, the drawer, or the command bar. It
uses the same timeline with a phone layout variant, matching today's `*-phone`
capture crops.

## Amendments required on acceptance

- `web/AGENTS.md` §Interactive product plate and §Product proof: replace with
  glass chapters, the recreation kit and D2's show-then-prove rule.
- Visual design §Hero, §Interactive image plate, §Motion: replace with D1, D4,
  D5 and the beat sheet.
- Specification R3 (two proof modes): hero real loop plus chapter scenes that
  end in real capture; the no-script contract becomes the settled keyframes.
- New dependency: `gsap` (standard no-charge license, commercial use allowed
  since 2025-04-30).

## Prototype before commitment

A lab route with the hero (D1) and Chapter 1 only, built on the real glass
controller, reviewed via contact sheets and in a live browser before the rest
of the page is converted.

## Open questions for the owner

1. Is the chapter grouping above right, and does `git-context` get its own
   media video?
2. Should chapters loop their scene, or stop on the settled keyframe after one
   pass until a step is chosen?
3. Hero loop source: does Sol produce a fresh real-capture loop now, or does the
   hero launch with the approved still and gain the loop later?
