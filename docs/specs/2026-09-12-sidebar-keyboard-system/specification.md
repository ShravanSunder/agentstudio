# Keyboard sidebar system

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) → this
Specification → [Program Design](program-design.md).

The sidebar is the visible navigator. Users enter its list, choose Panes or Repos,
filter and inspect results, then commit to a destination or return to their work.
Keyboard hints belong over existing UI. An independent invisible activity/history
stack and a sticky navigation-owner flag are not part of this system.

```text
Work in pane → focus sidebar → choose/filter/select
                                    |
                          preview (temporary) or commit
                                    |
                          return or work in destination
```

This journey serves U1/U3/U4/U5/U12/U15/U16. Committed pane visibility delegates to
the separate [arrangement contract](../2026-09-12-arrangement-visibility/specification.md)
for U6/U7. Pinned-pane navigation U14 remains an independent direct action whose
ordering/reach is not defined by sidebar result numbering.

## Required behavior

**R-S1.** Command-S MUST toggle sidebar visibility while retaining its selected
surface. Command-Shift-S MUST reveal the sidebar if hidden and move actual keyboard
focus into its list. While Management is active, Command-Shift-S MUST do nothing
and MUST NOT exit Management. Merely showing the sidebar MUST NOT select Repos. Basis U3/U4.

**R-S2.** With sidebar list focus, P and R MUST select Panes and Repos respectively.
F MUST enter the existing current-list filter. In an editable field those letters
and digits MUST remain text input. This is F-then-type filtering, not unrestricted
list type-ahead. Basis U3/U5 and current approved direction.

**R-S3.** Filter text changes MUST continue updating visible results. Enter in the
filter MUST preserve the query and return focus to the table without activating a
result. Basis U5 and owner Enter-to-table request.

**R-S4.** The list MUST expose a visible keyboard selection independent from the
active pane. The first-nine result capability MUST address current actionable rows
by the same identity shown by its badges, never an obsolete numeric row index.
Headings are not pane/worktree destinations. Digits 1–9 MUST immediately activate the corresponding result; they do not merely
select or preview it. Selection fallback remains open below. Basis U5.

**R-S5.** Enter on a pane destination MUST commit navigation through the shared
arrangement-reveal path and focus the actual pane. A worktree row's primary action
remains worktree open; it is not interchangeable with pane focus or a repository pin.
Missing/stale targets MUST NOT activate a different result or create a replacement
pane. Basis U4/U5/U7.

**R-S6.** Shortcut hints MUST be a visual overlay anchored to existing controls or
numbered rows. They MUST NOT add header rows, move existing controls, hide/dim the
workspace, or intercept pointer events. The small focus icon belongs at the marked
leading location in the existing second toolbar row. Hints and the icon MUST reflect
effective keyboard ownership and action availability, not an independent navigation
flag. List command hints MUST NOT claim ordinary letters while a filter/editor owns
text input. Exact glyph and reveal policy remain subject to visual review. Basis U16
and owner's latest overlay instruction.

**R-S7.** Existing Option-I/J/K/L spatial and Command-Shift-I/J/K/L terminal
scroll/prompt commands MUST retain their roles. Existing Commands and Panes search
bindings MUST NOT be silently repurposed. New command displays MUST come from the
existing command/action spec system. Basis U12 and repo governing instructions.

**R-S8.** Row filtering, grouping, navigation-index derivation and list-sized
calculations MUST remain off MainActor. MainActor MAY apply already-derived current
values, actual responder changes, selection/scroll and AppKit geometry. A keypress
MUST NOT initiate a full sidebar capture/projection merely to move a row selection.
The overlay MUST NOT add polling or an independent observer on raw terminal output.
Basis U1, explicit performance instruction and existing derived-state architecture.

**R-S9.** Temporary preview MUST remain distinct from committed navigation: the
user can inspect a selected existing pane and use Enter to go there. It MUST NOT
be implemented as committed focus followed by a blind restoration of durable state.
Preview MUST last only while its key is held; releasing the key MUST cancel
uncommitted preview. Enter commits the selected pane, and numeric activation commits
its addressed result; later key release MUST NOT undo that committed navigation.
The exact preview key and presentation placement remain open. Basis U15.

## Choices still to settle

These are isolated from the settled arrangement capability and other source/design
work. They are not silently resolved by choosing an implementation mechanism.

| Choice | Candidate default | Consequence |
| --- | --- | --- |
| Exact preview key | Space remains proposed | Hold/release behavior is settled; choose an available list-context binding |
| Preview target in another tab | Temporary presentation with no durable tab switch | Requires explicit mount/visibility participation, not just showing a hidden view |
| Escape/filter cancellation and vanished origin | Return to list, then existing origin | Query preservation and fallback destination need exact contract |
| Pinned-pane ordering/reach/wrap | No selected default | Separate U14 behavior; do not inherit discarded history semantics |

Current row/group arrow behavior can be evaluated as normal focused-list interaction;
extra G/I/J/K/L bindings are not required by this Specification. No nine-item pinned
working-set assumption, general chord engine, file-finder redesign or new workspace
window model is selected.

## Proof modalities

| Needs / requirements | Evidence required |
| --- | --- |
| U3/U4, R-S1/R-S2 | Real focus entry, surface switching, hidden/sidebar states, keyboard ownership with editable and transient surfaces |
| U5, R-S3/R-S4/R-S5 | Filter-to-table Enter, first-nine mapping during filter/regroup/update, exact target activation and stale-target rejection |
| U16, R-S6 | Native visual inspection at practical sidebar widths/scales; anchor/clipping/selection, no layout shift or click interception |
| U1/U12, R-S7/R-S8 | Catalog/dispatch coverage, existing shortcut regression checks, marker-scoped performance evidence separating capture/derivation from UI apply |
| U15, R-S9 | Preview/commit/dismissal with real native hosts once its observable choices are resolved |

No current runtime result or performance pass is claimed. Source inspection alone
does not establish focus or renderer behavior.
