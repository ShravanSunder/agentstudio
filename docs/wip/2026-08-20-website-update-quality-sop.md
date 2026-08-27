# Agent Studio website update quality SOP

**Status:** mandatory execution procedure

**Applies to:** every website image, copy, layout, interaction, responsive,
metadata, and campaign update

**Use with:**
[website release and visual verification SOP](2026-08-20-website-visual-verification-sop.md)
when a change is being deployed or released

## Purpose

This procedure controls the quality of the update while it is being made. It
prevents technically valid files, passing tests, or polished components from
entering the website before they prove their marketing job in the real page.

The release SOP proves a finished candidate and its deployment. This SOP comes
first: understand, define, make, inspect, reject or accept, then integrate.

## The rule

Every changed element must earn its place in the website at the size and in the
context where a visitor sees it.

Do not continue to the next stage when the current stage fails. Fix or replace
the failed work, repeat that stage, and keep the update `NOT ACCEPTED` until it
passes. Automated checks can find defects; they cannot overrule a human quality
failure.

## 1. Understand the current surface

Before editing:

1. Read the current page source, governing website documents, product-marketing
   context, and current Agent Studio product truth for the affected claim.
2. Open the current page at every affected desktop and phone width.
3. Inspect the current image, copy, layout, and interaction together. Do not
   judge a PNG, sentence, or component in isolation from its real placement.
4. Record the exact current failure in the active WIP ledger.
5. Confirm file ownership and concurrent-agent boundaries before writing.

**Required evidence:** source paths, affected page region and states, current
desktop and phone observations, and the owner correction being addressed.

**Reject and stop when:** the problem is still described as a vague preference,
the affected states have not been opened, the product claim is unverified, or
the intended write surface collides with another agent.

## 2. Define the update contract

Write a short acceptance contract before making the change:

- the visitor and moment the update serves;
- the one job of the affected page region;
- the product claim or action it must communicate;
- the exact UI, copy, media, and states that must be visible;
- the distracting or misleading content that must be absent;
- the desktop and phone conditions that must pass;
- concrete rejection conditions;
- the proof needed before integration and before release.

For a multi-element update, define each element separately and then state how
the complete set forms one coherent story.

**Reject and stop when:** an element has no unique job, two elements repeat the
same proof without a deliberate reason, the acceptance decision depends on an
unstated taste judgment, or the contract asks copy or layout to rescue weak
product evidence.

## 3. Make one bounded candidate

Change the smallest complete unit that can be judged in the page. Preserve the
current design system, source geometry, product terminology, and established
component boundaries.

Do not integrate a set of speculative alternatives. Produce one deliberate
candidate, inspect it, and revise or reject it before expanding the update.

**Required evidence:** focused diff and a runnable local page showing the
candidate in its intended location.

**Reject and stop when:** the change expands ownership, invents a new visual
language, adds unsupported product claims, introduces placeholder content, or
requires an unapproved workaround in another layer.

## 4. Image quality gate

Run this sequence for every marketing image before adding it to the manifest or
website:

1. State the single marketing claim the image must prove.
2. Define the exact native UI that must be visible and hidden.
3. Define composition, readable focal content, and rejection conditions before
   capture.
4. Capture a purpose-made candidate at the approved native geometry. Do not
   resize, pad, redraw, mask, or decorate a weak source into compliance.
5. Inspect the full-resolution source at 100 percent, including all four edges,
   corners, internal toolbars, file trees, sheets, drawers, pane boundaries,
   and the smallest claim-bearing text.
6. Reject clipping, irrelevant sidebars, empty space, unrelated repositories or
   tasks, duplicated campaign imagery, unreadable controls, personal data,
   cursors, notifications, white fringes, fake frames, and narrative mismatch.
7. Place the candidate in the actual website and inspect it at every affected
   desktop and phone width.
8. Ask: "Can a new visitor understand this image's claim from these pixels
   alone?" If not, recapture it. Do not rewrite the caption to excuse it.
9. Obtain an independent visual review using the same claim, source, rendered
   states, and rejection conditions.
10. Record separate `SOURCE PASS` and `RENDER PASS` decisions. Only both passes
    admit the image to the manifest and website.

One image failure rejects the affected image set. Reused imagery is acceptable
only when it is intentionally the same evidence, not when a distinct claim
lacks its own proof.

## 5. Copy quality gate

Run this sequence for every changed reader-facing line:

1. Identify the reader's situation and the one idea the line must communicate.
2. Map every product fact to the current README, source, or approved marketing
   context.
3. Read the visual evidence beside the copy. The words and pixels must prove the
   same claim.
4. Draft in plain language using the project-local copywriter guidance. Keep
   the approved Agent Studio voice and terminology.
5. Read the result aloud and at its real rendered width.
6. Reject unsupported claims, vague benefits, repeated ideas, inflated
   language, generic AI phrasing, jargon, and copy that needs surrounding lines
   to become understandable.
7. Obtain an independent copy review that has read the complete project-local
   copywriter skill and the same product sources.
8. Record the accepted line, its claim source, and the rendered page state.

Copy does not pass because it is grammatical. It passes when a skeptical
visitor can understand and repeat the promise after one reading, and the page
immediately shows evidence for it.

## 6. Integrated page quality gate

After each accepted element is integrated:

1. Open every affected state in the real local production page.
2. Inspect normal desktop and phone viewports at deliberate scroll positions.
3. Judge hierarchy, readability, spacing, rhythm, focus, crop, interaction,
   and copy-to-image agreement together.
4. Compare affected states with each other. They must look like one product and
   one campaign while each performs a distinct job.
5. Exercise keyboard, pointer, reduced-motion, loading-failure, and
   JavaScript-disabled behavior when the change touches those surfaces.
6. Inspect the browser console and network for site-origin failures.

**Reject and stop when:** a component is attractive alone but weakens the page,
phone presentation makes the proof unreadable, the campaign repeats one image
everywhere, visual hierarchy contradicts the message, or any affected state is
inferred instead of opened.

## 7. Independent update review

For image, copy, layout, responsive, or campaign work, give an independent
reviewer:

- the update contract and rejection conditions;
- current product-truth sources;
- the focused diff;
- full-resolution media;
- actual desktop and phone renders of every affected state;
- known limitations and unresolved questions.

The reviewer judges visitor comprehension, marketing specificity, visual
quality, copy quality, consistency, and defects. They do not approve from test
results or the implementer's summary. The implementer verifies every finding
against the current page before accepting or rejecting it.

## 8. Automated proof

Run the affected focused checks only after human source and rendered quality
passes. Then run the repository-required format, lint, strict typecheck,
capture audit, unit, browser, accessibility, and static-build gates appropriate
to the change.

Automated proof confirms contracts such as dimensions, image loading, state
switching, overflow, semantics, and build integrity. It never proves that an
image tells a useful story, that copy is persuasive, or that the complete page
looks good.

Any failed required check returns the update to the owning stage. Do not weaken
the check or expand into unrelated infrastructure without owner agreement.

## 9. Whole-update acceptance

Before requesting owner review:

1. Reopen every affected state from a clean local production load.
2. Review a desktop and phone contact sheet of the complete affected campaign,
   plus full-resolution sources for changed media.
3. Confirm every acceptance contract and rejection condition explicitly.
4. Confirm the current diff contains only authorized files and no placeholder,
   stale, duplicate, or rejected asset.
5. Record tests and quality observations separately.
6. Keep the result `NOT ACCEPTED` when any row is missing or uncertain.

The result may advance to `READY FOR OWNER REVIEW` only when the update works as
marketing, works as a responsive product surface, and passes its automated
contracts. Owner review is required before deployment of campaign-quality
imagery or a materially changed message.

## 10. Release and production verification

After owner approval, follow the website release and visual verification SOP.
Build one candidate, deploy that exact artifact, repeat the affected desktop
and phone walkthrough on the public URL, and preserve the rollback target.

Do not deploy to discover basic quality defects. Do not call a local pass a
production pass. Do not call a deployment complete until the exact deployed
version has been visually inspected.

## Required handoff

At any checkpoint, report:

- what was accepted and why;
- what was rejected and the exact observed failure;
- files changed;
- states and viewports inspected;
- independent-review status;
- automated commands and results;
- open owner decisions;
- current result: `NOT ACCEPTED`, `READY FOR OWNER REVIEW`, or
  `APPROVED FOR RELEASE`.
