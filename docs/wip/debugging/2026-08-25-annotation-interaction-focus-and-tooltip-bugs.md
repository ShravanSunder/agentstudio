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
   - Root cause: the owned shadcn-style Textarea correctly removes its own
     border/ring for `appearance="embedded"`, but the replacement lived only in
     a low-contrast `focus-within` treatment. Editing was not explicit state,
     so the boundary could also disappear when focus moved to Revert or Save.
   - Fix: `WorktreeAnnotationInlineSurface` now receives explicit `editing`
     state. Card, embedded, and chronology surfaces share one persistent inset
     `border-ring + ring-2` editor boundary; keyboard focus strengthens the same
     ring. The embedded Textarea remains borderless, avoiding a nested outline.
     Draft metadata now reads `Draft changes · saved locally` rather than the
     contradictory `Saved · draft changes`.
   - Proof: failing-first browser assertion, then 25/25 focused thread/editor
     tests; scoped lint, formatting, TypeScript, and diff checks pass. Captured
     browser visual: `tmp/bridgeweb-annotation-explicit-editing.png`.
   - Live blocker: the current origin/main Review dev journey is waiting for
     review metadata, so final product-surface owner acceptance remains blocked
     by the concurrent publication lane.
   - Status: implemented and browser-verified; live owner acceptance remains.

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

7. **Share command toolbar redesign**
   - Previous actual: the temporary Share row matched the loading status
     surface but repeated the long `Share comments` title and used text-only
     `Copy Markdown`, `Export JSON`, and `Done` actions.
   - Expected: a compact left `Share2 + Share` identity, mixed icon plus short
     labels for Copy and Export, icon-only Close, and the agreed Pending/All
     semantic color treatment.
   - Evidence: live Vite Review screenshot after commit `f3bec167c`.
   - Fix: the row now uses `Share2 + Share`, neutral Pending/All chrome with an
     amber Pending status dot, tinted Copy with a Copy icon, Export with a
     File-JSON icon, and icon-only Close. Precise action meaning remains in
     accessibility names and shared anchored tooltips. `Other saved comments`
     remains absent.
   - Proof: 15/15 focused browser tests across the isolated Share control and
     integrated File/Review surfaces, plus generated visual inspection.
   - Status: visual redesign fixed. Additional keyboard bindings remain item 10.

8. **The live Vite journey opened the wrong comparison base**
   - Actual: `scenario=current-worktree` opened with target `HEAD`, so Review
     showed only the five tracked uncommitted files instead of the branch's full
     change set.
   - Expected for this inspection: compare the current branch against
     `origin/main` so the complete branch change set is visible.
   - Evidence: the Vite supervisor hard-codes `initialTarget: 'HEAD'`; current
     Git evidence is 239 commits and 722 changed files from `origin/main` to
     `HEAD`, versus five tracked files from `HEAD` to the working tree.
   - Status: root cause proven. Switch the live selector to `origin/main` for
     this inspection; any default-target product change requires separate
   design because `HEAD` may still be correct for an uncommitted-worktree
   journey.

9. **New and Pending are separate user states**
   - New identifies unseen agent-authored messages and must clear when the
     reviewer views those messages. It remains visible at the thread summary so
     agent replies are discoverable.
   - Pending identifies saved revisions that have not been handled by a
     successful acknowledged output. It does not mean unseen and needs its own
     semantic color rather than borrowing the blue New treatment.
   - Share exposes only Pending and All. It does not expose New as an output
     scope and does not ask the reviewer to select individual messages.
   - Proof: unit derivation covers independent New/Pending combinations; browser
     thread proof covers agent New, `message.viewed.mark`, projection
     convergence, mixed New/Pending ordering, blue New, and amber Pending.
     Live Review shows the saved human message as Pending.
   - Blocker: the current live Files mode opens `.gitignore` with `Content
     unavailable`, `Source pending`, and an empty tree, so it cannot provide an
     honest final Files visual witness until the concurrent source/publication
     lane converges.
   - Status: automated behavior verified and live Review verified; live Files
     owner acceptance remains blocked by current source availability.

10. **Annotation keyboard shortcuts are not settled or implemented as one system**
    - Confirmed: Command-Enter saves root, reply, and message-edit composers;
      plain Enter remains a newline while editing.
    - Confirmed interaction sequence: first Escape exits the editor while
      preserving the active thread; the next Escape leaves the thread,
      collapses history, and clears the yellow Pierre range.
    - Existing native activation remains: Enter on a focused editable message
      edits it; Enter or Space on a focused button activates that button.
    - Open decision: whether Reply, Edit, Resolve, and Reopen receive additional
      feature-local shortcuts or remain button-only.
    - Contract: labels, icons, tooltip copy, and displayed shortcut glyphs must
      share one typed local command descriptor rather than hard-coded strings.
    - Status: design discussion open; no new shortcuts implemented.

11. **Expanded-thread animation must reveal one grouped sheet**
    - Expected: the row geometry opens over the app's 120 ms fast motion, then
      the chronology travels downward as one coherent group. Collapse performs
      the reverse upward motion.
    - Rejected: staircase/cascade entry, per-message delay, content appearing
      one-by-one, decorative fade-only reveal, and a chunk that simply pops in.
    - Owner preference: the compared B prototype felt better; reproduce that
      exact option before changing the durable animation again.
    - Current implementation: the Collapsible animates row height over
      `--motion-fast` (120 ms) while one grouped history container moves a
      downward mask with zero per-message delay; collapse reverses that mask.
    - Proof: the owned five-message browser witness asserts one four-message
      history group, 120 ms height and mask motion, no per-message history
      wrappers, zero delay, and reverse keyframes. The complete inline-shell
      geometry/motion suite passes 9/9.
    - Status: implemented and automatically verified; final owner feel remains.

12. **Thread surface hit area, corners, and breathing room need one anatomy**
    - Clicking the non-interactive thread surface should activate and expand the
      thread; it must not require the small expansion control exclusively.
    - The yellow active background must follow the rounded message geometry and
      retain breathing room instead of painting a square block around it.
    - Settled command-rail spacing: 8 px between controls, 8 px from the edge,
      and 8 px between message content and the control rail. The retained outer
      yellow-background breathing room is 36 px on the right and bottom.
    - Current implementation: the shared rounded conversation frame owns the
      active yellow background; standalone placement uses 36 px right/bottom
      reserve. The message surface uses a 40 px right reserve around a 24 px
      command rail, while the rail uses 8 px edge offsets and 8 px gaps.
      Non-control thread-surface click activates and expands.
    - Proof: owned browser geometry assertions plus the passing 9/9 inline-shell
      suite.
    - Status: implemented and automatically verified; final owner visual
      acceptance remains.

13. **Share output behavior must remain consistent while the toolbar is redesigned**
    - Pending copies/exports every Pending saved revision; All copies/exports
      every eligible saved revision. There is no manual checklist.
    - Draft text is never output. Copy and Export consume the same exact saved
      bodies and successful output marks them handled by default.
    - Copy/Export success closes Share and shows a toast with a reversible
      `Mark as not handled` action. Failure or cancellation retains Share and
      advances no handled boundary.
    - The same interaction and presentation must hold in File and Review.
    - Status: behavior is implemented and focused proof passed before the
      toolbar redesign; it must not regress when item 7 lands.

14. **The Vite development loop needs one honest startup journey**
    - `pnpm --dir BridgeWeb run dev` already owns the supervised Swift backend;
      manually building and launching another backend duplicates work.
    - The supervised journey currently hard-codes `HEAD`, which is suitable for
      uncommitted-worktree inspection but not for reviewing this branch against
      `origin/main`.
    - For the current live review, run one backend seeded with `origin/main` and
      point Vite at it through `BRIDGE_WEB_DEV_BACKEND_ORIGIN`.
    - Status: the corrected origin/main live journey is running. Any product or
      default-dev-target change remains a separate design decision.

15. **Command-Enter on the first message clears the active thread**
    - Actual: saving a root composer with only one message removes the pending
      composer and clears the yellow Pierre range instead of leaving the new
      one-message thread active.
    - Expected: Command-Enter saves, replaces the composer with the exact saved
      thread, and keeps that thread active/yellow. Focus may leave the textarea,
      but the interaction remains active until Escape or a complete-thread
      outside click.
    - Root cause: File and Review handled root `onSaved` by calling
      `admitSelectedRange(null, ...)`, which cleared the pending range without
      promoting it to the saved thread. Re-discovering the thread from the
      filtered rendered projection is also racy at this transition.
    - Fix: the committed Save receipt now supplies exact `messageId + threadId`
      identity to the root completion callback; File and Review clear the
      pending composer and immediately activate that exact saved thread.
    - Proof: failing-first browser witness reproduced the inactive transition;
      the corrected Command-Enter journey plus thread/Pierre regressions pass
      23/23 across three browser files. Scoped lint and formatting pass.
    - Live proof: on the origin/main Vite journey, Command-Enter closed the
      composer, rendered the saved body, and retained exactly one active thread.
    - Status: fixed; owner acceptance remains.

16. **Clicking outside a one-message saved thread does not clear yellow**
    - Actual: the document outside-click listener exists only while
      `threadExpansion.kind === 'open'`. A one-message saved thread can be
      active/yellow while expansion remains closed, so it never receives an
      outside-dismissal owner. Its Escape guard also treats the absent editor as
      different from `null`, making Escape inert.
    - Expected: an inside click retains the thread; an explicit Collapse only
      collapses history and retains yellow; a complete-thread outside click or
      second-stage Escape leaves the thread and clears yellow.
    - Fix: `leaveThread` is now separate from `collapseThread`. Outside
      dismissal follows either an expanded thread or a saved active range, and
      Escape handles a closed one-message thread without requiring expansion.
    - Proof: failing-first located browser witness, then 24/24 focused browser
      tests across thread lifecycle, Command-Enter root Save, and Pierre. Live
      Vite proof observed one active thread after activating the saved message
      and zero after clicking outside it.
    - Status: fixed; owner acceptance remains.

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
