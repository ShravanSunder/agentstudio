# Annotation Interaction, Focus, And Tooltip Bugs

Date: 2026-08-25

## Current todo

1. **Reply requires two clicks and the annotation moves**
   - Actual: after selecting an annotation, the first Reply activation changes
     selection/layout but does not open the reply editor; the second activation
     opens it.
   - Expected: one Reply activation keeps the same annotation anchored and opens
     the reply editor.
   - Evidence: owner report and supplied expanded-thread screenshots.
   - Root cause: thread-root `onFocusCapture` changed Pierre selection before
     the pointer click completed. The resulting render/geometry transition
     could replace or move the click target.
   - Fix: focus is presentation-only; click activation now owns range selection
     and Reply expansion.
   - Status: focused browser proof passes.

2. **Save loses the intended thread focus lifecycle**
   - Actual: Save/accept changes focus or exits the active review-thread state.
   - Expected: Save commits, replaces the editor with the saved message, and
     leaves the same thread expanded and active. Moving focus anywhere inside
     that thread changes no interaction state. Escape subsequently
     leaves/collapses the thread.
   - Evidence: owner report and current Reply composer screenshot.
   - Root cause: exact Save could unmount the focused editor before a stable
     same-thread focus target existed; focus return only used the original DOM
     invoker and had no fallback if it disconnected.
   - Fix: committed Reply preview takes focus during projection convergence;
     editor completion resolves the original invoker or a stable same-thread
     message fallback.
   - Status: focused browser proof passes.

3. **Annotation icon buttons have no discoverable tooltips**
   - Actual: Reply, Resolve/Reopen, Expand/Collapse, More/Edit, Revert, and Save
     rely on icon shape or accessible labels without the expected hover/focus
     tooltip presentation.
   - Expected now: every dense icon control anchors the shared Bridge tooltip,
     whose paint and compact `Action (shortcut)` format match native Agent
     Studio.
   - Future boundary: Bridge action identity/copy/icon/shortcut will be supplied
     by the command-spec system; that larger cutover is not part of this bug
     slice.
   - Evidence: owner report and supplied screenshots.
   - Fix: the actual button remains the Base UI anchor; shared popup paint now
     uses popover/primary colors, subtle ring, shadow, compact inset, and native
     radius; popup paint is pointer-transparent.
   - Status: product-anchor and controlled-open shared-primitive browser proofs
     pass. Full command-spec input ownership remains future work.

4. **Embedded annotation editor has no visible focus treatment**
   - Actual: the caret appears, but the editor surface does not visibly change
     border/ring/background to communicate focus.
   - Expected: the focused editor has a clear product-token focus treatment
     consistent with the owned shadcn Textarea/input system and the surrounding
     comment surface.
   - Evidence: supplied focused-editor screenshot.
   - Fix: the owned card and embedded surfaces now provide a visible
     `focus-within` ring at the shared surface boundary.
   - Status: focused browser proof passes.

5. **Clicking the active yellow thread background after Reply flickers the chronology**
   - Actual: Reply opens an empty composer. Clicking the yellow active-thread
     background removes the composer, briefly shows only the latest Draft
     message, then reveals the earlier messages again over successive frames.
     The code below the Pierre row jumps as the row height changes.
   - Expected: a click anywhere inside the complete active thread changes no
     editor, expansion, chronology, or row-height state. Only Escape or a click
     outside the complete thread may exit/collapse it.
   - Evidence: owner recording
     `/Users/shravansunder/Downloads/[capture]/2026-08-25.0803.Brave Browser.Bridge.mp4`,
     SHA-256
     `15d6d117db6f2a125db9daa6bbd38afdf4152332236da2fe80956e2c36ad11b0`,
     duration 4.475 s, 232 frames.
   - Status: root cause confirmed and bounded browser fix implemented. Ordinary
     Textarea blur no longer owns editor exit; Escape and complete-thread
     outside click remain the explicit exit owners.

6. **Output history steals pointer clicks from Share commands**
   - Actual: `Copy Markdown` is visibly enabled, but pointer activation does
     nothing. Keyboard Enter on the same button succeeds.
   - Expected: History remains in document layout below the Share command row
     and cannot overlap or intercept any command control.
   - Evidence: in the failing matching-stack layout,
     `elementFromPoint()` at the Copy button center returned the `Output
     history` section. Keyboard activation bypassed that hit-test conflict and
     created a succeeded v2 output attempt for two messages and 590 exact
     bytes.
   - Root cause: `WorktreeAnnotationShareSurface` returns multiple Fragment
     children into File and Review fixed-row grids. The hosts intend one Share
     row, but CSS Grid independently places the command row, optional other
     comments, and History, causing History's hit-test box to overlap Copy.
   - Fix: Share now has one stable layout owner, while File and Review reserve
     explicit auto rows for that owner before their flexible canvas row.
   - Status: fixed. The focused browser regression passes for File and Review
     with History collapsed and expanded. Live Chrome pointer Copy succeeded
     for two comments, and durable-history undo restored both to Pending.

## Scope classification

- These are primarily BridgeWeb transient interaction, focus, component
  identity, and design-system defects.
- They are not changes to the durable annotation message data model unless
  evidence shows that projection reconciliation changes message/thread
  identity or replaces committed state incorrectly.
- The New/Pending Program Design remains separate. It may reuse the corrected
  explicit-activation and focus ownership seam, but it must not absorb these
  bugs as new persistence requirements.

## Confirmed interaction model

```text
Reply once
  → activate thread + expand thread + focus reply editor

focus moves within the same thread
  → no selection, expansion, editor, or geometry transition

Save
  → commit + replace editor with saved message
  → keep thread active and expanded
  → focus a stable element owned by that same thread

Escape
  → exit active editor first
  → next Escape collapses/leaves the thread

click outside the complete thread
  → flush/exit active editor as required
  → collapse/leave the thread
```

Generic focus and blur are not state-transition owners. Focus styling may
reflect the active keyboard target, but `onFocusCapture` and `onBlurCapture`
must not select, expand, collapse, or dismiss a thread merely because focus
moves.

## Current spacing map

The current geometry was accumulated from separate adjustments rather than one
spacing model:

| Layer | Current Tailwind | Effective spacing |
| --- | --- | --- |
| standalone conversation frame | `m-2 p-2 pr-9 pb-9` | 8 px outer margin; 8 px top/left inset; 36 px right/bottom inset |
| message card offset | `mt-1` | 4 px above the card |
| message card content | `p-2.5 pr-8` | 10 px top/left/bottom; 32 px right reserve |
| command rail | `right-2 bottom-2` | 8 px from right/bottom |
| command icon | `size=icon-sm` | 24 px square |
| avatar/content grid | `1.5rem` plus `gap-x-2` | 24 px avatar column plus 8 px gap |

The 32 px content reserve exactly equals the 24 px icon plus its 8 px right
offset. That leaves no deliberate gap between content and the command rail.
The outer frame is also asymmetric: 8 px top/left versus 36 px right/bottom.
The 36 px background breathing room was retained, but the inner card and rail
were never normalized around it. The visual result is therefore mechanically
valid but compositionally inconsistent.

Spacing correction must choose one owned anatomy and one Tailwind spacing
scale for:

```text
outer thread breathing room
  → avatar/timeline gutter
  → metadata-to-card gap
  → card content inset
  → content-to-command-rail clearance
  → command-rail edge inset and gap
```

It must not tune each layer independently against one screenshot.

## Tooltip presentation contract

The existing `WorktreeAnnotationCommandButton` already wraps Base UI Tooltip.
The button remains the tooltip anchor. The immediate defect is paint parity:
the Bridge primitive currently uses `bg-foreground text-background`, while the
native tooltip uses a dark control-background surface, primary text, a subtle
light border, and a soft shadow.

The immediate target is:

```text
actual Button
  → Base UI TooltipTrigger anchor
  → shared Bridge tooltip surface
       dark control/popover background
       primary light text
       subtle light border
       soft shadow
       8 px horizontal / 4 px vertical inset
       8 px radius
       `Action (shortcut)` copy format
```

The future command-spec cutover replaces the tooltip's label/shortcut input;
it does not replace its anchor or visual primitive. This bug fix must keep that
input seam narrow so later command projection can feed it without another
visual rewrite.

Prohibited fixes:

- HTML `title` as the product tooltip;
- route-local Tooltip styling;
- a duplicate File/Review action catalog;
- adding a provider and assuming visual parity is solved;
- expanding this bug into the full future Bridge command-spec cutover.

## Ranked hypotheses

### H0 — Textarea blur still exits the editor inside the active thread

The thread-level focus/blur owner was removed, but both composer Textareas
still treat blur as an edit-state transition. The Reply composer explicitly
calls `onCancel` when an empty editor blurs with no durable target. Clicking a
non-focusable portion of the yellow active-thread background produces no
`relatedTarget`, so the composer closes even though the click remains inside
the thread and the document outside-click owner correctly does not collapse.

The editor-to-null transition then re-enters the expanded chronology render;
the current Collapsible/mask presentation briefly hides earlier messages before
revealing them, producing the observed one-message → two-message → three-message
stair-step and Pierre row-height jump.

Smallest proof: open Reply, blur the empty Reply textarea while dispatching a
click whose target is the same thread frame, and observe that the composer is
removed even though `data-annotation-expanded` remains true. Then make blur
presentation-only and prove the composer/chronology/row bounds remain stable;
Escape and a true outside click must still exit through the registered editor
exit owner.

### H1 — Activation mutates layout before the click completes

`onFocusCapture`/range activation may synchronously update the active Pierre
range and row geometry before the Reply button's `click` dispatch. If the
button moves or remounts between pointer down and click, the first activation
selects the thread while the original click target disappears.

Smallest proof: capture pointer-down, focus-capture, range activation, render,
button identity, and click order for the first Reply activation.

Confirmed by source and red browser proof: focusing the compact message applied
`bg-comment-active-surface` before any click. Removing focus-owned activation
makes focus inert while the same click activates and expands.

### H2 — Reply entry has two competing expansion owners

The outer thread capture handler and the Reply callback may each perform
activation/expansion through different transitions. A state replacement or
stale callback may make the first transition select-only and the second open
the editor.

Smallest proof: trace `handleThreadClick`, `activateRange`, `startReply`, and
the reducer/state update that owns `threadExpansion`.

Reduced after H1. Click capture and Reply share the same React event and batch
without losing the target once the preceding focus event stops mutating range
state. No second expansion owner is required.

### H3 — Save intentionally closes the editor without assigning focus

The Reply composer currently receives `onSaved={interaction.finishThreadEditor}`.
If Save unmounts the composer before focus is returned to a stable thread-owned
element, browser focus falls to the document or another Pierre surface.

Smallest proof: trace Save success through `onSaved`, composer unmount, stored
invoker/focus target, and the subsequent Escape owner.

Evidence now supports this hypothesis. Exact Save sets `committedCursor`,
which replaces the textarea with a static preview immediately. `onSaved` is
deferred until a later projection contains the committed revision. Only then
does `finishThreadEditor` try to focus the original invoker, and it has no
same-thread fallback when that DOM node disconnected.

### H4 — The embedded Textarea variant removes the primitive focus ring

The feature uses the owned Textarea with `appearance="embedded"`. That variant
may intentionally remove border/ring paint without moving focus indication to
the containing annotation surface.

Smallest proof: compare the base and embedded Textarea class variants and check
whether any ancestor applies `focus-within` tokens.

Confirmed. The owned Textarea base supplies `focus-visible:border-ring` and
`focus-visible:ring-2`, while `appearance="embedded"` overrides both with
transparent border and zero ring. The embedded `WorktreeAnnotationInlineSurface`
adds no parent `focus-within` treatment. The focus indicator is therefore
removed without a replacement.

### H5 — Annotation buttons stop at `aria-label`

`WorktreeAnnotationCommandButton` may project a label only into accessibility
and omit `Tooltip`, `ControlTooltipRenderValue`, or the shared viewer tooltip
wrapper.

Smallest proof: inspect the wrapper and one nearby correct dense-control
implementation using the owned Tooltip primitive.

Refined. The wrapper has Base UI Tooltip markup, Portal, and Popup; Base UI's
provider is optional for basic opening. The immediate visual defect is the
inverted `bg-foreground text-background` bubble rather than native dark-control
paint. Full Bridge command-spec ownership is later work. Live tooltip opening
still needs a working fixture because the current Vite Review surface is stuck
in comparison refresh.

## Evidence log

- 2026-08-25: owner supplied screenshots showing an expanded two-message
  Pending thread, the reply composer, and a focused textarea whose surrounding
  surface has no distinct focus paint.
- 2026-08-25: current source shows Reply calls `startReply`, which first calls
  `activateRange`; the thread root also calls `activateRange` from
  `onFocusCapture` and `onClickCapture`.
- 2026-08-25: current source shows reply Save is wired to
  `interaction.finishThreadEditor`; focus behavior after that transition is not
  yet proven.
- 2026-08-25: current interaction owner uses thread-root `onFocusCapture` to
  activate Pierre range state and `onBlurCapture` plus animation-frame work to
  collapse/clear state. This contradicts the confirmed click/Escape-owned
  lifecycle.
- 2026-08-25: current spacing is `m-2 p-2 pr-9 pb-9` outside and
  `mt-1 p-2.5 pr-8 right-2 bottom-2` inside; the content reserve and icon rail
  consume the same 32 px with no explicit clearance.
- 2026-08-25: current annotation button tooltips use the owned Base UI Tooltip
  primitive with an inverted foreground/background recipe. Owner clarified
  that visual parity is required now and full Bridge command-spec integration
  is future work.
- 2026-08-25: red browser proof: focus alone activated the compact thread;
  tooltip did not open inside the deliberately too-short animation-frame wait;
  saved-editor focus had no stable same-thread assertion.
- 2026-08-25: green browser proof after correction: three focused browser
  files, 26 tests passed. Covered focus-inert activation, focus movement outside
  without collapse, Save focus retention, tooltip anchor/paint, and editor
  focus surface.
- 2026-08-25: video parent inspection sampled the full clip at 4 fps and the
  yellow-click window at 20 fps. The dense window shows the empty Reply composer
  present, then absent immediately after the yellow-background click; the
  expanded chronology transiently presents one, then two, then all three
  messages while the code below moves with the Pierre row.
- 2026-08-25: current source still gives Textarea `onBlur` mutation authority
  in both `WorktreeAnnotationNewMessageComposer` and
  `WorktreeAnnotationMessageEditor`. The Reply composer closes an empty
  no-target editor on blur even when the click is within the active thread.
- 2026-08-25: Luna independently inspected all 232 frames. It confirmed that
  the click lands on the active thread header surface, the empty Reply composer
  disappears immediately, the chronology briefly presents latest-only, then
  the same three saved bodies return with no loading or refresh indicator.
- 2026-08-25: failing-first browser proof reproduced the unwanted composer
  removal from a same-thread summary click. Removing Textarea blur as a
  lifecycle owner made the composer, expanded state, and exact root/latest DOM
  nodes remain stable; the focused inline-shell suite passed 9/9.
- 2026-08-25: post-checkpoint Computer Use proof on the populated real-Pierre
  Vite surface tested message content, the thread summary, painted padding, and
  outside code separately. Summary and painted-padding clicks retained the
  Reply composer and expanded chronology; an outside-code click exited and
  collapsed as designed. A message-body click deliberately replaced Reply with
  the saved-message editor, which explains the first operator's ambiguous
  coordinate observation.
- 2026-08-25: live Cmd+Enter reached `Saving draft…` and then reported
  `Bridge comm worker failed to forward review.annotations.command.` while
  retaining the draft. That is a transport/backend failure and is not part of
  this UI interaction fix.
