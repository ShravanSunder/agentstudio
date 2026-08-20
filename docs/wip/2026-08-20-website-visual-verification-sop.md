# Agent Studio website release and visual verification SOP

**Status:** mandatory release gate

**Owner:** Agent Studio maintainer

**Applies to:** website source, copy, styling, product captures, generated
assets, deployment packaging, launch assets, Cloudflare production, and
post-launch operation

**Result vocabulary:** `READY FOR OWNER REVIEW`, `APPROVED FOR RELEASE`,
`RELEASED AND VERIFIED`, or `NOT VERIFIED`

## Purpose

This SOP is the mandatory verification gate for Agent Studio website
development, styling, product imagery, responsive behavior, and Cloudflare
deployment. It prevents a default state, automated test, or one screenshot from
being generalized into a claim that the whole website is correct.

No website visual task or public release is complete until every affected state
is opened, inspected, captured, and compared in the environments and viewports
required by this document. Public release also requires product truth,
activation-path, distribution, monitoring, rollback, and post-launch gates.

## Release principles

1. **Build once, prove the artifact, release that artifact.** A release record
   binds source commit, lockfile, build environment, emitted assets, Cloudflare
   version, and evidence. Rebuilding during approval creates a different
   candidate.
2. **One passing state proves one state.** Every interactive state, breakpoint,
   and environment has independent evidence.
3. **Pixels and semantics are separate contracts.** Screenshot equality does
   not prove keyboard access, roles, focus, loading stability, or truthful
   product claims.
4. **DOM presence is not visibility.** Controls must have visible nonzero bounds
   in the browser used for release verification.
5. **Product evidence must show the product's category.** Agent Studio launch
   images need recognizable coding agents and organized parallel work, not
   generic terminals.
6. **Promotion is reversible.** The last known-good Cloudflare version and a
   tested rollback command exist before public promotion.
7. **Release continues after deployment.** Monitoring, response, feedback
   classification, and the post-launch review are part of the release.

## Release classes

Classify the change before creating evidence. Higher classes include all lower
class gates.

| Class | Examples | Required scope |
| --- | --- | --- |
| V0 local iteration | copy spacing, local CSS experiment | affected local states and widths; no deployment |
| V1 website correction | styling, responsive behavior, footer/header, one product state | full local matrix, browser tests, Cloudflare dry run, affected remote matrix |
| V2 campaign asset release | new screenshots, product-state narrative, hero loop, OG image | all six source assets, all five selector states, local and remote contact sheets, metadata/share-preview QA |
| V3 public product launch | homepage and campaign published to external channels | every technical and visual gate, channel readiness, monitoring, rollback, launch-day operations, post-launch review |

If classification is uncertain, use the higher class.

## Release authority and responsibilities

| Responsibility | Owner | Required evidence |
| --- | --- | --- |
| Product claims and shipped behavior | Agent Studio source/README owner | current source revision and claim mapping |
| Positioning, audience, proof, conversion action | product-marketing context owner | reviewed `agent-studio-media/.agents/product-marketing.md` version |
| Capture fixture and app identity | capture owner | bundle, executable, PID, data root, window ID, source revision |
| Website implementation | website implementer | source commit, tests, build, local evidence |
| Visual campaign quality | human owner | contact-sheet and normal-viewport approval |
| Cloudflare promotion | release owner | dry run, candidate manifest, version ID, rollback target |
| Launch-day response | named maintainer | monitoring window, incident route, channel response assignment |

The implementer cannot self-approve campaign quality by citing automated tests.
The owner cannot waive a failed integrity, accessibility, or production-runtime
gate without recording the exception and accepting the release risk.

## Product and positioning gate

Before a V2 or V3 release, read the current product-marketing context in Agent
Studio Media and confirm:

- one-line product category and target user are still accurate;
- the hero promise matches the actual problem and shipped product;
- the primary conversion action is singular and works end to end;
- every feature claim maps to a current source anchor and visual proof;
- objections raised by the website are answered by evidence, not adjectives;
- no unapproved customer, performance, adoption, security, compatibility,
  pricing, or productivity claim appears;
- terms such as pane, drawer, Review, Quick Find, worktree, active, and
  persistent match current product meaning;
- the campaign shows Claude Code, Codex, and Agy as required by the owner, or
  records why a named agent is not applicable to a specific state.

Unknown metrics remain unknown. Do not manufacture proof to complete a launch
checklist.

## Release identity and artifact manifest

Create a release record before final verification:

```text
release-id: <date>-<short-name>
release-class: V0 | V1 | V2 | V3
source-commit: <full SHA>
agent-studio-source: <full SHA used for claims/captures>
lockfile-sha256: <digest>
node-version: <exact>
pnpm-version: <exact>
astro-version: <exact>
cloudflare-cli-version: <exact>
browser-family-and-version: <exact>
os-and-architecture: <exact>
build-command: <exact>
artifact-directory: <path>
artifact-manifest-sha256: <digest>
candidate-cloudflare-version: <ID or pending>
last-known-good-version: <ID>
evidence-directory: <path>
owner-approval: pending | approved
```

Generate an artifact manifest containing every emitted file's relative path,
byte size, media type, and SHA-256. Confirm that built HTML references emitted
asset names in that manifest. Never substitute a new build after approval.

## Release gate overview

| Gate | Decision | Blocks release when |
| --- | --- | --- |
| G0 scope and ledger | requirements are complete and traceable | an owner correction or affected state is missing |
| G1 product truth | claims, audience, terminology, and conversion match current product | a claim is unsupported or named-agent proof is absent |
| G2 capture and asset integrity | sources, generated formats, alpha, dimensions, hashes, and corners pass | any asset is stale, unreadable, empty, cropped, or visually corrupt |
| G3 page and state visual QA | every state/viewport passes local production review | any state is inferred, omitted, inconsistent, or visually rejected |
| G4 accessibility and interaction | semantics, keyboard, focus, reduced motion, and fallback pass | a critical flow is inaccessible or state identity is ambiguous |
| G5 performance and stability | assets, Core Web Vitals budget, layout shifts, console, and network pass | launch experience is unstable or critical assets fail |
| G6 launch surface readiness | metadata, links, install path, docs, GitHub, support, and channel assets pass | discovery or activation leads to missing, stale, or misleading content |
| G7 immutable Cloudflare candidate | dry run, artifact manifest, candidate ID, and rollback target are recorded | promoted output differs from tested output or rollback is unknown |
| G8 production verification | remote state matrix, asset integrity, logs, caches, and browsers pass | local/remote parity fails or production reports errors |
| G9 owner release approval | contact sheets and release packet are accepted | campaign quality or residual risk is not accepted |
| G10 post-launch closure | monitoring and feedback review complete | incidents or repeated confusion remain untriaged |

## Pre-launch surface readiness

For V2 and V3 releases, verify the complete public path rather than only the
homepage component tree.

### Message and activation

- A new visitor can identify the target user, category, problem, and outcome
  from the first viewport.
- The hero has one primary conversion action. For the current site this is the
  Homebrew install path; GitHub is secondary.
- Copying the install command produces the exact current README commands.
- Test install or activation from a clean supported machine or record why that
  end-to-end path is outside the website release scope.
- Requirements and compatibility are visible before the user commits.
- The GitHub destination, repository visibility, README, releases, and install
  instructions are current.

### Metadata and sharing

- title and meta description are correct;
- canonical URL is present and resolves to the production hostname;
- favicon and app icons load;
- Open Graph and social-card title, description, image, dimensions, and alt text
  are current;
- X, LinkedIn, Slack, Discord, iMessage/email, and Product Hunt previews are
  captured when those channels are in the launch plan;
- robots, sitemap, and structured data are present when required by the
  approved site architecture;
- no preview references localhost, a worktree, a temporary asset, or an old
  deployment hostname.

### Link and navigation integrity

- logo/home, install, GitHub, X, documentation, privacy/support, and campaign
  URLs resolve with expected status and destination;
- no orphan public page exists;
- redirects and trailing-slash policy are consistent;
- external links use descriptive accessible names;
- browser cosmetic filtering does not hide required navigation or profile
  links.

### Asset ownership

Every launch asset has an owner, source revision, status, and destination:

| Asset | Owner | Required proof |
| --- | --- | --- |
| Website screenshots | capture and website owners | source/master/output lineage plus state matrix |
| Launch film and cuts | video owner | approved brief, storyboard, preview, render, duration, captions/audio |
| OG/social cards | design owner | platform previews and text-safe crops |
| README images | repository owner | unchanged references or coordinated update |
| Product Hunt assets | launch owner | listing order, thumbnail readability, video/GIF fallback |
| Launch copy | marketing owner | product-context and copy-skill review |
| Support/FAQ/known issues | maintainer | current answers and escalation route |

## Accessibility release gate

Automated accessibility checks are a floor. Manually verify:

- semantic heading and landmark order;
- keyboard access to install, header, all five product selectors, closing
  GitHub action, and footer profile links;
- visible focus that is not clipped or hidden by the sticky header;
- tablist names, roles, selected state, roving focus, Home/End, arrow-key
  behavior, and panel relationships;
- JavaScript-disabled default-state fallback;
- useful alternative text for each product state and empty alt for decoration;
- text, focus, control, and non-text contrast against WCAG 2.2 AA targets;
- 200% zoom and narrow reflow without lost content or two-dimensional page
  scrolling;
- reduced motion without missing information;
- no interaction that requires hover, drag, animation, or pointer precision;
- touch target sizes and phone selector reachability;
- accessible error/status announcement for install-copy failure and success.

Store an ARIA snapshot for the page shell and product plate. An unchanged ARIA
snapshot does not waive a visible accessibility defect.

## Performance and loading-stability gate

Define budgets before V3 launch and record results for cold and warm loads:

- Core Web Vitals targets for LCP, INP, and CLS;
- HTML, CSS, JavaScript, image, and video transfer budgets;
- no unexpected post-ready layout-shift entry;
- explicit intrinsic width/height or aspect ratio for visual media;
- required fonts loaded before visual baseline capture;
- first product proof prioritized; hidden/below-fold states loaded without
  blocking the first viewport;
- no failed image, font, script, source map, or metadata request;
- no uncaught exception, unhandled rejection, site-origin console error, or
  unexplained warning;
- no third-party script blocks the hero, install action, or product switcher;
- slow-network and cache-cold checks preserve usable copy and primary actions.

Record layout-shift attribution when CLS changes. A correct final screenshot
does not waive a visibly unstable load.

## Launch channel readiness

Use the installed launch skill's owned/rented/borrowed model. Every selected
channel has an owner, asset, URL, publishing time, tracking code, response plan,
and measurable job.

### Owned

- website and install path;
- GitHub repository, README, release/changelog, and discussions/issues policy;
- email/newsletter or community when currently owned;
- documentation, support, FAQ, and known-issues surface.

### Rented

- X, LinkedIn, Reddit, Hacker News, Product Hunt, YouTube, or launch directories
  selected because Agent Studio's audience is present there;
- platform-specific copy and media rather than one duplicated post;
- UTM/source attribution through installation or activation where possible;
- requests for visits, trials, and feedback, never artificial votes or
  engagement.

### Borrowed

- maintainers, partners, integrations, technical communities, newsletters,
  podcasts, and reviewers with permission to participate;
- accurate briefing material and embargo/publish timing where applicable;
- a path from borrowed attention back to owned product and documentation.

Do not add a channel merely because a generic launch checklist names it.
Unselected channels are marked `not planned`, not left ambiguously unchecked.

## Launch phases

### Internal candidate

- team/friendly-user walkthrough;
- core install and first-use flow works;
- campaign assets are still private;
- blocking product, copy, and support gaps are logged.

### Controlled preview

- external users can access a real supported build;
- preview website and assets are shareable to the controlled audience;
- feedback route and response owner are active;
- no public launch claim is made.

### Release candidate

- G0 through G7 pass;
- launch assets and channel packets are frozen;
- release manifest and last-known-good Cloudflare version are recorded;
- launch-day staffing and rollback triggers are confirmed.

### Public launch

- owner authorizes promotion;
- exact tested candidate becomes production;
- channel posts link to the verified production URL;
- monitoring and response window begins immediately.

## Launch-day operations

Record a named owner and check cadence for:

- website and asset status;
- DNS, TLS, redirects, cache behavior, and Cloudflare errors;
- install command copies, GitHub visits, repository availability, release
  downloads, and first-use activation where measurable;
- unexpected 4xx/5xx responses and client errors;
- Product Hunt and community questions when those channels are selected;
- support, known issues, and repeated objections;
- traffic anomalies and abusive or misleading posts;
- public status/incident communication when required.

Define rollback triggers before launch. Minimum triggers include broken primary
CTA, missing product imagery, remote/local visual mismatch, widespread asset
404s, unexpected 5xx responses, uncaught runtime errors, or a browser hiding a
required conversion/navigation control.

During the launch window, freeze unrelated production changes unless they fix
an active incident.

## Rollback procedure

Before promotion:

1. Record the last known-good Cloudflare version ID.
2. Confirm it remains rollback-eligible.
3. Record the exact rollback command or dashboard operation.
4. Verify the old version does not depend on removed resources or bindings.
5. Assign rollback authority.

On rollback:

1. Preserve the failed version and evidence.
2. Promote the known-good version.
3. Verify production status, visuals, assets, and logs.
4. Notify affected channels if users saw the failure.
5. Open a failure record before attempting another release.

## Post-launch closure

### First hour

- verify production from an independent browser and network;
- inspect real-time logs and critical routes;
- confirm the primary CTA and all campaign assets;
- answer technical questions and record repeated confusion.

### First 24 hours

- classify feedback into product bug, website bug, install/onboarding friction,
  missing capability, positioning confusion, pricing/compatibility objection,
  and feature request;
- publish known issues and immediate fixes when necessary;
- compare channel traffic with successful activation, not visits alone.

### 48-hour review

- rank findings by frequency, severity, and strategic value;
- update copy, screenshots, FAQ, docs, or onboarding when questions repeat;
- contact users who failed installation or activation when a contact route
  exists;
- decide whether another launch communication is warranted.

### Seven-day review

- compare stated launch goals with measured outcomes;
- review incidents, rollback events, conversion, activation, retention signals,
  and qualitative feedback;
- record what to repeat, stop, and change;
- choose the next meaningful launch moment rather than extending launch noise.

## Current blocked assumptions

The following assumptions are rejected and must not drive further work:

- Passing the default Parallel work state does not prove Pane drawer, Quick
  Find, Review, or Persistent workspace.
- A loaded image does not prove that the image is useful marketing evidence.
- Generic terminal output, Git status, or a diff does not prove an agentic
  development workflow.
- A side-by-side persistence comparison fails when two half-size 16:10 images
  leave a large unused region inside the product plate.
- Localhost proof does not prove remote behavior. Browser cosmetic filtering,
  packaging, caching, and generated-image formats can change the deployed page.
- A full-page browser screenshot is not sufficient proof for a sticky-header
  page because capture stitching can duplicate sticky content. Use normal
  viewport screenshots at deliberate scroll positions.

The current capture suite remains rejected until it visibly proves agent work
and passes this SOP. In particular, future captures must visibly identify
Claude Code, Codex, and Agy as requested by the owner. Repository names and Git
commands alone are insufficient.

## Source-of-truth order

Use these sources in order:

1. The owner's current annotated screenshots and written corrections.
2. The current Agent Studio app and its shipped README/source behavior.
3. The website visual acceptance rubric and active remediation ledger.
4. Website source, tests, and capture manifest.
5. Older specifications and design boards.

When an older document requires a layout the owner has rejected, stop and
reconcile that document before implementation. Do not preserve a failed layout
because it is written down.

## Required task ledger

Before editing source, create or update one WIP checklist containing every
owner correction. Each item must link to its proof artifact or recorded
measurement. A checkbox means both the implementation and its proof pass.

The ledger must include:

- the affected page region;
- the affected product state or states;
- the required desktop and phone behavior;
- the local proof path;
- the deployed proof path when deployment is in scope;
- the exact failed observation if the item remains open.

Do not close a parent item while any referenced state remains unchecked.

## Environments

Verify in this order:

1. **Development:** `http://127.0.0.1:4321/`
2. **Local production:** `http://127.0.0.1:4322/`
3. **Cloudflare production:** the current deployed URL with a cache-busting
   query containing the deployed version identifier

Development is for iteration. Local production proves the generated Astro
artifact. Cloudflare production proves packaging, asset delivery, browser
filtering, and the actual public page.

Do not deploy to discover basic local defects. Do not accept local proof as a
substitute for the final remote pass.

## Required viewports

Use exact CSS viewport sizes:

- `1600x1000`: maximum desktop composition and side-by-side product plate
- `1440x1000`: desktop boundary check
- `1280x900`: responsive product-selector transition
- `900x900`: narrow desktop/tablet boundary
- `390x844`: phone composition

At each width verify document overflow, section rhythm, image bounds, selector
behavior, footer alignment, and visible focus treatment. A passing 1600px
layout does not prove 1280px or phone.

## Page-region walkthrough

Inspect these regions separately in a normal viewport:

1. Header
2. Hero and install control
3. Organized parallelism heading
4. Product selector and active product image
5. Closing product lockup and GitHub action
6. Footer identity and profile links

For each region capture a screenshot at the scroll position where the whole
region is visible. Never rely solely on one stitched full-page screenshot.

## Product-state walkthrough

The verifier must click every selector and wait for the selected panel's image
to load before judging it. Capture one desktop screenshot per state and one
phone screenshot per state.

### Parallel work

Required visible evidence:

- two or three readable panes;
- explicit Claude Code, Codex, and/or Agy identity in pane titles, terminal
  content, or another real app-owned identity surface;
- repository, worktree, branch, and working-directory context;
- simultaneous agent work that reads as distinct tasks, not two idle shells;
- no large empty pane that dominates the frame.

### Pane drawer

Required visible evidence:

- one named agent is clearly the primary task;
- the real drawer is visibly owned by that task;
- drawer content is purposeful, such as a build, test, browser, review, or
  documentation surface related to the agent's work;
- the drawer is not mostly empty;
- native dimming and geometry are preserved without an invented marketing
  outline.

### Quick Find

Required visible evidence:

- the real Quick Find surface and one meaningful scoped query;
- the same believable named-agent workspace remains visible behind it;
- the command surface is readable and not surrounded by a synthetic frame;
- the query does not expose personal paths or unrelated fixture data.

### Review

Required visible evidence:

- a named agent terminal is visible beside the work it produced;
- the Changed Files tree and selected populated diff are readable;
- the terminal-to-file-tree-to-diff relationship is clear;
- no white or bright corner artifacts appear around the captured window;
- the frame is not dominated by an empty terminal or unreadable truncated UI.

### Persistent workspace

Required visible evidence:

- before and restored states come from one verified persistence sequence;
- the same named Claude Code, Codex, and/or Agy sessions are recognizable in
  both states;
- tabs, panes, drawer/review entries, terminal content, and workspace grouping
  visibly correspond;
- the presentation fills the product plate at marketing scale;
- no side-by-side arrangement is accepted when it creates a large empty lower
  half or makes both screenshots unreadable;
- a replacement presentation pattern must be approved before implementation if
  the current split comparison cannot meet these conditions.

## Per-image visual checklist

Run this checklist for all six capture assets and every generated website
variant:

- [ ] Correct state and filename
- [ ] Correct 16:10 source geometry
- [ ] Full image visible without stretching
- [ ] No unexplained gap between selector and image
- [ ] Image top and bottom align with its panel
- [ ] No white, bright, or transparent-corner flattening
- [ ] No accidental crop
- [ ] No large dead region
- [ ] Text and primary UI remain readable at rendered size
- [ ] Named agentic software is visible where the narrative requires it
- [ ] Feature claim is proved by the pixels in the image
- [ ] No cursor, notification, credential, personal path, or unrelated app
- [ ] Color treatment matches the campaign
- [ ] Selected styling uses charcoal plus the approved blue focus signal, not a
      broad purple fill

One failed item rejects that image. One failed image rejects the suite.

### Source-pixel admission gate

`RGBA` is a file format fact, not transparency proof. Before an image enters
`web/src/assets/captures/`, record all of the following from the decoded source:

- intrinsic width, intrinsic height, bit depth, color profile, and alpha mode;
- RGBA values at all four exact corner pixels;
- the first non-transparent pixel on the top, bottom, left, and right edges;
- a 32 by 32 pixel crop from each corner, enlarged against both a checkerboard
  and the real website product-panel background;
- whether the image is a native window capture, a measured native-window
  composite, or a generated derivative;
- the single owner of corner clipping: native source alpha or one documented
  composition mask, never a source mask plus a second CSS approximation.

For a rounded native window, the exact outside-corner pixels must have alpha
zero. Partially transparent antialiasing pixels must not contain a white or
bright premultiplied fringe that becomes visible on `--product-ground`. A fully
opaque corner fails when the frame claims to preserve a rounded native window.
`hasAlpha: true` alone never passes this gate.

For a Quick Find or other multi-window composite, the mask may affect only the
separate native sheet boundary. Pixels outside that sheet must reveal the
captured parent window, not white, gray filler, or a synthetic marketing scrim.
The receipt records the measured sheet bounds and radius.

### Crop, fit, and readability gate

Every full-app source has one approved intrinsic aspect ratio. The rendered
image must preserve it. At each required viewport, record:

- image natural size and rendered size;
- image and panel bounding boxes;
- `object-fit`, `object-position`, CSS radius, overflow, and transform values;
- whether every source edge is visible;
- unused panel area above, below, left, and right of the image;
- the rendered pixel height of the smallest text needed to understand the
  feature.

Full-app proof uses `width: 100%` and intrinsic height. It may not use
`object-fit: cover`, a negative translation, an undocumented clip path, or CSS
radius to hide source contamination. A close crop is allowed only when the
storyboard names the crop and another visible frame establishes app context.

Reject the state when the selector or another sibling forces a taller panel
that leaves more than 10 percent of the product surface unused. Reject any
state whose important agent name, task, repository, branch, changed-file name,
or command result cannot be read at the actual website rendering size.

Persistence may not place two 16:10 screenshots side by side inside a full-height
plate. Show one full-scale frame at a time through an accessible Before/Restored
control, comparison wipe, or another owner-approved full-scale pattern. The
JavaScript-disabled fallback must still show one complete honest frame and make
the second source available without creating a dead region.

### Campaign-meaning gate

The verifier asks one question before inspecting details: "Would this still
look like coding-agent work if the website caption disappeared?" If the answer
is no, reject the image.

- Agent identity must come from real pane titles or real terminal content. A
  website label, alt text, filename, or added overlay does not count.
- The suite must contain recognizable real Claude Code and Codex sessions. The
  owner-requested `Agy` identity remains blocked until the exact tool is named;
  do not silently substitute `aider`.
- Repository and Git context support the story but cannot replace agent output.
- Use two or three primary panes. More panes require a state-specific written
  reason and a rendered-scale readability pass.
- A focal surface should occupy enough of the frame to read. Reject a pane,
  drawer, command sheet, diff, or review path that is mostly empty.
- Reject synthetic rails, glows, scrims, borders, focus boxes, fake labels, or
  decorative zooms used to compensate for weak source composition.
- One image proves one benefit. Unrelated UI must recede through native product
  state and composition, not an invented marketing treatment.

### Two-plane visual approval

Each image receives two independent visual decisions:

1. `SOURCE PASS`: inspect the decoded full-resolution source and its corner
   crops. This proves content, crop, color, alpha, and native geometry.
2. `RENDER PASS`: click the state in the real website at every required
   viewport. This proves scale, fit, container background, borders, spacing,
   and readability.

Neither decision implies the other. A clean source can fail when the website
shrinks it too far. A neat container can fail because it hides a contaminated
source edge. Record both decisions per asset. Any `FAIL` keeps the whole suite
at `NOT VERIFIED`.

## Corner and alpha verification

For every source and generated image:

1. Confirm dimensions and color profile.
2. Confirm whether the source contains alpha.
3. Confirm the generated website format preserves required alpha.
4. Inspect all four corners at 100% zoom.
5. Inspect the rendered page against the actual product-panel background.
6. Reject any white wedge, bright strip, halo, flattened transparency, or
   mismatched corner radius.

Do not infer corner correctness from the center of the image or from a different
product state.

## Geometry and spacing measurements

Record computed bounds rather than judging alignment only by eye:

- selector right versus image left in side-by-side mode;
- selector bottom versus image top in stacked mode;
- image top/bottom versus panel top/bottom;
- header and footer icon/link bounds;
- hero summary to install control;
- install control to next section eyebrow;
- section description to product plate;
- closing lockup internal gaps.

The approved responsive rhythm is:

- desktop: `40 / 80 / 40` pixels for content / section / content gaps;
- phone: `32 / 64 / 32` pixels.

Use at most two pixels of tolerance for subpixel image scaling. Any larger
offset requires a source or CSS correction.

## Local all-state contact sheet

After the local production walkthrough, create a contact sheet containing:

- all five selected website states at 1600px;
- all five selected website states at 390px;
- the six full-resolution source captures;
- focused crops of every image corner;
- header, closing lockup, and footer viewports.

Review the contact sheet as one campaign. Reject inconsistent geometry,
different capture density, unreadable panes, generic terminal-only states, or a
state that looks like a different product.

## Automated gates

Run from the repository root:

```bash
pnpm --dir web run fmt
pnpm --dir web run check
pnpm --dir web run build
pnpm --dir web run test:browser
```

Browser coverage must assert:

- all five selectors exist and switch without changing the URL;
- the selected panel image loads;
- one install control exists in the hero;
- one closing GitHub action exists;
- footer GitHub and X links have visible nonzero bounds;
- side-by-side and stacked image geometry have no gap;
- selected styling uses the approved charcoal surface;
- phone layout has no document overflow;
- JavaScript-disabled fallback remains valid.

Automated gates do not replace the visual walkthrough.

## Cloudflare promotion gate

Cloudflare deployment begins only after the local production contact sheet and
all local checklist rows pass.

Required sequence:

1. Build the Astro site.
2. Run `cf build`.
3. Run `cf deploy --prebuilt --dry-run`.
4. Commit the verified local checkpoint.
5. Deploy with `cf deploy --prebuilt`.
6. Record the Cloudflare version identifier.
7. Reload the public URL with a version query to bypass stale caches.
8. Repeat the page-region walkthrough in a normal Brave viewport.
9. Click all five product states on the public site.
10. Repeat the 1600px and 390px state screenshots.
11. Verify zero site-origin console errors or warnings.
12. Compare remote screenshots with local production evidence.

Remote proof fails if Brave or another browser hides a required element, even
when the DOM still contains it. A nonzero DOM count is not visibility proof.

## Required proof artifact structure

Use one evidence directory per source commit:

```text
/private/tmp/agentstudio-website-verification/<commit>/
  local-production/
    1600/
      hero.png
      parallel-work.png
      pane-drawer.png
      quick-find.png
      review.png
      persistent-workspace.png
      closing-lockup.png
      footer.png
    390/
      ...same states...
  cloudflare-production/
    1600/
      ...same states...
    390/
      ...same states...
  contact-sheets/
    local-all-states.png
    cloudflare-all-states.png
    source-captures.png
    corner-crops.png
  measurements.json
  console.json
  receipt.md
```

Do not use screenshots from a prior commit or deployment version.

## Completion receipt

The receipt must state:

- release ID and release class;
- exact source commit;
- product-marketing context version;
- Agent Studio source revision used for claims and captures;
- build environment and lockfile digest;
- artifact manifest path and digest;
- Cloudflare version when deployed;
- last known-good Cloudflare version and rollback route;
- exact browser and environment;
- every viewport checked;
- every product state clicked locally and remotely;
- local and remote evidence paths;
- automated command results and counts;
- geometry measurements;
- corner/alpha result for every image;
- named agent evidence present in each applicable state;
- accessibility, performance, metadata, link, and activation-path results;
- selected owned, rented, and borrowed channels with owners;
- launch monitoring window and named responder;
- post-launch review status;
- accepted failures: none;
- remaining blockers, if any.

Use this decision block verbatim:

```text
Release decision: NOT VERIFIED | READY FOR OWNER REVIEW | APPROVED FOR RELEASE | RELEASED AND VERIFIED
Open gates: <gate IDs or none>
Accepted exceptions: <none or explicit owner-approved risks>
Source commit: <full SHA>
Artifact manifest: <path and SHA-256>
Candidate/production version: <Cloudflare version ID>
Last known good: <Cloudflare version ID>
Owner decision: pending | approved
Post-launch closure: pending | complete | not applicable
```

## Stop conditions

Do not claim completion when any of these is true:

- one selector state was not opened;
- one state lacks a current screenshot;
- one state contains a white corner or gap;
- one state is mostly empty or unreadable;
- named agentic software is absent from the campaign proof;
- local and remote behavior differ;
- footer/header controls exist but have zero visible bounds;
- an automated gate is not run or fails;
- the deployed version is not the version visually inspected;
- the owner has not accepted campaign quality.

The correct result in these cases is `NOT VERIFIED`, with the failed state and
evidence named explicitly.

## References

### Project-local marketing frameworks

- Agent Studio Media `.agents/skills/product-marketing/SKILL.md`, pinned from
  `coreyhaines31/marketingskills` at
  `c6ea12834be62bdc4180a1385f6455cde84ae60c`
- Agent Studio Media `.agents/skills/launch/SKILL.md`, same pin
- Agent Studio Media `.agents/skills/site-architecture/SKILL.md`, same pin
- Agent Studio Media `.agents/product-marketing.md`
- Agent Studio Media
  `tmp/research-workflows/2026-08-20-website-release-sop/research-ledger.md`

### Primary online guidance

- Playwright visual comparisons:
  https://playwright.dev/docs/test-snapshots
- Playwright screenshots:
  https://playwright.dev/docs/screenshots
- Playwright ARIA snapshots:
  https://playwright.dev/docs/aria-snapshots
- Playwright diagnostic UI:
  https://playwright.dev/docs/test-ui-mode
- WCAG 2.2 quick reference:
  https://www.w3.org/WAI/WCAG22/quickref/
- web.dev layout instability:
  https://web.dev/articles/fixing-layout-instability
- Cloudflare versions and deployments:
  https://developers.cloudflare.com/workers/versions-and-deployments/
- Cloudflare rollback:
  https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/
- Cloudflare real-time logs:
  https://developers.cloudflare.com/workers/observability/logs/real-time-logs/
- Cloudflare retained logs:
  https://developers.cloudflare.com/workers/observability/logs/
- Product Hunt launch guide:
  https://www.producthunt.com/launch
- Product Hunt launch preparation:
  https://www.producthunt.com/launch/preparing-for-launch
- Product Hunt product-fit guidance:
  https://www.producthunt.com/launch/how-product-hunt-works
