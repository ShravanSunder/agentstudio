# Agent Studio Marketing Site Visual Design

## Design thesis

Agent Studio turns parallel coding-agent work into spatially organized work. The website makes that organization visible through real, consistently captured product surfaces: repositories separate into worktrees, worktrees carry panes, drawers attach related tools, and focus brings one unit of work forward without erasing the surrounding work.

The product is the hero. Marketing language establishes the promise, then the
page supplies product proof through recognizable hero imagery and one clickable
image plate that contains the complete feature explanation.

Herdr contributes discipline: one large claim, a constrained chassis, hairline rails, strong typography, and immediate product proof. Agent Studio supplies the visual identity, product geometry, colors, imagery, and motion.

## Page anatomy

The page uses one 1440px maximum-width framed chassis. The background may continue outside the chassis, but primary copy, rails, proof surfaces, and calls to action align to the same left and right edges.

### Page-local chrome

- 60px desktop height.
- Agent Studio logo and name at the left.
- In-page anchors, GitHub, and Install at the right.
- One bottom hairline separates chrome from the hero.
- No Docs, Blog, Changelog, account, pricing, or other ungoverned destinations.

### Hero

- Small monospaced eyebrow: `NATIVE MACOS WORKSPACE FOR CODING AGENTS`.
- Display statement: `Stay oriented without losing context.`
- One short paragraph explaining repository/worktree-centered organization.
- Homebrew install control and GitHub action.
- A large 16:10 product-video plate beneath the copy, using the approved website-loop poster before playback.
- No feature cards, testimonials, or fake metrics in the hero.

### Interactive image plate

- Full-width 16:10 stage directly after the hero.
- 280px desktop selector rail and one dominant image panel.
- Selector states: Parallel work, Pane drawer, Quick Find, Review, and Git/PR context.
- Each state displays one manifest-verified website capture master.
- The plate may include a small state label and one sentence outside the image. It does not place explanatory badges over the application UI.
- Selection uses blue focus; inactive/parallel state markers may use peach.

### After the explainer

The clickable plate owns Parallel work, Pane drawer, Quick Find, Review, and
Git/pull-request context. A compact expandable feature list follows it.
Persistence is the first required disclosure because restoration needs a
sequence and explanation rather than another single screenshot tab. Additional
rows may cover owner-approved shipped details without repeating the five main
states. The final install call to action follows the disclosure list.

### Final call to action

- Canonical stacked-plane logo.
- `Agent Studio.`
- `Native macOS workspace for coding agents.`
- Current Homebrew command and GitHub action.
- Long enough vertical hold that the end of the page feels deliberate rather than appended.

## Color system

| Role | Token | Use |
| --- | --- | --- |
| Deep canvas | `#1D2026` | Page background and deepest pane ground |
| Product ground | `#282C34` | Main framed chassis and large product surfaces |
| Elevated | `#323641` | Selector rail, command palette, raised product chrome |
| Selected | `#464B57` | Selected rows and secondary active surfaces |
| Primary ink | `#FFFFFF` | Display headlines and critical labels |
| Secondary ink | `#EAEAEA` | Body copy and primary product text |
| Muted ink | `#C5C8C6` | Captions, descriptions, secondary status |
| Faint ink | `#9BA1AD` | Metadata and nonessential technical context |
| Product primary | `#89B4FA` | Focus, selection, current action, active rail |
| Parallel work | `#EF9F76` | Rear planes, related/background work, depth markers |
| Glyph cyan | `#74C7EC` | Canonical terminal glyph and rare technical detail |
| Interactive blue | `#409CFF` | Native product capture detail only |

Large backgrounds remain solid or use localized radial illumination. Do not use full-screen linear gradients, gradient text, purple/cyan SaaS glow, or a rainbow expansion of syntax/status colors.

## Typography

The website uses the operating-system stack so it feels like the native application without shipping proprietary fonts.

- Display: `system-ui`, `-apple-system`, `BlinkMacSystemFont`, `SF Pro Display`, sans-serif.
- Body: `system-ui`, `-apple-system`, `BlinkMacSystemFont`, `SF Pro Text`, sans-serif.
- Technical: `ui-monospace`, `SF Mono`, `SFMono-Regular`, Menlo, Monaco, Consolas, monospace.

Desktop scale:

| Role | Size | Weight | Line height |
| --- | --- | --- | --- |
| Hero display | `clamp(76px, 7.5vw, 132px)` | 800 | 0.88–0.92 |
| Section display | `clamp(52px, 5vw, 88px)` | 750–800 | 0.94 |
| Body lead | 24–30px | 400 | 1.35 |
| Body | 18–21px | 400 | 1.55 |
| Mono label | 12–15px | 500 | 1.3 |

Mobile hero display is 52–68px. Body copy never shrinks below 17px. Product labels inside screenshots are captured at the fixed app geometry rather than resized independently.

## Grid, spacing, and geometry

- 8px base spacing unit.
- Wide desktop gutters may use sparse icon-derived plane stamps. They disappear
  entirely when the gutters cannot hold them.
- 64px desktop chassis gutter, 40px laptop, 24px tablet, 18px phone.
- Section vertical spacing: 128–176px desktop and 80–112px mobile.
- 1px semantic rails and dividers.
- Marketing containers use a restrained softened radius derived from the icon.
  Different roles use consistent shell, product-frame, and control radii.
- Real Agent Studio windows preserve their native titlebar and control radii.
- Product imagery is front-facing. Do not tilt screenshots into decorative perspective.
- Shadows are unnecessary for ordinary surfaces. Depth comes from plane offset, rail color, and overlapping geometry.

## WebsiteCaptureSuite

### Master geometry

- Logical debug window: 1280×800 points.
- Master image: 2560×1600 pixels at 2× scale.
- Aspect ratio: 16:10.
- Source format: lossless Retina PNG with the capture display's embedded ICC profile.
- Master format: 2560×1600 sRGB IEC61966-2.1 PNG produced by deterministic ColorSync conversion from the untouched source.
- Capture target: exact Agent Studio debug window, including its real unified toolbar/titlebar.
- Background outside the application window is excluded.

### Shared fixture

Every master uses the same:

- debug application build and source revision;
- bundle identifier, executable identity, isolated data root, and fixture identity;
- window position, size, scale, theme, toolbar, and app appearance;
- state-specific Agent Studio sidebar visibility and width from the required
  master contract;
- repository/worktree names and ordering;
- pane arrangement and terminal font scale;
- terminal density, prompt hygiene, and product content tone;
- capture tool, source color profile, normalization profile, and conversion command identity.

Peekaboo captures an untouched native-window source after the operator has staged and verified the dedicated debug process with Sky. For every shot, the operator resolves the current CoreGraphics window ID from the verified PID, captures that window ID at Retina scale, and records both identities. Window titles are descriptive evidence only because the debug window currently exposes the generic title `AgentStudio`. Peekaboo does not own marketing emphasis, labels, crops, color normalization, or per-shot visual judgment.

ColorSync converts each untouched source to the canonical sRGB IEC61966-2.1 master without resizing. Both source and master hashes and ICC identities are recorded. HyperFrames consumes only the normalized master.

No image may contain personal paths, credentials, private repositories, notifications, unrelated applications, random shell history, cursor, selection artifacts, or transient animation blur.

### Focus isolation treatment

The campaign name for the example treatment is **focus isolation**: a contextual spotlight made from one truthful capture, a uniform dark scrim over the non-focal workspace, and an unmodified full-value focal region. HyperFrames owns this treatment for both settled website stills and animated video frames.

- Preserve every untouched Peekaboo source as capture evidence and every sRGB-normalized master as the campaign source.
- Build the emphasis derivative from one untouched master plus uniform scrim
  segments outside the approved product-shaped focus region; focal pixels remain
  uncovered.
- Do not blur, sharpen, recolor, regenerate, rewrite, or reconstruct any Agent Studio pixels.
- Use one campaign-wide scrim strength. Edge treatment follows the real product
  boundary and may be omitted when a rail would invent a box around a multi-pane
  reading path.
- Keep focus geometry aligned to real product boundaries such as pane, drawer, command surface, file tree, or diff edges.
- A subtle one-pixel blue/cyan rail may identify the active boundary; glow, bloom, and gradient halos are not used.
- State labels and explanatory copy remain outside the captured app surface.
- HyperFrames snapshots the settled focus states for website assets. The same masks may move between approved regions in video, using the campaign's rigid 120–200ms focus timing.

The treatment emphasizes ownership without pretending that the dimmed state is a separate product mode. Every derivative records its source master, normalized focal mask, scrim settings, settled frame time, output dimensions, and SHA-256.

### Required masters

#### `parallel-work.png`

- The Agent Studio Pane/All Panes sidebar is visible.
- Two or three panes show distinct named-agent contexts.
- Real pane notes, activity, Git, and recency context may appear naturally in
  the pane sidebar; they are supporting evidence rather than added callouts.
- One pane is clearly focused through current product selection treatment.
- Background panes remain legible and visibly parallel.
- Focal region: full window; no crop may remove the sidebar-to-pane relationship.
- Emphasis derivative: sidebar topology and all parallel panes remain at full value; only surrounding marketing canvas is muted. This is the establishing state and does not isolate one pane prematurely.

#### `pane-drawer.png`

- Same fixture and arrangement family.
- The global Agent Studio sidebar is hidden.
- One primary agent pane is selected.
- Its drawer is open with shell/build/review/browser context visibly attached.
- Main pane and drawer ownership remain readable together.
- Focal region: selected pane plus full drawer; sidebar may remain as contextual edge.
- Emphasis derivative: selected pane and attached drawer remain at full value while the rest of the captured workspace is uniformly muted.

#### `quick-find.png`

- Same fixture behind the command surface.
- The global Agent Studio sidebar is hidden so it does not compete with Quick
  Find as the active navigation surface.
- Command-P is open with the repository/worktree scope selected.
- Result rows show believable current fixture names and open-pane context.
- The `#`, `$`, and `>` scope model is visible without filling the frame with instructions.
- Focal region: command surface and enough background workspace to establish location.
- Emphasis derivative: Command-P and its result surface remain at full value; the surrounding workspace stays visible under the scrim.

#### `review.png`

- Same fixture worktree and agent context.
- The global Agent Studio sidebar is hidden.
- Agent terminal remains visible beside Review.
- Review's Changed Files tree remains fully visible whenever Review is shown.
- A modest, readable unified diff is visible; a narrow side-by-side diff is not
  accepted for this website capture.
- Diff content contains no secrets, personal paths, generated noise, or roadmap-only UI.
- Focal region: terminal-to-file-tree-to-diff relationship.
- Emphasis derivative: one contiguous stepped mask preserves the terminal-to-file-tree-to-diff reading path; it must not spotlight the diff alone.

#### `git-pull-request-context.png`

- The Agent Studio repository sidebar is visible.
- Exactly two agent/terminal panes are visible beside it.
- Review and Files are not shown; their viewer story belongs to the dedicated
  Review capture, where the global sidebar is hidden.
- One understandable repository and a small number of real worktrees remain
  readable.
- Branch, dirty state, ahead/behind state, pull-request context, and related
  pane ownership are real app-owned evidence.
- The frame avoids duplicating the Parallel work composition: repository and
  Git/PR context are the subject, while agent panes provide supporting context.
- Focal region: repository sidebar through the related active pane or PR
  surface.

### Derivatives

Derivatives are generated from masters, not recaptured.

- Interactive plate desktop uses the full 16:10 master.
- Long-form sections use art-directed crops recorded by source master and normalized focal box.
- Phone plate uses the locked state strategy below; the operator never chooses a crop:
  - Parallel work: full master.
  - Pane drawer: normalized focal box `(x: 0.23, y: 0.27, width: 0.72, height: 0.72)`.
  - Quick Find: normalized focal box `(x: 0.16, y: 0.10, width: 0.68, height: 0.68)`.
  - Review: normalized focal box `(x: 0.22, y: 0.18, width: 0.74, height: 0.74)`.
  - Git/PR context: art-directed detail preserving the repository sidebar and
    related active work surface.
- If an approved capture cannot preserve its named UX claim with the locked focal box, return to Visual Design; do not improvise during capture or implementation.
- Persistence media, when added to the expandable details, preserves the
  complete before/restored sequence and is not reused as a primary plate state.
- Every derivative records output dimensions and SHA-256 in the product projection.
- HyperFrames is the deterministic derivative renderer for focus isolation and campaign crops; Astro may perform delivery-format optimization from those approved outputs.

## Image-plate interaction

Desktop:

- Selector rail remains left of the image.
- One image panel is exposed at a time.
- State label and explanation live outside the capture.

Mobile:

- Selector rail becomes a horizontally scrollable tab row above the image.
- The selected tab scrolls into view without moving document focus.
- Image stays below the tabs and uses the approved master/crop.
- No overlay copy obscures the product.

Before enhancement, Parallel work is the only exposed image and selectors are disabled. Successful enhancement enables the tab contract without moving focus.

## Motion

Website motion is functional and uses the app's existing timing character:

- Fast selection/rail response: 120ms.
- Standard panel handoff: 200ms.
- Panel change: outgoing image resolves immediately while the incoming image uses a restrained opacity plus 8px translation; no scale blur or 3D rotation.
- Rear plane markers may offset during hero composition, but the real product image never tilts.
- The hero's cinematic motion comes from the HyperFrames loop, not duplicated DOM animation.
- Screenshot sections do not all animate on scroll. Rails or one focal caption may reveal only when the motion explains structure.
- Timers/spinners in captured images are frozen. Any HTML ambient indicator is optional, bounded, and stops when hidden.

Reduced motion shows the video poster, switches image states instantly, and disables nonessential rail movement.

## Responsive composition

### Wide desktop, 1440px chassis

- Hero copy occupies approximately two thirds of the chassis width.
- Video and plate span the chassis.
- Product plate selector is 280px; image owns the remaining width.
- Screenshot sections alternate composition while keeping large product surfaces.

### Laptop, 1024–1279px

- Hero type scales down but preserves two lines.
- Plate selector narrows to 220px.
- Screenshot copy stacks above the image when side-by-side layout makes the UI unreadable.

### Tablet, 768–1023px

- Page-local chrome reduces to identity, GitHub, and Install.
- Plate selector becomes horizontal tabs.
- Screenshot sections stack copy then image.

### Phone, 360–767px

- Hero type remains dominant without clipping.
- Install command wraps as one selectable block.
- Video poster and plate remain 16:10 within the viewport.
- Tabs scroll horizontally with visible focus and selected state.
- Screenshot crops preserve the named product feature; no tiny full-window image is accepted merely because it technically fits.

## Design-board contract

The design board shows, at minimum:

1. token and typography reference;
2. desktop page overview;
3. desktop hero/video poster;
4. each of the five image-plate states;
5. the expandable feature-list treatment, including persistence;
6. the final call to action;
7. mobile hero and mobile image plate;
8. capture-master matrix with focal regions and status.

Temporary README images may appear only as clearly labeled composition references until the WebsiteCaptureSuite is produced. They are not visual approval of final website imagery.

## Visual acceptance

The visual direction is ready for Astro implementation when:

- every board frame reads as one Agent Studio campaign without motion;
- product UI remains the dominant proof surface;
- every selected state has one explicit master and focal region;
- desktop and mobile compositions preserve the same hierarchy;
- blue/peach semantics remain consistent;
- screenshot sections avoid repeated-card rhythm;
- reduced-motion frames remain complete;
- no final asset slot depends on an historical README image or an unmade capture decision.
