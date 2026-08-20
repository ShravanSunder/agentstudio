# PR1 Inline Comments UI Remediation

Status: active UI implementation contract
Scope owner: PR1 BridgeWeb inline-comment UI only
Driver: settled owner decisions, PR1 Requirements/Specification/Program Design,
and live Chrome evidence from 2026-08-18

## 1. Purpose

This WIP document is the execution checklist for replacing the current PR1
inline-comment presentation with the agreed compact comment system.

It does not authorize changes to Swift transport, metadata-capacity admission,
projection delivery, SQLite persistence, or other backend mechanisms. Another
lane owns those concerns. The UI lane consumes the existing typed annotation
client and reports interface blockers without redesigning backend ownership.

The current screenshots are not a styling baseline. They are defect evidence:

- the root composer is a large generic form card interrupting the code canvas;
- command buttons are tiny rounded squares although circular controls were
  explicitly required;
- multi-message threads duplicate chronology inline and in the overlay;
- messages are rendered as nested bordered cards;
- the overlay reads as a generic modal instead of an anchored thread expansion;
- metadata, commands, and message content lack a coherent hierarchy;
- the implementation uses shadcn primitives mechanically while freelancing the
  product component system around them.

## 2. Absolute scope boundary

```text
PR1 UI lane
  ├── Pierre File and Review range selection feedback
  ├── endpoint/gutter add-comment affordance
  ├── root composer
  ├── compact inline single-message projection
  ├── compact inline multi-message projection
  ├── animated inline full-thread expansion between M-summary and M-last
  ├── reply and draft composers
  ├── thread Resolve/Reopen presentation
  ├── Copy Markdown and Export JSON presentation
  ├── focus, keyboard, dismissal, and accessibility behavior
  └── visual and interaction proof in Swift backend + Vite + Chrome

Explicitly absent from PR1 UI
  ├── global Comments panel
  ├── session-level comment panel or persistent session chrome
  ├── whole-file comments
  ├── sidebar thread UI
  ├── general-review card or panel
  ├── agent delivery, agent replies, or agent-completed state
  ├── comment/message deletion
  ├── PR2 lifecycle UI
  ├── App IPC additions
  └── design-token source changes in bridge-app.css
```

File and Review may each host located comments through the shared component
system. A comment created for one file/range must never appear on unrelated
files or every route.

### Immediate visual-integration slice

Before behavioral remediation or automated-test work, build one fast visual
slice against the running Swift development backend and Vite HMR:

```text
agree on visual anatomy in chat
  └── change BridgeWeb React presentation only
        └── inspect the real result in Chrome
              └── compare screenshots and adjust
```

This immediate slice deliberately excludes backend work, test authoring, broad
refactors, and final proof gates. Existing data and callbacks may be used to make
the real components look correct. The slice ends only when the owner accepts the
visual direction for the root composer, M1, multi-message compact projection,
and expanded thread. Behavior and automated proof remain required before PR completion,
but they do not block this short visual-convergence loop.

## 3. Canonical presentation model

Exactly one projection occupies Pierre normal flow for one thread. Expansion
adds chronology to that same projection and lets Pierre remeasure the row.

```text
message count = 1
        │
        ▼
inline projection = M1

message count >= 2
        │
        ▼
inline projection = M-summary + M-last

explicit Expand / Edit / Reply
        │
        ▼
expanded inline chronology = M-summary + M1 ... Mn exactly once
```

The compact projection remains in Pierre normal flow. Expansion inserts the
missing earlier messages above the same keyed M-last, moves later diff rows
down, and restores them on collapse. Pierre remains the only scroll owner; the
thread adds no floating chronology layer or nested scrollbar.

## 4. Shared visual anatomy

All states use one coherent comment anatomy rather than different cards for
root, reply, saved message, summary, and expanded thread.

```text
left timeline                         compact content

     ◉  avatar node    author · time · visible state    timeline actions
     │
     │                 ╭──────────────────────────────────────╮
     │                 │ top-aligned message or composer     ○│
     │                 │                                    ○│
     │                 │                                    ●│
     │                 ╰──────────────────────────────────────╯
     │                                                   command rail
```

Settled geometry:

- avatar lives on the left timeline;
- author, time, and visible state share the avatar/timeline row;
- time is not isolated in a wasteful right-side region;
- the message/composer surface uses strongly rounded rectangle corners, not a
  full pill and not a square card;
- saved message height is driven by content;
- Markdown/body text is top-aligned;
- the right command rail is vertically stacked at the bottom-right edge;
- the command rail never determines body height;
- the full-width Pierre annotation lane is visually quiet and effectively
  invisible outside the compact projection;
- one owner supplies border, background, radius, focus ring, and active state;
- no nested border, nested card, or textarea-within-another-card treatment.

## 5. Standard shadcn command-button contract

Every icon command is an owned shadcn `Button`. The feature must not reproduce
button geometry, interaction, focus, disabled, or pressed behavior in a local
command-button abstraction. Message/composer rails use circular controls;
timeline actions use the quiet toolbar treatment and are not circular.

Current defect:

```text
Button size="icon-xs"
  └── rounded-sm
        └── tiny rounded square: rejected
```

Required shared primitive:

```text
components/ui/Button circular icon size
  ├── equal width and height
  ├── rounded-full
  ├── shared compact hit target
  ├── canonical shared icon size
  ├── standard focus-visible ring
  ├── standard disabled behavior
  └── standard default / ghost / destructive variants
```

Rules:

- add or extend the circular icon geometry in
  `BridgeWeb/src/components/ui/button.tsx`; do not scatter `rounded-full`, raw
  dimensions, or one-off button CSS across annotation feature files;
- `WorktreeAnnotationCommandButton` must be removed or reduced to semantics that
  do not redefine Button appearance/geometry; a wrapper is not permitted to
  invent a parallel button system;
- every icon button has one Lucide identity, tooltip, and accessible name;
- core controls have no visible text label;
- icon optical weight must be consistent, not merely the same SVG view box;
- Save is the only primary-colored command in a composer;
- ordinary commands use a visible outline treatment with comment semantic
  border/surface/foreground roles;
- Resolve/Reopen uses one stable stateful command identity;
- destructive treatment is reserved for a genuinely destructive action;
- circular rail buttons do not become badges, pills, or square cards on hover/focus;
- timeline Expand/Collapse and More use `ghost` toolbar buttons with the
  default compact radius and no visible circular outline;
- output inclusion stays inside More → Review output and does not occupy a
  permanent timeline control.

## 6. Exact command ownership

No command may appear in two locations on the same presentation.

| Surface | Right circular command rail | Timeline row |
| --- | --- | --- |
| Empty or durable composer | Revert, Save | Draft/error state only |
| One-message compact M1 | Edit when editable, Reply, Resolve/Reopen | time/state and More |
| Multi-message compact | Edit M-last when editable, Reply, Resolve/Reopen | M-summary with message count/latest time/state, Expand immediately before More |
| Expanded message | Edit when editable, Reply | author/time/message state |
| Expanded thread | one thread-level Resolve/Reopen | thread state |

Canonical icons:

- Reply: `Reply`;
- Resolve: `Check`;
- Reopen: `RotateCcw`;
- Revert: `Undo2` or the repository's canonical undo identity, not a second
  unrelated glyph;
- Save: `Check`, primary text/tint treatment; no solid blue background or
  black floppy-disk glyph;
- Expand/Collapse: one disclosure identity;
- More: `Ellipsis`.

Explicit removals:

- no MapPin or location button; source range presentation owns location;
- no Edit control for a locked message; a committed message remains editable
  until successful or crash-unknown output locks it;
- no Reply or Resolve/Reopen in the timeline row;
- no output-history glyph in the message command rail;
- no duplicate collapse/expand control;
- no permanent Include/Exclude control in the timeline;
- no unexplained permanent icon;
- no floppy icon styled as a tiny rounded-square button outside the standard
  circular Button contract.

## 7. Root composer states

### 7.1 Pending range

```text
Pierre range highlight
  └── endpoint/gutter circular + affordance
        ├── click +: open root composer
        ├── select another range: move pending range
        ├── click outside: clear pending range
        └── Escape: clear pending range
```

Range selection must provide visible drag feedback. The range remains selected
until `+`, another range, outside click, or Escape.

### 7.2 Empty composer

```text
◉  You · New comment
│
│  ╭──────────────────────────────────────────╮
│  │ Write an annotation in Markdown         ○│ Revert
│  │                                          ●│ Save
│  ╰──────────────────────────────────────────╯
```

- empty composer uses the same shell as later draft/saved states;
- it is compact and content-appropriate, not a giant form card;
- textarea is an integrated transparent Markdown canvas;
- empty focus loss, Escape, or abandoning without action removes it;
- Save remains disabled until valid non-empty content exists;
- the composer must not push a large blank block into the code review.

### 7.3 Durable draft

- first non-whitespace edit creates/persists the draft;
- input is debounced while focused at approximately one second;
- a bounded max-wait prevents indefinite dirty state;
- focus loss requests an immediate flush;
- explicit Save requests an immediate flush and commit;
- crashes/reloads must not lose the durable draft;
- the user can Revert the draft;
- Draft is visibly signaled with restrained warning/yellow semantics;
- focus loss does not discard or collapse a non-empty durable draft;
- Escape/new range may collapse the draft while preserving its durable content;
- Save converts the same visual shell into saved M1.

## 8. Compact saved projections

### 8.1 Exactly one message

Render M1 directly; do not add a synthetic thread-summary card.

```text
◉  You · 5m · Saved
│
│  ╭──────────────────────────────────────────╮
│  │ The refresh should remain asynchronous. ○│ Reply
│  │                                          ○│ Resolve
│  ╰──────────────────────────────────────────╯
```

### 8.2 Two or more messages

Render one synthetic summary plus M-last inside one compact projection. Do not
render M1 separately, and do not render every reply inline.

```text
◉  3 messages · latest 2m · Open               Expand · More
│
│  ╭──────────────────────────────────────────╮
│  │ Latest · You                             ○│ Reply
│  │ The refresh should remain asynchronous.  │
│  │                                          ○│ Resolve
│  ╰──────────────────────────────────────────╯
```

M-summary is the existing timeline row. Its right side owns quiet toolbar
actions, with Expand immediately before More. M-last is the compact body below
it. They are information layers in one component, not two stacked cards. The
latest body may truncate compactly. Temporary output-selection differences stay
inside Review output and never appear as summary status. Full content remains
available in the expansion.

## 9. Inline complete-thread expansion

The expanded thread remains inside Pierre's annotation row and composes the
owned shadcn Button, Tooltip, Textarea, and Avatar primitives. It is not a
Popover and does not own a ScrollArea. The same keyed M-last stays mounted while
the missing earlier messages are inserted. The result is one timeline:
M-summary followed by M1 through Mn exactly once.

```text
◉ M-summary                              Collapse · More
│
◉ M1                                          Edit · Reply
│ first message
│
◉ M2                                          Edit · Reply
│ intermediate message
│
◉ M-last                    Edit · Reply · Resolve/Reopen
│ latest message
│
◉ Draft reply                               Revert · Save
```

Requirements:

- one inline expansion owned by the existing Pierre annotation row;
- flat chronological M1 ... Mn rows, ordinal-sorted and rendered once;
- no card around every message;
- separators and spacing distinguish messages without nested surfaces or a
  second timeline;
- Expand opens chronology; Reply/Edit open chronology with the stable editor;
- one Resolve/Reopen command exists at thread level;
- expanded summary omits the redundant blue node because message avatars own
  the visible chronology nodes;
- expanded message nodes use a 4 px gap and a neutral semantic rail rather than
  an outer bordered thread card;
- M-last remains the same keyed DOM element across compact/expanded states;
- Pierre remeasures expansion while preserving the expanded row top and scroll
  anchor; later diff rows move down and return on collapse;
- no floating layer, Popover chronology, or nested thread scrollbar;
- collapsing removes hidden content from keyboard/accessibility traversal and
  returns focus to the exact invoking control.

## 10. Focus, keyboard, and collapse

- focusing the compact shell or clicking its non-control body activates the
  stored Pierre range and never opens chronology by itself;
- Expand, Edit, or Reply explicitly expands the thread;
- Tab traverses actual controls in visible order; the whole page is not made of
  arbitrary tab stops;
- collapsed history is absent from Tab and accessibility traversal;
- Escape while editing flushes/exits editing and keeps the thread expanded;
- a second Escape with no active editor collapses the thread;
- outside click while editing flushes and collapses the thread;
- outside click with no editor collapses the thread;
- closing returns focus to the exact invoking circular button;
- Save/Revert ends editing but keeps the thread expanded;
- losing comment activity with no expanded thread clears saved-range paint;
- no focus transition may unmount/remount the editor or lose its current text.

## 11. Pierre range integration

Pierre owns range paint and endpoint/gutter placement. The annotation component
owns message state and commands.

```text
inactive compact thread   ──► endpoint-anchored projection; no full range paint
focused compact thread    ──► full stored range paint
expanded thread           ──► retain full stored range paint
another thread activated  ──► move paint to that thread
comment activity cleared  ──► clear saved range paint
```

- only one pending-or-saved range writer may control Pierre `selectedLines`;
- inactive comments do not paint every saved range simultaneously;
- there is no location button because active range paint supplies that feedback;
- dragging must show immediate selection feedback;
- endpoint `+` must be visible and usable for single-line and multi-line ranges;
- comments appear only at their stored file/range, not every page or unrelated
  file.

## 12. Markdown and message content

- comments accept Markdown with H2-H6 but reject H1;
- raw HTML is rejected;
- a message body is limited to 16 KiB;
- users needing more content may add replies;
- saved Markdown renders through the owned annotation Markdown component;
- body typography must use the existing typography utilities until the shared
  typeset program supplies its compact preset;
- no parallel typeset/token system is created in this lane;
- body text is top-aligned, readable, and not visually treated as textarea text
  once saved.

## 13. Thread and message semantics visible in UI

- every comment belongs to a flat thread;
- replies are flat chronological messages, not nested reply trees;
- Resolve/Reopen changes the whole thread;
- saved messages remain editable while their status is `editable`; successful
  or crash-unknown output changes included messages to `locked`, after which
  they cannot be edited and remain replyable;
- Copy is temporary output state, not a durable message status;
- messages may visibly communicate Draft/Saved/Locked where supported;
- copied/exported does not mean an agent addressed the comment;
- PR1 has only human-authored messages; agent participation is PR2.

Edit is a capability-derived control. It appears only for `editable` messages
and opens the inline expanded editor; it never appears for `locked` messages.

## 14. Copy Markdown and Export JSON

- PR1 output options are Copy Markdown and Export JSON file;
- Copy uses the existing native handoff and shows a concise shadcn Sonner toast;
- successful Copy closes only the output-selection interaction, not the thread
  expanded thread and not the comment itself;
- Copy does not automatically Resolve the thread;
- Export uses the existing save-file handoff;
- Markdown output is human/model-readable, path-led, and includes file and line
  coordinates;
- Markdown separates selected comments cleanly and permits comment bodies to
  retain H2-H6 content;
- JSON export preserves structured fields with Markdown message bodies;
- output selection may include arbitrary eligible messages;
- output/history UI must not become a global comments panel.

## 15. Visual language and tokens

- compose from owned shadcn primitives in `BridgeWeb/src/components/ui/`;
- use registered role/context utilities, including the frozen `comment-*`
  utilities when present;
- do not use raw colors, `var(--bridge-*)`, new `dark:` variants, or feature-local
  design tokens;
- do not edit `bridge-app.css` in this UI lane;
- use the shared compact control scale;
- preserve one coherent radius hierarchy: circular controls, circular avatar,
  strongly rounded rectangular message/composer surface;
- avoid generic card stacks, gratuitous borders, large gray gutters, and modal
  chrome that repeats information;
- active, hover, focus, draft, and resolved are distinct states with one owner
  each;
- Save primary color does not turn every surface border into primary blue.
- selected source lines retain Pierre's yellow selection paint, but selected
  annotation rows reuse Pierre's dark `--diffs-annotation-bg`; no extra React
  backing card is added to compensate for Pierre's selected-row mix.

## 16. Current implementation defects to remove

| Defect | Current source owner | Required correction |
| --- | --- | --- |
| Rounded-square icon controls | `worktree-annotation-inline-surface.tsx`, shared `Button icon-xs` | shared circular icon Button size; no feature-local geometry system |
| Giant root/reply composer card | `worktree-annotation-composer.tsx` | compact shared shell and integrated transparent Textarea |
| Nested cards and borders | composer/message/expansion components | one surface owner; flat inline chronology |
| Duplicate chronology | compact and expanded branches | compact M1 or summary+latest; expanded summary + M1...Mn exactly once |
| Floating thread chrome | deleted `worktree-annotation-thread-overlay.tsx` | keep chronology inside the shared Pierre annotation row |
| Tiny inconsistent icons | local command wrapper and Lucide call sites | canonical icons and shared optical size |
| Saved body/card blue outline everywhere | active/surface styling | active range and restrained active rail/surface state; no blanket focus-card look |
| Excess blank lane/card space | conversation frame and surface minimums | content-driven height and visually quiet lane |
| Arbitrary article tab stop | inline surface `tabIndex=0` | intentional keyboard entry and roving/semantic control path |
| Timeline/action redundancy | compact thread command assembly | exact ownership matrix from section 6 |
| Location control | stale command assembly | remove; Pierre range paint owns feedback |
| Editor flicker/unmount | projection/interaction reconciliation | preserve DOM/editor identity through projection updates |
| Comments on unrelated pages/files | viewer integration/placement lookup | exact file/range scoping only |

## 17. Implementation ownership map

```text
components/ui/button.tsx
  owns circular icon geometry and standard variants

worktree-annotation-inline-surface.tsx
  owns avatar timeline + one rounded message/composer surface

worktree-annotation-compact-thread.tsx
  owns only 1-message versus 2+-message projection

worktree-annotation-thread-message.tsx
  owns one message body, metadata, and capability-driven message controls

worktree-annotation-composer.tsx
  owns textarea, draft state, Revert, Save, and validation

viewer interaction controller / Pierre adapter
  owns active thread, inline expansion invoker, range paint, and focus restoration
```

Do not create another wrapper layer simply to avoid correcting these owners.
Delete obsolete presentation structure when the responsibility no longer exists.

## 18. Execution checklist

Current order is contract-first, then visual proof:

```text
1. reconcile Save/read lifecycles with BLO
2. remove the superseded inline-disclosure test contract
3. verify compact + expanded-inline component anatomy
4. run the real backend + Vite interaction loop
5. polish from screenshots without crossing the design-system boundary
```

### A. Shared primitive and anatomy

- [x] Add standard circular icon shape to the owned shadcn `Button`.
- [x] Consume circular geometry through the owned `Button`, not local dimensions/radii.
- [x] Establish canonical icon/tooltip/accessible-name mapping.
- [x] Rebuild the shared avatar/timeline/message surface anatomy in the shared inline surface.
- [x] Remove nested border/card ownership and content-height distortion.

### B. Compact projections

- [x] Render exactly M1 when message count is one.
- [x] Render summary + M-last when message count is two or more.
- [x] Collapsed: render only M-summary + M-last.
- [x] Expanded: render M-summary + M1...Mn exactly once inline.
- [x] Apply the exact right-rail and timeline command matrix.

### C. Composer

- [x] Replace giant card with compact integrated composer.
- [x] Use circular Revert and primary circular Save.
- [x] Compose Save from the owned shadcn `Button` with `Check`, primary text,
      and primary tint on hover; no solid blue/black treatment.
- [x] Preserve durable draft/autosave/focus-loss behavior.
- [x] Remove empty abandoned composers correctly.
- [x] Preserve editor DOM identity during projection updates.

### D. Inline chronology expansion

- [x] Delete the floating Popover/ScrollArea chronology owner.
- [x] Expand inside the existing Pierre annotation row.
- [x] Render flat message rows without per-message cards.
- [x] Keep one thread Resolve/Reopen control.
- [x] Integrate reply/edit composer with two-stage Escape.
- [x] Keep the same keyed M-last mounted across compact/expanded states.
- [x] Prove expansion grows the Pierre row while preserving its top and scroll anchor.

### E. Pierre interaction

- [x] Show drag-selection feedback.
- [x] Keep selected range until `+`; new-range/outside/Escape variants remain in focused proof.
- [x] Activate saved range on comment focus; clear when activity leaves.
- [x] Remove the location button.
- [x] Scope each comment to its exact file/range.

### F. Output and negative space

- [ ] Keep Copy Markdown and Export JSON only.
- [ ] Use Sonner toast for successful Copy.
- [ ] Do not Resolve on Copy.
- [x] Confirm no global/session/whole-file/sidebar/general-review UI remains.

### G. Proof

- [x] Add/update focused unit tests for render-derived compact branches.
- [x] Add/update browser interaction tests for command ownership and keyboard.
- [x] Run BridgeWeb check and focused unit/browser suites.
- [x] Use the real Swift development backend plus Vite HMR.
- [x] Inspect in Chrome at normal and narrow widths.
- [x] Inspect at a verified 200% root text scale, restore the runtime style, and
      confirm zero page/CodeView horizontal overflow.
- [ ] Capture screenshots for empty composer, durable draft, M1, multi compact,
      expanded thread, active range, inactive range, resolved, and error states.
- [x] Verify no JS edit restarts the Swift backend.
- [x] Report backend-interface failures separately to the backend lane.
- [x] Add a real Review Save/reload journey using established Review tree
      selection and real Pierre additions-side pointer geometry.
- [ ] Pass the uninterrupted File-then-Review journey on one shared worktree
      session; Review currently returns native projection unavailable after a
      File-origin thread exists.

Current UI/runtime receipt, 2026-08-19:

- exact receipt/convergence/cursor/controller unit slice: 7 files, 39 tests
  passed;
- Swift transport adapter: 7 tests passed, including exact root and Save
  message receipts;
- strict Swift annotation transport: 7 tests passed; strict JSON: 5 tests
  passed;
- full BridgeWeb typecheck and focused Oxfmt/type-aware Oxlint: passed;
- focused browser interaction: 3 files pass; the new-root exact-receipt browser
  scenario remains red above the proven request-correlation seam and is not
  accepted as complete;
- live supervised Vite: `127.0.0.1:5176`; Chrome confirmed the real current
  Review surface after the Swift backend rebuild;
- live composer geometry: 1px outer border, approximately 13px radius, 24px
  circular command targets, zero nested textarea border/padding, no narrow
  viewport horizontal overflow;
- no optimistic saved row, second transport, or projection-dependent command
  completion fallback was added.

Current inline-shell receipt, 2026-08-20:

- annotation/source unit slice: 13 files, 53 tests passed;
- annotation browser slice: 10 files, 47 tests passed;
- full BridgeWeb check and `git diff --check`: passed;
- isolated Swift backend plus Vite Review journey: range selection, root Save,
  Reply Save, compact summary + latest, expanded one-timeline chronology,
  collapse, and narrow width all exercised with real SQLite authority;
- popup focus regression: More opens without collapsing, Escape closes only the
  popup, and click-away collapses the thread;
- Chrome console after the isolated journey: zero warnings/errors;
- visual correction: ordinary commands are visible circular outline buttons,
  Save uses the primary tint Check, and active range no longer paints every
  message card with a primary border.
- 200% text proof: 32 px computed root text, page 1494/1494 client/scroll,
  CodeView 1064/1064 client/scroll, contained thread geometry, then exact
  restoration to the prior 16 px root style;
- expanded hierarchy correction: no blue summary node, no transient
  `Mixed inclusion` status, quiet non-circular toolbar actions, 4 px message
  gap, and a neutral timeline rail;
- Pierre contrast correction: selected source lines retain their normal paint
  while the selected annotation row uses Pierre's darker 78% relationship tint;
- message rail geometry: three 24 px buttons use 2 px gaps and remain fully
  inside the 80 px card with 3 px top / 1 px bottom clearance;
- File-to-Review adapter correction: File-origin threads map to the Review head
  additions side when the head path exists; focused unit/browser proof is green;
- remaining runtime blocker: a File-started viewer still receives no Review
  annotation projection after switching to Review, and output-candidate queries
  fail on fresh File-only and mixed-origin sessions despite current revisions
  and eligible SQLite rows. These precede the React shell and belong to the
  worker/native runtime lane.

### H. Save and read-convergence lifecycle

- [x] Consume the runtime lane's exact new-root identity/revision receipt; do
  not discover the created message through projection before issuing Save.
- [x] Delete `awaitingProjection` from the composer Save state.
- [x] End Save disabled/spinner state on the exact committed or failed command
  response.
- [ ] Keep command failure in the composer, retain the draft, and present it as
  Save failure.
- [x] Model projection reads as `ready | refreshing | unavailable`, retaining
  the last complete snapshot in all dirty/degraded states.
- [x] Present refreshing/unavailable as read status, never as `Saving` or
  `Committed · updating thread` Save progress.
- [x] Do not fabricate saved rows or optimistically mutate projection data.
- [x] Prove an existing-message Save completes while projection is blocked.
- [ ] Prove committed Save remains successful when projection fails, and the
  retained last-complete view recovers atomically.
- [ ] Prove new-root Save no longer waits indefinitely for projection before
  it can issue the requested save mutation.

## 19. Acceptance gate

The UI remediation is not complete until all of the following are true in one
current build:

```text
✓ circular standard shadcn command buttons
✓ compact root composer
✓ M1-only single-message inline projection
✓ summary + latest multi-message inline projection
✓ expansion animates M1...M(n-1) between M-summary and the same M-last
✓ no nested card stack
✓ stable editor with no flicker or first-character disappearance
✓ visible drag feedback and active-only range paint
✓ exact command ownership with no redundant controls
✓ no global/session/whole-file/general-review UI
✓ exact file/range scoping
✓ Copy Markdown and Export JSON remain functional
✓ keyboard, focus restoration, narrow, and 200% text proof
✓ focused automated tests and live Chrome screenshots
```

Passing DOM tests without live visual proof is insufficient. A screenshot that
looks correct without working Save/Reply/focus behavior is also insufficient.

## 20. Governing references

- `docs/specs/2026-08-06-worktree-annotations/pr1-user-requirements.md`
- `docs/specs/2026-08-06-worktree-annotations/pr1-specification.md`
- `docs/specs/2026-08-06-worktree-annotations/pr1-program-design.md`
- `tmp/pr1-inline-comment-presentation-remediation-2026-08-17.md`
- `BridgeWeb/src/components/ui/button.tsx`
- `BridgeWeb/src/worktree-annotations/`

Where this WIP and the current presentation implementation disagree, this WIP
drives UI remediation. Where this WIP conflicts with the durable non-UI domain
or transport contract, stop and report the exact conflict to the owning lane.
