# Agent Studio website visual verification SOP

## Purpose

This SOP is the mandatory verification gate for Agent Studio website
development, styling, product imagery, responsive behavior, and Cloudflare
deployment. It prevents a default state, automated test, or one screenshot from
being generalized into a claim that the whole website is correct.

No website visual task is complete until every affected state is opened,
inspected, captured, and compared in the environments and viewports required by
this document.

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

- exact source commit;
- Cloudflare version when deployed;
- exact browser and environment;
- every viewport checked;
- every product state clicked locally and remotely;
- local and remote evidence paths;
- automated command results and counts;
- geometry measurements;
- corner/alpha result for every image;
- named agent evidence present in each applicable state;
- accepted failures: none;
- remaining blockers, if any.

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
