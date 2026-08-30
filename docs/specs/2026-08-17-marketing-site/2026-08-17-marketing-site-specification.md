# Agent Studio Marketing Site Specification

Requirements authority: [2026-08-17-marketing-site-requirements.md](2026-08-17-marketing-site-requirements.md)

## Observable product contract

The marketing site is a statically delivered public homepage. It must communicate one promise: Agent Studio lets developers run more coding agents while staying oriented across repositories, worktrees, panes, attached tools, navigation, Git/pull-request state, review, and persistent sessions.

The page must remain useful as HTML before client behavior runs. Client TypeScript enhances bounded controls; it does not own the page's primary content or make the product story disappear when unavailable.

## Visitor journey

1. The visitor sees the product name, category, campaign promise, short explanation, install action, GitHub action, and recognizable Agent Studio product proof in the first viewport.
2. The visitor can watch a short silent product loop or receive its representative poster when autoplay is inappropriate or unavailable.
3. The visitor can operate a clickable Agent Studio workspace and inspect five shipped product stories.
4. The visitor can expand a restrained follow-up feature list for persistence
   and other approved supporting details without replaying the five primary
   stories.
5. The visitor reaches a final installation and GitHub invitation after that
   detail list, without repeated feature sections or a contradictory visual
   system.

## Page composition requirements

### R1 — Static delivery

The site MUST build into static assets that can be served without an application server, server-side rendering process, Cloudflare adapter, Workers entry point, or runtime binding.

If client TypeScript fails to execute, the page MUST retain its hero copy, install command, GitHub link, default interactive-plate screen, screenshot proof, and final call to action.

Basis: U1, U4, U7.

### R2 — Claim-first hero

The first viewport MUST contain:

- Agent Studio identity;
- the promise “Run more agents. Stay oriented.” or owner-approved successor copy with the same meaning;
- the category “native macOS workspace for coding agents”;
- a concise explanation of repository/worktree-centered organization;
- the current Homebrew install action;
- a GitHub action;
- visible product proof rather than decorative illustration alone.

The hero MUST NOT claim support for planned review comments, whole-workspace dynamic regrouping, or sandbox/runtime security features as shipped.

Basis: U1, U4, U8.

### R3 — Two complementary proof modes

The page MUST provide two proof modes without making them compete at equal visual weight in one viewport:

1. recognizable real product imagery in the hero, using an approved poster
   until a shared silent website loop is ready;
2. an interactive product-faithful workspace after the hero.

The interactive workspace MUST contain the five primary screenshot stories. A
single expandable feature list MAY follow it for persistence and other approved
supporting details. That list MUST NOT repeat the five primary stories as
long-form sections.

Basis: U2, U3.

### R4 — Hero video behavior

The hero video MUST use real approved Agent Studio capture or a composition derived from it. It MUST be muted and inline when autoplaying, MUST loop only while appropriate, and MUST have a representative poster.

When reduced motion is requested, the site MUST present the poster without automatic playback and MUST provide an explicit way to start and stop playback if video remains offered.

If no supported source loads, the representative poster and surrounding product copy MUST remain visible; a blank or collapsed product frame is a failure.

Basis: U2, U5.

### R5 — Interactive workspace states

The interactive workspace MUST offer exactly these initial product stories:

| State | Purpose-made capture | Current claim demonstrated |
| --- | --- | --- |
| Parallel work | Wide workspace with multiple named agent panes and the Agent Studio Pane/All Panes sidebar | Parallel work stays separate but visible; pane notes and activity provide real orientation context |
| Pane drawer | The same fixture with the global Agent Studio sidebar hidden and one main pane plus related tools visibly attached beneath it | One unit of work keeps its context in its drawer |
| Quick Find navigation | The same fixture with the global Agent Studio sidebar hidden and Command-P showing one meaningful scope | Visitors understand keyboard-first navigation without a competing navigation surface |
| Review | The same fixture with the global Agent Studio sidebar hidden, agent terminal beside the always-visible Review Changed Files tree, and a readable unified diff | Review stays beside the work that produced it |
| Git and pull-request context | The same fixture with the Agent Studio repository sidebar showing real worktree, branch, dirty/ahead/behind, and pull-request context beside two agent/terminal panes; Review and Files are not shown | Repository and pull-request state stays attached to the work instead of becoming another place to hunt |

The default state MUST be Parallel work. Selecting a state MUST change only the plate's displayed workspace and selection semantics; it MUST NOT navigate the page, change the browser URL, run commands, access local files, or imply a live connection.

All screens MUST use frozen captures from one approved capture suite. The selector changes the displayed capture; it MUST NOT reconstruct or approximate the Agent Studio UI in HTML. Ambient HTML labels may identify the selected story but MUST NOT cover the product feature or fabricate live state.

Basis: U2, U3, U8.

### R6 — Interactive semantics

After successful enhancement, every plate selection MUST be a semantic control. The state selector MUST expose one selected item and one associated panel at a time.

Keyboard users MUST be able to enter the selector, move among states, activate a state, and reach the selected panel without pointer input. Focus MUST remain visible. Selection and panel relationships MUST be programmatically exposed to assistive technology.

Before client enhancement succeeds, the Parallel work screen MUST be the only exposed panel. Selector labels MUST remain non-operable: they MUST be disabled, absent from the focus order, and MUST NOT expose a live tablist/tab contract.

The controller MUST validate the complete root, state, selector, and panel contract before changing any operability or selection semantics. After validation, it MUST enable the selector, tab relationships, roving focus, and event handling as one synchronous transition without moving existing focus. If initialization is delayed, unavailable, or fails before or during that transition, the plate MUST remain or return to the non-operable Parallel work state.

Basis: U5.

### R7 — Capture-backed clickable story

The clickable product plate MUST contain these capture-backed stories:

| Story | Capture master |
| --- | --- |
| Parallel work | `parallel-work.png` |
| Pane drawer | `pane-drawer.png` |
| Quick Find navigation | `quick-find.png` |
| Review | `review.png` |
| Git and pull-request context | `git-pull-request-context.png` |

Persistent terminal sessions no longer occupy a plate state. They move to the
expandable feature list governed by R15. The existing repository-relative
README image locations MUST remain valid but MUST NOT be substituted for a
missing website capture.

Every primary capture master MUST be an sRGB IEC61966-2.1 PNG at 2560×1600 pixels,
representing a 1280×800-point Agent Studio window at 2× scale. All five masters
MUST use the same approved debug build, isolated fixture data root, app theme,
window chrome, typography scale, two- or three-pane density, capture method,
and deterministic color-normalization path. Sidebar visibility MUST follow the
state-specific contract in R5 rather than being forced to match across states. Four narrow panes,
large empty pane fields, cursor, desktop background, notifications, personal
paths, tokens, and unrelated apps MUST be absent.

Peekaboo MUST capture an untouched native-window source after the dedicated debug identity and fixture are verified. Every capture MUST resolve the current CoreGraphics window ID from the verified PID, target that window ID, and use native Retina PNG output. A window title MUST NOT be the sole capture selector. The source's embedded ICC profile MUST be recorded, then ColorSync MUST convert a copy to sRGB IEC61966-2.1 without resizing. Both hashes MUST be recorded, and the normalized copy becomes the master consumed by HyperFrames. Marketing emphasis MUST NOT be applied manually during capture or normalization.

Responsive and long-form variants MUST be generated as art-directed derivatives of the capture masters. They MUST NOT be independently recaptured with a different application geometry. A derivative MUST preserve the feature named by its state and record its source master and crop/focal metadata.

Focus-emphasis derivatives MUST be rendered deterministically through the shared HyperFrames focus-isolation composition. The derivative MUST use one untouched master with uniform scrim segments surrounding an approved rectangular focal region; focal pixels MUST remain uncovered. The treatment MUST NOT blur, recolor, regenerate, rewrite, or reconstruct product pixels. All states MUST share one scrim and edge treatment; only the focal region MAY differ. The projection MUST record the region, treatment settings, settled snapshot time, output dimensions, and content hash.

Images MUST preserve useful intrinsic dimensions, responsive sizing, meaningful alternative text, and readable crops. Narrow-screen presentation MAY crop or stack supporting composition, but MUST NOT make the relevant product feature illegible.

Basis: U2, U3, U8.

### R8 — Install and GitHub actions

Every displayed installation command MUST match the current README-supported command. Copying the command MUST provide a visible success result and MUST leave the command selectable if clipboard access fails.

GitHub actions MUST point to the canonical Agent Studio repository. External navigation MUST be distinguishable and must not replace the current page unless that is the control's visible purpose.

Basis: U4.

### R9 — Brand fidelity

The site MUST use the current Agent Studio semantic theme and canonical stacked-plane identity. Product primary blue denotes current/focused/interactive state; peach denotes parallel, related, or background work. Cyan remains a scarce logo or glyph detail.

The site MUST NOT use Herdr's lilac palette, ram identity, terminal fixtures, or copy. Marketing geometry may borrow its large typography, constrained frame, rails, and product-first hierarchy.

Basis: U8.

### R15 — Expandable feature details

A restrained expandable feature list MUST follow the interactive workspace and
precede the final call to action. Persistent terminal sessions MUST appear in
this list rather than as one of the five primary screenshot states. Additional
rows MAY cover other owner-approved shipped capabilities that do not duplicate
the primary stories.

Each row MUST expose a short human-readable heading and plain description while
collapsed. Activating the row MUST reveal its details inline without navigating
away. Expanded content MAY include a focused approved image or silent clip when
that media adds proof; decorative placeholder media is forbidden.

The list MUST use native or equivalently complete disclosure semantics, remain
understandable before client enhancement, expose expanded/collapsed state to
assistive technology, and support keyboard operation. It MUST NOT autoplay,
open every row by default, or become a card grid that competes with the primary
product showcase.

Basis: U2, U3, U5, U8.

### R10 — TypeScript boundary

All authored website application logic and executable JavaScript/TypeScript toolchain configuration MUST be TypeScript. Plain JavaScript, JSX, and MJS application or executable configuration source files are not part of the supported website system. Declarative package manifests, lockfiles, structured data, stylesheets, and CI/deployment YAML or JSON are permitted and do not weaken the TypeScript application boundary.

Astro component frontmatter and client scripts MUST participate in strict website type checking. A successful transpile without Astro and TypeScript checking is insufficient proof.

Basis: U6.

### R11 — Responsive and accessible interpretation

The complete page MUST remain navigable and understandable at narrow phone, tablet, laptop, and wide desktop viewports. A narrow interactive plate MAY simplify secondary panes, but MUST preserve selector access, selected-state identity, and the primary product story.

Nonessential animation MUST honor reduced-motion preferences. Color MUST not be the only indication of selection, status, or focus. Text and interactive controls MUST meet WCAG AA contrast at their rendered sizes.

Basis: U5.

### R12 — Client-cost boundary

Static sections MUST ship without hydration. The initial implementation MUST NOT load React or hydrate a page-wide component tree.

If a later approved interactive component uses React, only that bounded island MAY hydrate, and its server-rendered content MUST remain useful before hydration. The rest of the page remains Astro-rendered static HTML.

Basis: U6, U7 and the authorized “React only if necessary” constraint.

### R13 — Cloudflare previews and production

The repository MUST be able to produce a Cloudflare Pages preview for pull requests and a production static deployment from the designated production branch. The published artifact MUST be the site's static output directory.

The first release MUST NOT require `@astrojs/cloudflare` or direct `@cloudflare/vite-plugin` configuration. Adding either requires a newly authorized server or Workers capability.

Basis: U7.

### R14 — Source freshness

The site MUST publish checked-in, website-owned projections of product claims, installation commands, capture masters and derivatives, icons, semantic colors, and promotional video references. Each image projection MUST include the debug build revision, executable identity, fixture identity, isolated data-root identity, process generation, PID-to-window-ID binding, capture dimensions, scale, source ICC profile and hash, normalization profile and master hash, source master, crop/focal metadata where applicable, and derivative content hash. The production build MUST consume the checked-in projections; it MUST NOT silently derive published marketing meaning from the current repository HEAD, historical README screenshots, or the newest external media file.

Before promotion, every projection MUST be compared with its named current owner. A missing owner, mismatched value, changed asset, or absent immutable video identity MUST block promotion while leaving the checked-in last-verified projection available for local rendering and the preceding production deployment. Campaign copy MAY use website-owned wording, but every shipped capability and installation fact it expresses MUST remain traceable to the README authority.

Basis: U8.

## Failure and partial-success behavior

| Failure | Required visible outcome |
| --- | --- |
| Client controller is delayed, unavailable, or fails initialization | Static page and default Parallel work plate remain visible; selectors remain disabled and non-operable |
| Video cannot autoplay | Poster remains; playback can be started explicitly where supported |
| Video source fails | Poster and product copy remain; no empty product frame |
| Clipboard permission or API fails | Install command remains selectable and a non-success status is shown |
| Optional image fails | Layout retains its caption/context and does not shift into an unusable state |
| Cloudflare preview build fails | No preview is promoted as deployable; failure is visible in repository checks |
| A product projection cannot be verified | Promotion is blocked; the checked-in last-verified projection and preceding production deployment remain unchanged |

## Compatibility and negative space

- Supported behavior is a public static website in current evergreen browsers.
- JavaScript-disabled visitors receive the default product story but not state switching or clipboard enhancement.
- The clickable workspace is an explanatory fixture, not a compatibility promise for the native app's DOM, bridge protocol, persistence format, or automation API.
- No compatibility is promised for undocumented fixture data fields.
- No offline installation guarantee is introduced.
- No analytics, personalization, accounts, or cross-session website state is defined.

## Requirement-to-proof obligations

| Requirements | Evidence class | Observable boundary |
| --- | --- | --- |
| R1, R10, R12 | Automated behavior and static artifact inspection | Built output, HTML before client execution, type-check result |
| R2, R3, R7, R9, R11 | Manual visual evidence | Supported desktop and narrow viewports |
| R4 | Manual interaction plus media-state inspection | Autoplay, poster, controls, reduced motion, source failure |
| R5, R6 | Automated browser behavior plus accessibility inspection | Selection, panels, URL stability, keyboard and semantic state |
| R8 | Automated browser behavior plus link/clipboard observation | Install and GitHub actions, success and failure paths |
| R13 | Release/runtime evidence | Pull-request preview and production static deployment |
| R14 | Source inspection | Claim/asset owner comparison at release boundary |
| R15 | Automated browser behavior plus manual visual evidence | Disclosure semantics, inline expansion, non-duplicative content, and responsive layout |
