# Rendered Markdown annotation needs

Readers reviewing Markdown in Agent Studio need to discuss the rendered content
without switching to raw source or losing the existing annotation workflow.
The owner is Shravan; authority is the accepted prototype discussion on
2026-09-10, including nested todos/tables and the recorded refresh guard.

The [Specification](specification.md) defines observable behavior; the
[Program Design](program-design.md) defines its realization.

## Authorized needs

All rows are authorized by the owner for this MVP and are required together;
priority is owner-assigned MVP scope, not an implementation ordering.

- U1: Review rendered Markdown with one continuous gutter resembling the existing
  Pierre annotation gutter. Code fences must not introduce a second gutter.
  Basis: “same gutter”, “don't want separate gutter for code fence”.
- U2: Click and drag gutter ranges, then annotate; retain ordinary text selection
  for copying. Basis: “click and drag should work in the real app”.
- U3: Target source-line ranges rather than rendered character positions: prose
  paragraphs, each nested list item's own text, logical code lines, table rows,
  quoted paragraphs, and whole Mermaid diagrams. Inline formatting remains part
  of its enclosing text. Basis: accepted MVP and expanded prototype cases.
- U4: Use the existing annotation editor, thread behavior, yellow selection,
  reply/edit/resolve, persistence and sharing rather than a new comment system.
  Basis: request for the real version of the existing annotation experience.
- U5: Preserve comments/drafts safely across rendering and refresh. Old retained
  Markdown remains readable; new annotation creation waits for an exact match
  between the displayed document and the current source. Basis: recorded
  refresh-guard decision and subsequent resume instruction.
- U6: Match the accepted compact gutter: number centered against the first text
  line; Mermaid top-aligned; plus almost overlaps the gutter number; no extra
  comment-count icon. Basis: owner screenshot corrections and acceptance.
- U7: Demonstrate real browser and native interaction, with automated production
  tests and strict TypeScript/discriminated unions. The test waiver applies only
  to the disposable prototype. Basis: real-app drag requirement and repository
  proof contract.

## Boundary

Work only in the separate rendered-markdown-annotations worktree. Reuse the
existing File viewer, Markdown worker, shared controls and annotation system.
No new persistence model, transport protocol, coordinator, native atom, Pierre
fork, source-editing feature, Mermaid node/edge anchoring, character anchors,
or unrelated palette changes. Checkboxes are read-only. Existing sanitization
and inert-link/media policy remain in force. Review diffs retain Pierre; this
MVP adds annotations to the existing rendered Markdown File-view route.

No unresolved product hypothesis is promoted to an obligation. Performance and
native fidelity require implementation proof rather than prototype inference.
