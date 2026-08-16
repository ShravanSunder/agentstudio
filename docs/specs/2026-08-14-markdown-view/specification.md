# Markdown View Specification

Date: 2026-08-14

Requirements: [Markdown View User Requirements](./user-requirements.md)

Program Design: [Markdown View Program Design](./program-design.md)

## The observable problem

Agent Studio's File View presents selected Markdown as literal source unless a
semantic document path is connected to the current File owner. Review already has
the correct exact-change presentation through Pierre, but its file headers do not
provide a direct in-place route to the corresponding complete current file.

The required outcome separates those jobs:

```text
human reviewer
  ├─ Review View ──► Diff: exact Pierre diff
  │                 Open: complete current file in the same Review canvas
  └─ File View   ──► complete selected file
                         └─ Markdown becomes a semantic document

outside this boundary
  automatic rendered Markdown in Review · editing · comments · version browsing
```

The system in this view is intentionally opaque. Review and File View are the two
observable surfaces; internal renderer, worker, sanitizer, navigation intent, and
state ownership belong to Program Design.

## Outcomes

- O1: A selected complete Markdown file reads as a structured document in File
  View.
- O2: Review defaults to Pierre's normal exact textual diff for Markdown and every
  other supported file, with the exact diff directly recoverable after Open.
- O3: Every Review file header provides an in-place Diff/Open toggle for that
  reviewed item without changing Review's rail or mode.
- O4: Fenced Swift is readable with visible syntax-token differentiation.
- O5: Mermaid fences produce bounded, inert diagrams instead of source blocks.
- O6: loading, failure, stale content, and an unavailable current path never show a
  misleading document for another file or revision.

## Normative requirements

### R1 — Semantic Markdown in File View

When File View has complete content for a selected `.md` or product-classified
Markdown file, it MUST present the file as semantic Markdown automatically.

The presentation MUST visibly distinguish headings, paragraphs, ordered and
unordered lists, block quotations, links, tables, thematic breaks, inline code,
and fenced code when those constructs are present. Heading levels MUST retain
semantic heading elements and a visible hierarchy after application-wide style
resets.

If complete content is pending, File View MUST show a Markdown-specific loading
state rather than briefly presenting stale rendered content or literal source for
a different selection.

Basis: U1, U4. Proof: V1, V2.

### R2 — Preserve Review as the exact Diff surface

Review View MUST initially present Markdown changes through the same normal Pierre
diff projection used for other reviewable files. Markdown selection MUST NOT
automatically replace the diff with a rendered document or introduce a
Markdown-specific `Rendered` / `Diff`, `Source` / `Preview`, or equivalent control.

Pierre's base/head line numbers, side-by-side or configured layout, diff content,
and existing review-item status MUST remain unchanged by File View Markdown
rendering and the Open action.

Basis: U4, U7. Proof: V3, V4.

### R3 — Offer a Diff/Open toggle beside every reviewed file's counts

Every Review file header MUST show one compact two-state icon toggle immediately to
the right of that file's deletion/addition counts. Its actions MUST be named `Diff`
and `Open` and MUST be present for added, modified, renamed, and deleted items.

Activating Open MUST keep Review active, keep the Changed files rail mounted, and
replace only that selected item's content with its complete current-file
presentation. Activating Diff MUST restore its exact Pierre diff. The toggle MUST
NOT open another pane or window or add Current/Previous choices.

Basis: U5, U8, U9. Proof: V3, V5.

### R4 — Handle an unavailable current path truthfully

When Open targets an item without current content, including a deleted file,
Review MUST show an explicit unavailable-current-file state for that item. It MUST
NOT display another file, fabricate current content, or silently substitute the
previous revision.

Selecting another reviewed file MUST return the content projection to that file's
normal Diff state.

Basis: U5, U8, U9. Proof: V5, V6.

### R5 — Shiki-highlight fenced code

Rendered fenced code in File View MUST preserve the fence contents and present
supported languages with visible syntax-token differentiation. Swift fences MUST
be supported.

An absent or unsupported language identifier MUST render as inert, readable code
without executing content or failing the surrounding Markdown document. Long
lines MUST remain readable through bounded horizontal overflow rather than
widening or clipping the document canvas.

Basis: U2. Proof: V7, V8.

### R6 — Render Mermaid as a bounded diagram

A valid `mermaid` fence in File View MUST produce a visible diagram. The literal
fence MUST not remain the normal successful presentation.

An invalid or unsupported diagram MUST produce a bounded error at that diagram's
location while the rest of the Markdown document remains readable. A diagram
failure MUST NOT replace the whole document with a blank or generic failure canvas.

Repository-authored Mermaid MUST remain inert: it MUST NOT execute script, install
event handlers, embed executable foreign content, or trigger remote resource loads.

Basis: U3. Proof: V9, V10, V11.

### R7 — Keep rendered output tied to selected File content

Rendered output MUST correspond to the currently selected File View path and its
current content revision. A late result from an earlier selection or revision MUST
NOT replace the current canvas.

When selected Markdown content changes, the visible state MUST move through an
explicit loading or refresh state until matching rendered output is available. If
rendering fails, File View MUST show a bounded failure with a retry opportunity.

Basis: U1. Proof: V12, V13.

### R8 — Preserve content-first presentation and accessibility

Rendered Markdown MUST use Agent Studio's existing content-area colors,
typography, spacing scale, focus treatment, and dark appearance. Document styling
MUST remain scoped to the Markdown canvas and MUST NOT restyle surrounding Bridge
chrome or Pierre content.

Semantic headings, lists, tables, quotations, and code MUST remain exposed as
their corresponding document structures. Mermaid diagrams MUST have an accessible
diagram label or description.

The Diff/Open toggle MUST be keyboard operable and visibly focused. Its icon-only
buttons MUST expose the names `Diff` and `Open` to assistive technology and as
tooltips; the icons themselves MUST be decorative.

Markdown link text MUST remain visible and visually differentiated, but links in
this read-only presentation MUST be inert and MUST NOT be exposed as actionable
navigation. This change introduces no URL-opening policy.

Basis: U1, U2, U3, U5, U8. Proof: V2, V3, V8, V10.

## Observable surface contracts

### File View

- Input: a selected product-classified Markdown file with complete current content.
- Markdown success: semantic rendered document matching that selected content.
- Non-Markdown success: existing File View presentation remains unchanged.
- Missing target: explicit unavailable-current-file state for the requested path;
  no stale prior selection.
- Pending: visible loading state; no stale prior document.
- Diagram partial failure: local Mermaid error; remaining document stays readable.
- Document failure: visible bounded error and retry; no false success.

### Review View

- Input: a selected review source and its review items.
- Success: existing Pierre diff presentation, with Diff/Open beside every file's
  counts.
- Open success: Review stays active and Pierre presents the selected item's
  complete current file in the existing content area.
- Diff recovery: Pierre restores the selected item's exact diff.
- Compatibility: Pierre layout, line numbers, diff content, collapse behavior, and
  Review selection/state remain owned by Review.

## Security, reliability, performance, and compatibility constraints

- Repository-authored Markdown, raw HTML, fenced code, and Mermaid are untrusted
  presentation input. Successful rendering MUST NOT execute them as active content.
- Rendering failure MUST be fail-contained to File View Markdown presentation and
  MUST NOT break File/Review navigation.
- Rendering MUST remain responsive at the existing supported selected-content
  boundary. Content outside that boundary MAY fall back to an explicit unavailable
  state; it MUST NOT be silently truncated and presented as a complete document.
- Existing non-Markdown Pierre/Shiki File behavior and all Pierre Review behavior
  are protected.
- Existing Bridge content acquisition, source identity, and review-package
  semantics are protected; this change adds only an optional presentation field to
  the existing Review selection command and no new transport lane.
- Open state is Review-local and transient. No persisted preference or navigation
  history is required.

## Explicit non-goals

- Automatic rendered Markdown or a Markdown-specific presentation toggle inside
  Review.
- Direct Markdown or source editing.
- Comment authoring, comment anchors, source-range integration, persistence,
  delivery, or lifecycle.
- Current/Previous reviewed-version navigation or previous-revision File View.
- Execution of MDX components, raw HTML, scripts, or interactive embedded widgets.
- Loading local or remote Markdown images or other remote resources.
- Replacing Pierre as the exact File/Diff renderer.
- A new native protocol, application, content transport, persistence system,
  navigation subsystem, Git adapter, or security subsystem.

## Requirement and proof coverage

| Need | Outcome | Requirement | Observable contract | Proof obligation |
| --- | --- | --- | --- | --- |
| U1 | O1, O6 | R1, R7, R8 | File View | V1–V2, V12–V13 |
| U2 | O4 | R5, R8 | File View | V7–V8 |
| U3 | O5 | R6, R8 | File View | V9–V11 |
| U4, U7 | O1, O2 | R1, R2 | File View, Review View | V1, V4 |
| U5, U8 | O3, O6 | R3, R4, R8 | Review View | V3, V5–V6 |
| U9 | O6 | R3, R4 | Review unavailable current item | V5–V6 |

U6 is superseded and authorizes no obligation. U7's prior rendered-Review meaning
is superseded; its current boundary authorizes R2. U9 authorizes only the negative
boundary against Current/Previous version browsing.

## Proof obligations

- V1 — Automated behavior evidence distinguishes complete Markdown selection from
  non-Markdown and incomplete selection and proves semantic File View output.
- V2 — Browser visual and accessibility evidence proves heading hierarchy,
  ordinary document spacing, semantic structure, scoped styling, and inert links
  in File View.
- V3 — Browser interaction/accessibility evidence proves every Pierre file header
  has the Diff/Open icon toggle immediately after its counts and that it is keyboard
  operable and visibly focused.
- V4 — Browser regression evidence proves Markdown remains Pierre's normal diff,
  including side-by-side layout and line numbers, with no Markdown projection
  control.
- V5 — Automated and browser interaction evidence proves Open keeps Review and its
  rail mounted, presents the selected complete current file, and Diff restores the
  exact change projection.
- V6 — Browser evidence proves another selection resets to Diff and a deleted item
  produces an explicit unavailable current-file state without unrelated content.
- V7 — Automated renderer evidence proves Swift and other supported fences retain
  content and produce differentiated Shiki tokens; unknown languages remain inert.
- V8 — Browser visual evidence proves multi-color Swift tokens, code geometry,
  horizontal overflow, and readable contrast.
- V9 — Automated renderer evidence proves Mermaid classification, successful
  diagram output, and local invalid-diagram failure.
- V10 — Browser visual/accessibility evidence proves a real Mermaid diagram is
  visible and meaningfully labeled in File View.
- V11 — Misuse-case evidence proves Markdown/Mermaid cannot retain executable
  script, event handlers, foreign executable content, or remote resource loading.
- V12 — Automated race evidence proves late render results cannot replace a newer
  File selection or revision.
- V13 — Browser interaction evidence proves pending, retry, partial diagram
  failure, and full document failure states without stale or blank success.
