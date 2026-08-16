# Markdown View User Requirements

Date: 2026-08-14

Status: current owner-confirmed user requirements

Return destination: `spec-design` within the bounded `orchestrator-design` cycle

## Scope

This record captures two reviewer-facing needs: semantic Markdown presentation for
a complete file, and a direct way to open any reviewed file in place without leaving
Review. Review remains the normal Pierre diff surface. This record does not
specify internal renderer, transport, comment-storage, source-range, or anchor
mechanisms.

## Affected users and stakeholders

- Human reviewer: reads repository files and diffs and understands Markdown as a
  document.

## Authorized needs

### U1 — Read complete Markdown as a document

- Affected class: human reviewer
- Need/outcome: complete Markdown files present real document structure,
  including visually distinct headings and normal Markdown content, instead of
  showing only literal Markdown source.
- Evidence anchor/type: owner request and supplied screenshots in the 2026-08-14
  and 2026-08-15 conversations; direct product requirement
- Authority state: authorized
- Priority: must
- Priority assigner: product owner

### U2 — Read highlighted fenced Swift

- Affected class: human reviewer
- Need/outcome: fenced Swift code inside rendered Markdown has Shiki syntax
  coloring and usable code-block layout.
- Evidence anchor/type: owner request in the 2026-08-14 conversation; direct
  product requirement
- Authority state: authorized
- Priority: must
- Priority assigner: product owner

### U3 — Read Mermaid as a diagram

- Affected class: human reviewer
- Need/outcome: Mermaid fences inside rendered Markdown appear as actual diagrams
  rather than literal fenced source.
- Evidence anchor/type: owner request and supplied screenshots in the 2026-08-14
  conversation; direct product requirement
- Authority state: authorized
- Priority: must
- Priority assigner: product owner

### U4 — Do not introduce an editing-oriented source toggle

- Affected class: human reviewer
- Need/outcome: the Markdown experience does not require a Source/Preview toggle
  merely to support editing, because direct source editing is not planned for
  this surface.
- Evidence anchor/type: owner correction in the 2026-08-14 conversation; direct
  product boundary
- Authority state: authorized
- Priority: must
- Priority assigner: product owner

### U5 — Open every reviewed file in place

- Affected class: human reviewer
- Need/outcome: every Review file header offers one compact two-state icon toggle
  immediately to the right of its addition/deletion counts. The code state shows
  the exact Pierre diff; the document state opens the complete current file.
- Evidence anchor/type: owner correction and supplied GitHub reference in the
  2026-08-15 conversation; direct product requirement
- Authority state: authorized
- Priority: must
- Priority assigner: product owner
- Boundary: the action changes only Review's content projection. Review mode and
  the Changed files sidebar remain mounted and unchanged. It does not offer
  Current/Previous version choices.

### U6 — Comment integration is not part of this change

- Affected class: human reviewer
- Prior candidate need: prepare rendered Markdown for the forthcoming commenting
  system through a source-range integration seam.
- Evidence anchor/type: owner correction in the 2026-08-14 conversation
- Authority state: superseded; non-normative
- Priority: out of scope
- Priority assigner: product owner
- Disposition: this Markdown-view change performs no comment integration and adds
  no source-range mapping, comment projection, comment storage, or comment
  lifecycle.

### U7 — Review remains the normal Pierre diff

- Affected class: human reviewer
- Prior candidate need: selecting Markdown in Review primarily shows a complete
  rendered current document with a `Rendered` / `Diff` control.
- Evidence anchor/type: owner correction after direct packaged-product inspection
  in the 2026-08-15 conversation
- Authority state: superseded; non-normative
- Priority: out of scope
- Priority assigner: product owner
- Disposition: Review defaults to Pierre's normal textual diff, including its
  normal side-by-side layout. A deliberate per-file Open action may replace the
  content canvas with that file's complete current presentation; it is not the
  default Markdown Review projection that this correction rejected.

### U8 — Open stays inside Review

- Affected class: human reviewer
- Need/outcome: selecting the document side of the toggle keeps Review active and
  opens that reviewed path in Review's existing content area without changing the
  Changed files sidebar, opening another pane, or opening another window.
- Evidence anchor/type: owner correction in the 2026-08-15 conversation; direct
  product requirement
- Authority state: authorized
- Priority: must
- Priority assigner: product owner
- Boundary: the toggle becomes the direct return path to Diff. Selecting another
  changed file returns the content area to that file's normal Diff state.

### U9 — Current/Previous version navigation remains separate work

- Affected class: human reviewer
- Prior candidate need: every reviewed file header offers Current and Previous
  version choices.
- Evidence anchor/type: owner scope correction in the 2026-08-14 and 2026-08-15
  conversations
- Authority state: deferred; non-normative for this cycle
- Priority: out of scope
- Priority assigner: product owner
- Disposition: this cycle supplies only the current-file Open state. A deleted path
  may truthfully be unavailable; this cycle does not synthesize its
  previous revision.

## Observed foundation

- File View currently presents selected files through Pierre `CodeView`; the new
  Markdown path already connects complete selected content to Markdown Exit and
  Shiki.
- The shared Markdown canvas supplies scoped document typography, sanitization,
  and bounded Mermaid rendering.
- Pierre owns exact diff presentation and line-oriented review evidence.
- Pierre's `renderHeaderMetadata` slot is invoked for every diff item and places
  caller content after the built-in header metadata. Agent Studio already uses that
  slot for its deletion/addition counts.
- Review already owns selected-item state and supports a selected-item complete-file
  presentation through its existing content-demand and Pierre materialization path.

## User-job sequence input

Human reviewer reads exact changes in Review. When the complete current file is
more useful, the reviewer selects the document side of the toggle beside that
file's counts. Review remains active, the Changed files sidebar remains unchanged,
and only the content area opens the complete current file. The code side returns to
Pierre's exact diff.

Current pain: Markdown in File View is otherwise literal source, headings lack
hierarchy, Swift fences do not appear as intended, Mermaid remains source, and
Review headers do not provide a direct in-place route to the complete current file.

Desired observable difference: Review remains a predictable diff surface, every
reviewed file has a direct in-place complete-file route, and complete Markdown reads
like a document.

## Confirmed goal boundary

- Primary goal: let a human reviewer read complete Markdown documents naturally
  while preserving Review's default exact Pierre diff and making every reviewed
  current file directly openable in Review's content area.
- Existing foundation to reuse: File View, Review View, Pierre diff/file rendering
  and header metadata slot, Markdown Exit, Shiki, the shared Markdown worker and
  canvas, Review selected-item state, and Review's existing complete-file
  presentation seam.
- Missing observable capabilities: automatic semantic Markdown in File View,
  scoped document styling, rendered Mermaid, and a universal per-file `Open` action
  in Review.
- Allowed capability surface: BridgeWeb complete-file Markdown presentation,
  Review header metadata, Review-local selected projection state, and Review's
  existing selected-item content path.
- Protected surface: Pierre remains the exact Review renderer. Comment-system
  contracts and behavior remain unchanged and are not consumed by this change.
- Explicit non-goals: automatic rendered Markdown as Review's default projection,
  a global Review presentation preference, direct source editing, a Markdown editor, comment integration or
  source-range mapping, Current/Previous revision browsing, replacement of Pierre,
  and a parallel File/Review application.
- Acceptable complexity: extend existing surface owners and shared primitives. The
  existing Review selection command may carry the selected `diff | file`
  presentation; a new transport lane, persistence, native protocol, Git adapter,
  cache, navigation subsystem, or security system requires renewed approval.
- Acceptable outcome evidence: automated File Markdown rendering and Review-local
  Diff/Open interaction proof, Vite browser visual proof, signed packaged WKWebView
  proof, and the complete repository gates as later implementation evidence.
- Unresolved owner choices: none for this Requirements boundary.
