# Agent Studio website visual acceptance rubric

This rubric is the final review contract for both Claude Opus and Cursor Grok.
One failed required row returns `NO-SHIP`. Reviewers must inspect current live
desktop and phone screenshots plus every final product still, not source alone.

## Required page structure

- The page order is Hero copy and actions, then the clickable Organized
  parallelism explainer, then the install CTA.
- The hero headline is `Stay oriented without losing context.`
- Wide desktop presents that headline as an intentional two-line lockup rather
  than three accidental wraps, while phone wrapping remains readable.
- The clickable explainer supplies the first and only large product image.
- Parallel work is the default selected state and therefore the first product
  image a visitor sees.
- No standalone hero screenshot or repeated proof section duplicates the
  explainer.
- The hero and final CTA have no GitHub action because GitHub is already
  available in the header.

## Required capture composition

- All six source captures come from one fresh dedicated debug process lineage,
  one fixture, one app theme, and one 16:10 window geometry.
- The capture window is smaller than the rejected 1440×900 composition and is
  recorded at 2× scale.
- Every state uses two or three readable visible panes, including attached
  drawer panes, never four narrow primary panes.
- Visible panes contain short, purposeful, legible content. Large empty pane
  fields and noisy terminal logs fail.
- Parallel work shows two distinct, readable repositories with real Git output
  and the `All Panes` workspace context.
- Pane drawer shows one selected task plus its real attached drawer. The native
  app dimming and remaining workspace must make the attachment clear.
- Quick Find keeps a believable two- or three-pane workspace behind the command
  surface.
- Review shows the agent terminal beside the diff/file-tree path.
- Persistence before/restored images use the same two- or three-pane layout and
  demonstrate a recognizable restored arrangement.
- The six-image contact sheet must read as one campaign without relying on
  labels to explain inconsistent geometry.

## Required focus treatment

- Parallel and both Persistence images have no local focus rail.
- Pane drawer follows the actual drawer boundary and its native radius.
- Quick Find follows the rounded command palette itself. Any larger enclosing
  rectangle fails.
- Review preserves the terminal-to-diff-to-file-tree relationship and does not
  invent a box around the whole window.
- Non-focal context remains visible through Agent Studio's native treatment.
  The website still pipeline adds no marketing scrim or focus rail.
- Approved full-frame master and website-output bytes are exact matches for all
  six images.

## Required website art direction

- Wide gutters use a restrained 72px grid pattern with Agent Studio blue and
  peach hairlines. Repeated terminal or pane-stamp wallpaper fails.
- Gutter decoration disappears completely at narrow widths.
- The header GitHub action uses the official GitHub mark plus plain text; the
  `↗` glyph is not used as a substitute for the mark.
- The install command uses the darker Ghostty/Agent Studio pane ground and the
  command block aligns cleanly with the Copy button at desktop and phone sizes.
- The CTA uses one visual hierarchy: product name, one explanation, product
  traits, and install command. It does not repeat GitHub.
- The footer uses the Agent Studio icon at left and official GitHub/X icon links
  at right. It contains no redundant `Agent Studio` text label.
- Exact Agent Studio icon colors and softened geometry remain consistent.

## Required copy and interaction

- Every copy-writing or copy-review agent must read
  `web/.agents/skills/ai-copywriter/SKILL.md` completely and identify that
  coverage in its receipt. Missing coverage returns `NO-SHIP` for that review.
- Copy remains traceable to the current README and contains no filler labels,
  invented claims, or stacked marketing jargon.
- All five product states switch correctly without URL changes.
- Keyboard focus, tab semantics, JavaScript-disabled fallback, reduced motion,
  and phone overflow behavior remain correct.
- Desktop and phone have no document-level horizontal overflow and no
  site-origin console errors or warnings.

## Evidence required for `SHIP`

- A current six-image source-master contact sheet.
- A current six-image processed-still contact sheet.
- Current desktop, wide-desktop, and phone website screenshots.
- Capture lineage, dimensions, source/master/output SHA-256 values, and Quick
  Find sheet geometry in the checked-in manifest and WIP receipt.
- HyperFrames check with zero findings.
- Pixel-exact focal verification for all six outputs.
- Oxfmt, type-aware Oxlint, Astro diagnostics, capture verification, Vitest,
  Playwright desktop/mobile, and static build all pass.
