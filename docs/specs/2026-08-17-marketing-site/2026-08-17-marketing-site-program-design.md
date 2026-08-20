# Agent Studio Marketing Site Program Design

Requirements: [2026-08-17-marketing-site-requirements.md](2026-08-17-marketing-site-requirements.md)

Specification: [2026-08-17-marketing-site-specification.md](2026-08-17-marketing-site-specification.md)

## Structural direction

The website is a new static Astro application under the existing `web/` boundary. Astro owns page composition and static HTML. Tailwind v4 and semantic CSS own layout and visual tokens. A small TypeScript controller owns the clickable workspace state. Native HTML owns video and images. Cloudflare Pages serves the generated static output.

React is not part of the initial runtime. Astro already provides the component boundary needed for static composition, and Herdr proves the required plate behavior does not need a virtual-DOM runtime. The interactive workspace retains an explicit future island boundary: if its state, composition, or independent testing becomes materially clearer in React, that one component can move to `@astrojs/react` without changing the page shell.

## Why this direction is smaller

Three credible structures were considered:

| Direction | Gain | Cost | Disposition |
| --- | --- | --- | --- |
| Astro plus typed DOM controller | Zero hydration framework, server-rendered fixture, direct accessibility ownership, smallest runtime | Controller must keep state and DOM semantics synchronized | Selected |
| Astro plus one React island | Declarative state/render composition and familiar React tests | React runtime and hydration for a behavior currently proven simple | Revisit when the plate exceeds the threshold below |
| One page-wide React application | One rendering model | Hydrates static marketing content, weakens Astro component reuse, raises fallback cost | Rejected |

The selected debt is a small imperative synchronization layer. The website maintainer pays that cost. Revisit the React island if the plate gains nested independently updating controls, asynchronous data, shared state across page sections, or enough conditional composition that static panels and one reducer are harder to understand than a component tree.

## Integrated component model

```text
MarketingSite
├── VerifiedProductProjection
├── SiteShell
│   ├── DocumentHead
│   ├── Navigation
│   └── Footer
├── Hero
│   ├── PositioningCopy
│   ├── InstallActions
│   └── ProductVideo
├── InteractiveWorkspaceDemo
│   ├── DemoStateSelector
│   ├── DemoPanels
│   └── DemoController
└── FinalInstallCallToAction
```

### VerifiedProductProjection

Owns the checked-in marketing values and provenance consumed by the site: campaign copy and shipped claims, install command, semantic token projection, approved icon/logo copies, capture-suite manifest, derived image identities, poster, and immutable promotional-video reference. Each entry names its current owner and last-verified revision or content identity.

The production site reads this projection only. A separate verification boundary compares it with current owners before promotion; comparison never rewrites the projection automatically.

### SiteShell

Owns document structure, canonical metadata input, page-local chrome, page-width frame, and global style imports. Navigation and Footer are not information-architecture owners: they may contain only Agent Studio identity, in-page section anchors, and the same install/GitHub destinations already governed by R2 and R8. They do not authorize additional routes, Docs/Blog/Changelog destinations, or a multi-page site. SiteShell does not own product-demo state or product claims.

### Hero

Owns first-viewport composition. ProductVideo owns its media element, poster, playback controls, and reduced-motion response. InstallActions owns the visible install command, GitHub link, and clipboard enhancement boundary.

### InteractiveWorkspaceDemo

Owns the explanatory fixture as a unit. DemoStateSelector and DemoPanels are Astro-rendered views over one immutable mapping from state identifiers to frozen capture assets. DemoController is the only client state owner and the only writer of active selection, visible image panel, and focus movement. It never reconstructs app UI or derives active-agent state from HTML.

### WebsiteCaptureSuite

Owns six frozen 2560×1600 sRGB capture masters and their manifest: Parallel
work, Pane drawer, Quick Find, Review, Persistent before, and Persistent
restored. One stable capture lineage, source revision, built executable, bundle
identifier, isolated data root, fixture identity, and 1280×800 window contract
produces the suite. Every state uses two or three readable primary panes. One
capture operator follows one approved shot matrix and may not change lineage,
geometry, fixture content, or visual design while recording.

The first five masters, including `persistent-before.png`, belong to process generation A with a verified PID and window identity. The operator closes only generation A through its verified identity, relaunches the same bundle and isolated data root, then verifies the new PID and window identity as process generation B. Before any restored-state action, generation B produces an untouched proof capture. Only after internal state equivalence is recorded may the verified window be normalized to the fixed capture bounds for `persistent-restored.png`. No PID, window identifier, or accessibility snapshot crosses the restart boundary.

Sky owns semantic control of the verified dedicated debug app. Peekaboo resolves a current CoreGraphics window ID from the verified PID and owns window-ID-targeted lossless Retina capture plus source verification. ColorSync owns deterministic conversion from the captured display ICC profile to the canonical sRGB IEC61966-2.1 master without resizing. A shared HyperFrames FocusIsolation composition consumes only that master and owns campaign emphasis and settled still export. It renders one untouched master plus uniform contextual-scrim segments outside the per-story product-shaped focus region. Astro consumes approved exported assets; it does not reproduce the focus treatment independently.

WebsiteCaptureSuite is an asset-production boundary, not runtime state. It changes when the approved app build, fixture, capture geometry, or visual contract changes. Every derivative records its master, focal mask, treatment settings, settled snapshot time, output geometry, and hash.

### Brand styles

Website semantic tokens are consumed from VerifiedProductProjection. Tailwind `@theme` variables expose layout utilities; ordinary CSS variables own values that must not create utilities. Marketing component CSS owns the product plate and stacked-plane treatments that are too semantic for utility-only expression.

## Ownership and dependency direction

```text
current product owners
  README · AppStyles · BridgeWeb tokens · canonical icon · debug app · approved video
                        │ verification only; never automatic adoption
                        ▼
WebsiteCaptureSuite ──► VerifiedProductProjection ──► Astro content/components ──► static HTML
          │
          ├──► semantic CSS/Tailwind
          ├──► native image/video elements
          └──► DemoController TypeScript enhancement
                                      │
                                      ▼
                             plate DOM state only
```

Allowed dependencies:

- pages depend on SiteShell and page components;
- pages, styles, and media components consume VerifiedProductProjection rather than parsing current owner files or historical README screenshots;
- Astro components depend on typed content/fixture data and semantic styles;
- DemoController depends only on the demo's DOM contract and typed fixture identifiers;
- tests may drive the built public surface and observe semantic state;
- deployment consumes only static output.

Forbidden dependencies:

- marketing components must not import Bridge transport, Bridge app state, native automation, workspace persistence, or generated BridgeWeb assets;
- DemoController must not call Agent Studio, shell, filesystem, repository, or network APIs;
- the page must not add screenshot sections that repeat interactive-demo states;
- deployment must not require a Workers entry point or binding;
- native application code must not depend on website packages.
- production rendering must not select unverified current-owner values or the newest external media implicitly.

Static dependency rules and tests enforce these edges; directory location alone is not considered enforcement.

## Behavioral interfaces

### Demo fixture contract

The fixture supplies a closed set of `DemoState` records. Each record contains a stable identifier, visible label, accessible description, frozen capture identity, intrinsic dimensions, and focal metadata. Fixture records are build-time content, not runtime input.

Consumers may enumerate states and render their image panels. They may not reconstruct the app UI, add a runtime state, execute a command, or derive a product claim absent from the verified fixture source.

### Demo controller contract

Pre-enhancement contract:

- Astro renders only the Parallel work panel as exposed content;
- selector controls are disabled, absent from the focus order, and do not expose tablist/tab semantics;
- delayed or missing TypeScript leaves this contract unchanged.

Initialization inputs:

- a root element containing one selector and matching panels;
- the closed set of valid state identifiers;
- disabled selector controls and matching panels emitted by Astro.

Initialization validates the full root, state-id, selector, and panel correspondence before the first DOM write. After validation, one synchronous activation installs listeners and tab relationships, establishes roving focus, and enables selectors. Activation does not move focus. If activation cannot complete, the controller disables every selector and restores the Parallel work panel before returning failure.

Postconditions after a valid selection:

- exactly one selector is selected;
- exactly one panel is exposed as current;
- focus follows the documented keyboard model without being stolen on pointer selection;
- the active state does not change browser location or external state;
- any derived active-agent indicator is consistent with the selected panel.

Invalid or missing identifiers leave the last valid state intact. Repeated selection of the current state is idempotent. No state persists across page loads.

### Product video contract

ProductVideo receives approved source and poster URLs plus accessible context. It owns playback behavior but no global page state. Reduced motion initializes poster-first. Media errors preserve the poster and explanatory copy.

### Install action contract

InstallActions renders the current verified command in HTML. Client enhancement may copy the exact command and publish a transient status. Clipboard rejection must not hide or mutate the command.

## Interactive state model

DemoController owns one transient state:

| State | Entry | Visible panel | Exit |
| --- | --- | --- | --- |
| `parallel-work` | Page load or explicit selection | Parallel panes | Select another valid state |
| `pane-drawer` | Select Pane drawer | Main pane and attached drawer | Select another valid state |
| `quick-find` | Select Quick Find | Command bar scopes | Select another valid state |
| `review` | Select Review | Agent terminal and continuous diff | Select another valid state |
| `persistent-workspace` | Select Persistent workspace | Before/after restored arrangement | Select another valid state |

Illegal transitions do not exist between valid states because every selection is a direct replacement. Unknown state identifiers are rejected without changing the last valid state. Page unload disposes listeners and transient timers; reload returns to `parallel-work`.

The Persistent workspace panel is one pre-authored split composition containing `persistent-before.png` and `persistent-restored.png`, simultaneously visible and explicitly labeled Before close and Restored. Both images come from the same fixture and geometry. It has no nested selector, timer-driven state transition, automatic playback, or implied live attachment. Selecting Persistent workspace performs only the same one-state panel replacement as every other demo state.

Ambient motion is derived presentation, not state. It starts only when visible and permitted by motion preferences, and stops when the demo leaves the viewport, the document becomes hidden, or reduced motion is requested.

## Entrypoint-to-effect paths

There is no current website runtime predecessor; `web/` is image-only. The following paths are proposed additions.

### Selecting a product story

```text
visitor click or keyboard activation
  ──► semantic selector control
  ──► DemoController validates state id
  ──► DemoController updates selected semantics and exposed panel
  ──► browser renders the chosen pre-authored screen
  ◄── no URL, storage, network, filesystem, or native-app effect
```

The controller returns by visible and programmatic selection state. Invalid input returns by preserving the previous valid screen.

### Loading the page

```text
HTTP request
  ──► Cloudflare Pages static asset
  ──► server-independent HTML/CSS/poster render
  ──► optional TypeScript validates complete demo contract without DOM writes
  ──► synchronous activation enables tab semantics, listeners, and roving focus
  ──► demo becomes interactive and video follows motion policy
```

If validation or activation fails, the path ends in the complete static render with disabled selectors and only Parallel work exposed. Delayed activation cannot steal focus because disabled selectors are outside the focus order and activation preserves the document's current focus.

### Copying installation

```text
visitor activates Copy
  ──► typed clipboard controller reads verified command element
  ──► Clipboard API resolves or rejects
  ├── success: visible copied status
  └── failure: visible unavailable status; command remains selectable
```

## Failure and recovery

| Boundary | Detection | Containment | Recovery truth | Visitor outcome | Proof seam |
| --- | --- | --- | --- | --- | --- |
| Demo controller load/initialization | Module, validation, or activation failure | Demo enhancement only | Disabled selectors plus static Parallel work panel | Default panel remains visible; no inoperable tab contract is announced | Blocked, delayed, and partial-initialization browser cases |
| Unknown demo state | Controller validation | Reject selection | Last valid state | No inconsistent selector/panel pair | Invalid-state controller case |
| Video autoplay blocked | Playback promise/media state | ProductVideo only | Poster plus explicit control | Product proof remains visible | Browser media-state observation |
| Video source error | Media error event | ProductVideo only | Poster and copy | No blank or collapsed hero | Media-error fixture |
| Clipboard rejection | Rejected Clipboard API | Install status only | Rendered command text | Command stays selectable | Denied clipboard case |
| Screenshot load failure | Image error/loading state | Owning demo panel | Selector copy and layout shell | Story remains understandable, degraded visually | Browser resource-failure case |
| Cloudflare build failure | Build/check status | Preview or deployment | Last successful production artifact | Failed candidate is not promoted | Deployment status/artifact evidence |

There are no retries for demo state, images, clipboard, or video. Reload is the recovery for client initialization. Cloudflare owns build retry policy outside the site runtime; the website does not add a deployment control plane.

## Concurrency and consistency

The demo has one synchronous controller and one current state. Rapid selections are processed in event order and each complete update establishes exactly one selected control and panel before the next event. No asynchronous selection work, remote data, persisted state, or shared worker exists.

Timers and media events may overlap with selection, but they cannot write selection state. Disposal and visibility/motion guards prevent background intervals from becoming a second lifecycle owner.

Current product owners may change independently. The website build consumes only VerifiedProductProjection, so a source change cannot alter published meaning automatically. Promotion verification compares each projection entry with its named owner: README for shipped claims and install facts; `AppStyles.primaryHex` and named BridgeWeb semantic roles for app theme values; `AppIcon.svg` for stacked-plane palette and geometry; approved website copies for icon/logo use; the WebsiteCaptureSuite manifest plus image hashes for product stills; and an immutable URI plus content hash for cross-repository promotional video. Historical `web/images/` remain README evidence and are not website production owners. Mismatch blocks promotion and never selects a replacement value implicitly.

## Accessibility realization

- Astro emits disabled selector controls, no live tab contract, and one exposed Parallel work panel before enhancement.
- DemoController validates before mutation, then enables the WAI-ARIA tab model and roving focus without moving focus; failure restores the disabled static contract.
- Focus appearance belongs to semantic CSS and is not suppressed by mouse styling.
- Reduced-motion CSS and controller guards disable nonessential motion; ProductVideo starts poster-first.
- Screen reader labels describe the product story, not every decorative terminal line.
- Narrow layouts keep the selector and primary panel readable, while secondary panes may collapse according to specification.

## Static deployment and cutover

The new site has no predecessor deployment. During development, the repository README continues to serve as the public product source. A production cutover occurs only after Cloudflare Pages serves the approved static artifact at the owner-selected canonical domain.

Cloudflare Pages owns static hosting and preview generation. Astro's output remains host-neutral static content. No Cloudflare adapter or Vite Workers plugin is present. If server behavior is later authorized, that change requires a new design because it adds a runtime owner, failure boundary, and deployment contract.

Rollback selects the preceding successful static Pages deployment. No website data reconciliation is required because the site writes no durable state.

## How requirements are realized and proved

| Requirements | Realization owner | Observable seam | Required reality |
| --- | --- | --- | --- |
| R1, R12 | Astro static build and SiteShell | Built HTML before enhancement | Real static output; client module may be blocked |
| R2, R3, R9 | Hero, InteractiveWorkspaceDemo, semantic styles | Rendered page hierarchy | Real copy, brand sources, poster or approved loop, and images |
| R4 | ProductVideo | Media state and reduced-motion boundary | Real browser media element; source failure may be substituted |
| R5, R6 | Demo fixture, selector/panels, DemoController | Semantic and visual selected state | Real DOM and controller; no native app connection |
| R7 | WebsiteCaptureSuite and InteractiveWorkspaceDemo | Manifest-verified masters, responsive derivatives, and alternative text | Real dedicated debug captures and recorded crop provenance |
| R8 | InstallActions | Link and clipboard success/failure | Real link; clipboard may be allowed or denied |
| R10 | Website configuration and source boundary | Static/type-aware analysis | Real Astro and TypeScript source |
| R11 | SiteShell, components, semantic styles, controllers | Multiple viewport, keyboard, assistive technology, reduced motion | Real supported browsers |
| R13 | Cloudflare Pages deployment | Pull-request preview and production artifact | Real Cloudflare environment |
| R14 | VerifiedProductProjection and promotion verifier | Projection-to-owner comparison before deployment | Real repository owners, checked-in projection identities, and immutable video provenance |

Structural invariants use these enforcement classes:

- types and closed identifiers for fixture state;
- runtime guards for invalid selection and missing DOM contracts;
- semantic browser behavior tests for selector/panel invariants;
- static rules preventing JavaScript source and forbidden Bridge imports;
- build checks for Astro/TypeScript/static output;
- visual and accessibility evidence for the rendered product surface;
- deployment evidence for preview and production.

## Revisit signals

Reconsider a React island when at least one occurs:

- the demo adds nested independently stateful controls beyond one selected screen;
- panels require asynchronous data or a shared client cache;
- the controller must create/destroy substantial conditional DOM rather than expose pre-rendered panels;
- multiple page regions need the same live client state;
- component-level composition and tests are demonstrably clearer than the static-panel contract.

Reconsider Cloudflare Workers when a confirmed requirement adds server actions, authentication, dynamic personalization, runtime content, analytics ingestion, or bindings. Neither threshold is met by the current specification.
