# Annotating rendered Markdown

Governed by [Requirements](requirements.md); realization is in
[Program Design](program-design.md).

## Reader journey

```text
Read rendered Markdown -> select gutter range -> press + -> write/save
  current gap: rendered view has no annotation entry
  desired: stay in rendered context, then revisit/reply/share normally
  authority: U1, U2, U3, U4
```

The same reader uses Chrome development preview and the native embedded viewer.
Both expose the same annotation behavior. Native storage/sharing remain the
existing observable annotation system; editing Markdown is outside this boundary.

## Observable contract

- R1 (U1,U6): The rendered document MUST expose one gutter with source-line
  numbers, compact overlaid annotation actions, and the existing yellow active
  range language. Text targets align numbers to the first rendered line; diagrams
  align at the top. No redundant comment-count icon or nested code gutter.
- R2 (U2): Primary-pointer dragging in the gutter MUST select the contiguous
  source range between the anchor and endpoint in either direction. Pressing +
  MUST open a composer for that range. Text dragging outside the gutter MUST
  preserve browser text selection and MUST NOT start annotation selection.
- R3 (U3): Paragraphs and list paragraphs MUST exclude descendant list items.
  Dragging may explicitly include them. Wrapped text remains the same target.
  Nonempty fenced code targets logical content lines, including blank lines;
  empty and indented blocks target the whole block. Mermaid targets the complete
  fence even if diagram rendering fails. Table header and body rows are separate
  targets; the Markdown separator row is not a rendered target. Quotes target
  paragraphs; bold, links and other inline spans do not create targets.
- R4 (U3,U4): The composer and thread MUST appear after the last selected target.
  A table-row thread MUST span the table columns in a row beneath the target.
  Code comments appear after the selected logical line, not just after the fence.
  Nested list comments MUST NOT be deferred to the end of the parent subtree.
- R5 (U4): Saved comments MUST use the existing annotation session, admission,
  command, draft, reply/edit/resolve and sharing semantics. Source and rendered
  views MUST refer to the same source-range annotation, not duplicate records.
- R6 (U5): While displayed Markdown differs from the current source identity,
  it MUST remain readable but MUST NOT admit a new annotation or accept a stale
  selection as a new-source selection. Refresh MUST NOT silently discard durable
  drafts/comments. Once an exact-current render is installed, new selection is
  available again. Switching files MUST retire a pending selection.
- R7 (U3,U7): Task state MUST be visibly read-only; malformed diagrams MUST remain
  annotatable as source blocks when the document is current. Source-authored HTML
  MUST NOT gain scripts, active forms, media fetches or navigation privileges.
  Missing/invalid target metadata MUST NOT produce an incorrectly anchored save.
- R8 (U7): Production proof MUST exercise source mapping, real rendered
  interactions, exact-source refresh admission and durable annotation flow.
  Native proof MUST demonstrate click/drag, creation and text selection. Lint,
  formatting and strict typechecking MUST pass; prototype proof is insufficient.

## Failure and cancellation

Save/reply failures retain the existing actionable error and draft behavior;
this feature introduces no retry policy. Escape and outside-click behavior use
the existing editor/selection contract. Selection itself is transient, not a
durable draft. An async render result for an obsolete file must never enable
annotation for the selected file. Failure of one Mermaid diagram does not remove
its source target or prevent annotations elsewhere.

## Coverage and proof

```text
Need        Problem -> outcome                 Contract    Evidence
U1,U6       absent gutter -> coherent context   R1          browser/native visual geometry
U2          source switch -> direct range      R2          pointer and text-selection interaction
U3          ambiguous blocks -> exact ranges  R3,R4,R7    parser and rendered boundary cases
U4          disconnected comments -> reuse    R4,R5       real save/projection/reply/share journey
U5          stale painted source -> safe save R6          retained-render replacement interleaving
U7          nominal feature -> proved flow    R7,R8       misuse, browser, native and quality gates
```

The proof boundary includes current supported runtimes, not a new release or
platform compatibility promise. No latency budget or new observability service
is introduced; existing render worker scheduling and source-scrubbing remain.
