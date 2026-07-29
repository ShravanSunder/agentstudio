# Pane Zoom UI Contract

## Scope

This spec replaces the Viewer command semantics, toolbar, Arrangements-panel,
arrangement-interaction, and Zoom-management presentation clauses of the
adjacent Pane Zoom spec. Its Viewer entry/toggle behavior and arrangement
transitions also supersede the conflicting clauses in the adjacent Pane Zoom
implementation plan. The existing Zoom eligibility, companion-lifecycle,
persistence, IPC, and ownership contracts remain unchanged.

## Product contract

Pane Zoom uses one name and one icon everywhere.

- The user-facing command name is `Pane Zoom`; compact icon-only surfaces may
  omit the label. `Focus`, `Zoom Focus`, and `Zoom Pane` are not Zoom
  vocabulary.
- Every Zoom control uses the SF Symbol
  `square.arrowtriangle.4.outward`.
- The inactive control enters Zoom.
- Compact management controls use the same control selected while Zoom is
  active; activating it exits Zoom.
- The active Arrangements details section instead exposes an explicit
  icon-and-text `Cancel Zoom` button using the same canonical icon.
- Switching, traversing, or creating a durable arrangement changes the
  arrangement underneath Zoom without exiting Zoom.
- Zoom must not introduce a second cancel icon, an `xmark.circle` replacement,
  or an all-caps floating `ZOOM PANE` badge.

## Ownership map

```text
AppCommandSpec
  owns: Zoom, Viewer, Copy Path, and location-action identity

PaneSurfaceToolbarPresentation
  owns: normal-versus-Zoom toolbar membership and ordering

DrawerIconBar
  owns: shared button geometry, semantic action groups, and divider spacing

ArrangementPanel
  owns: normal pane visibility rows and active Pane Zoom details

ZoomPresentationContainer
  owns: one parent Zoom chrome and suppression of child pane chrome
```

Presentation changes must not create another Zoom state owner or change durable
pane membership.

## Bottom toolbar

### Normal terminal

```text
[Drawer Toggle] [Add Drawer]
                  [Zoom] [Viewer] [Editor] │ [Finder] [Copy Path] │ [Notification]
```

### Zoomed terminal

```text
[Drawer Toggle] [Add Drawer]
        [Zoomed selected] [Viewer] [Editor] │ [Finder] [Copy Path] │ [Notification]
```

The inactive `[Zoom]` control is icon-only. After Zoom mounts, that same control
morphs into the selected canonical icon plus `Zoomed`; it does not add another
control or render the command label `Pane Zoom`.

The ordering is contractual:

1. Zoom precedes Viewer, and Viewer precedes Editor, in normal and Zoom states.
2. Viewer remains available outside Zoom so it can enter Zoom and ensure the
   Viewer is visible.
3. Finder precedes Copy Path.
4. Notification is the final isolated action.
5. Drawer Toggle and Add Drawer remain adjacent without a divider.

The semantic groups are:

```text
drawer structure          pane context         │ location          │ alerts
Drawer Toggle, Add Drawer Zoom, Viewer, Editor Finder, Copy Path Notification
```

Every icon-only control uses the existing shared square hit target, hover fill,
selected fill, alignment, tooltip, and accessibility contracts. Every semantic
group divider uses `AppStyles.General.Spacing.standard` as horizontal padding on
both sides. The current two-point divider padding is not the accepted toolbar
scale.

Copy Path uses the existing pane-path command and copies the source terminal's
actual current working directory. Finder and Copy Path share the same path
availability state. When the terminal has no live actual CWD, both actions are
unavailable; the worktree root must not be substituted and presented as the
actual CWD.
Copy Path uses the `document.on.document` symbol everywhere through the shared
`LocalActionSpec.copyPath` presentation.

## Keyboard shortcuts

The typed `AppShortcut` and `AppCommandSpec` catalog owns this shortcut family:

| Shortcut | Command | Behavior |
| --- | --- | --- |
| `Command-O` | Viewer | Outside Zoom, enter Zoom and ensure Viewer is visible. Inside Zoom, toggle Viewer visibility without exiting Zoom. |
| `Command-Option-O` | Open in bookmarked editor | Open the active pane's actual location in the configured/default editor. |
| `Command-Option-Control-O` | Editor chooser | Open the editor chooser for the active pane. |
| `Option-O` | Copy Path | Copy the active pane's actual current working directory. |
| `Command-Shift-Return` | Pane Zoom | Enter or cancel Pane Zoom without changing Viewer visibility independently. |
| `Command-Shift-O` | Finder | Preserve the existing Finder shortcut. |

Viewer is a composite entry/toggle command, not a Zoom-exit command:

```text
normal                     -- Command-O --> Zoom + Viewer visible
Zoom + Viewer hidden       -- Command-O --> Zoom + Viewer visible
Zoom + Viewer visible      -- Command-O --> Zoom + Viewer hidden
any Zoom state             -- Command-Shift-Return --> normal
```

Toolbars, command rows, and menus project their shortcut text from the typed
command catalog. They must not carry parallel tooltip strings.

## Arrangements panel

### Normal state

The normal panel retains Pane Visibility. Every Zoom-capable durable terminal
main-pane row exposes the same Zoom icon used by the toolbar. Unsupported panes
do not gain Zoom capability.

```text
ARRANGEMENTS
[Default] [Add Arrangement]

────────────────────────────────────────
Pane Visibility

● repo | branch | worktree folder                 [Zoom] [Hide]
● repo | branch | worktree folder                 [Zoom] [Hide]
```

### Active Zoom state

Pane Visibility is hidden while Zoom is active. The panel shows only the
existing arrangement controls followed by one title-case `Pane Zoom` details
section.

```text
ARRANGEMENTS
[Default] [Layout 1] [Add Arrangement enabled]

────────────────────────────────────────
Pane Zoom

repo | branch | worktree folder        [icon Cancel Zoom]
/full/current/working/directory
```

Pane Zoom is a status/details block, not a selected list row. It does not use a
selection dot or selected-row background. The identity and path remain grouped,
with an explicit trailing Cancel Zoom action.

The fields are:

- Primary: repository name, branch name, and worktree folder name.
- Secondary: the source terminal's actual current working directory as a full
  path, not a relative path.
- Tooltip/accessibility value: the complete current working directory.
- Trailing action: an icon-and-text `Cancel Zoom` button using the canonical
  Zoom icon. Activating it exits Zoom.

The CWD may truncate through the middle for layout, but the underlying value and
tooltip remain the complete path. If no live actual CWD exists, the path is
absent and path actions remain unavailable; the worktree root is not a
substitute. The block must not show duplicated repository and worktree labels
as two unexplained `actual` lines, selected-list styling, Pane Visibility, or a
list of retargetable panes.

### Popover continuity and arrangement editing

The Arrangements popover is a stable workspace. It remains open when the user:

1. enters or cancels Zoom;
2. switches or traverses arrangements;
3. creates an arrangement; or
4. begins, commits, or cancels an arrangement rename.

Only Escape, an intentional outside click, or explicitly toggling the
Arrangements control closes it. Inline rename owns keyboard focus until Enter,
Escape, or an intentional outside click. Starting a rename must not flicker,
briefly replace the field with a chip, or dismiss and reopen the popover.

### Minimized panes and quick-access ordinals

Opening the normal Arrangements panel temporarily reveals minimized pane bars
without changing their durable minimized state or activating Management mode.
Closing Arrangements hides those bars again unless Management mode is active.

A minimized bar uses `eye.slash.fill` in the same circular badge geometry,
icon scale, and spacing as the ordinal badge it replaces. Minimized rows in
Pane Visibility use the same filled hidden-eye symbol as their state indicator;
their trailing Show action remains `eye` because activating it restores the
pane.

Pane ordinals are quick-access indices for expanded panes, not stable pane
identities:

- expanded panes are numbered densely in current layout order;
- minimized panes have no ordinal and show `eye.slash.fill` instead;
- minimizing or restoring a pane recomputes the expanded-pane ordinals; and
- `Option-1` through `Option-9` target only expanded panes and never restore a
  minimized pane.

### Viewer split memory

The source/Viewer divider ratio is runtime presentation memory owned per Zoom
source pane. It survives Viewer hide/show, arrangement changes, and explicit
Cancel Zoom followed by re-entry for the same retained source/companion during
the app session. It resets when that source's retained companion is retired,
the source becomes invalid, or the app restarts. The ratio is not durable
workspace state and must not be written to SQLite.

### Presentation transitions

Zoom entry mounts the Zoom presentation and its toolbar, then morphs only the
Zoom control from the canonical icon into selected icon plus `Zoomed` using
`AppStyles.General.Animation.standard`. Cancellation contracts that control
back to the icon using `AppStyles.General.Animation.fast`, then cancels Zoom and
identity-replaces the pane and toolbar. Retargeting remains identity replacement
without animation.

Viewer visibility remains a separate transition: showing Viewer opens the split
from the center toward the Viewer side, and hiding Viewer collapses it from the
center toward the Viewer side. Viewer motion uses the existing
`AppStyles.General.Animation.standard` timing and must not duplicate, snapshot,
or recreate a terminal or Viewer host.

### Arrangement changes during Zoom

Zoom is a runtime presentation above the selected durable arrangement.
Switching or traversing arrangements changes the selected arrangement
underneath Zoom and preserves the same Zoom source and retained Viewer
companion. Exiting Zoom reveals whichever durable arrangement is then active.

Arrangement creation remains enabled during Zoom, including while Default is
selected. Creating an arrangement:

1. snapshots the underlying durable pane layout;
2. excludes Zoom presentation, Viewer companion, and Viewer visibility;
3. makes the new durable arrangement active underneath Zoom; and
4. leaves Zoom active with the same source.

Ordinary arrangement switching, traversal, and creation must not cancel Zoom.
Zoom ends only when the user toggles it off or its real source becomes invalid
through source-pane deletion, tab teardown, workspace teardown, application
teardown, or existing invalid-resource recovery.

## Zoom management chrome

Normal and active Zoom use the same Zoom and Arrangements controls in the same
top-left positions. The Pane Zoom/Cancel Zoom control is immediately left of
Arrangements. Zoom changes its selected state and active accessibility/tooltip
meaning without moving it.

```text
normal       [Pane Zoom]          [Arrangements]
active Zoom  [Cancel Zoom selected] [Arrangements]
```

The durable source preserves the existing management title convention and
appends the Zoom state:

```text
normal       <pane ordinal> · <active arrangement name>
active Zoom  <pane ordinal> · <active arrangement name> · Zoom

example      1 · Layout 1 · Zoom
```

The source ordinal and active arrangement name remain live while Zoom is
active. Switching or creating an arrangement updates the middle segment without
removing the `· Zoom` suffix. Default follows the same convention:
`1 · Default · Zoom`.

The retained Viewer companion is not a durable pane and therefore has no pane
ordinal. Source and Viewer child management toolbars remain hidden beneath the
single Zoom parent chrome. The Viewer may show its Files/Review product surface,
but visible product chrome must show only user-facing file/review context. It
must not render a numbered pane badge or the transport `sourceId`, which embeds
the raw companion identity.

## Requirements

- R1: All Pane Zoom entry and exit controls use the canonical icon and accepted
  compact-toggle or explicit-Cancel model.
- R2: No user-facing Zoom surface uses `Focus`, `Zoom Focus`, a replacement
  cancel icon, or an all-caps floating Zoom badge.
- R3: Zoom toolbar actions render in the exact accepted order.
- R4: Toolbar dividers use shared standard horizontal padding.
- R5: Copy Path is present and copies only the source terminal's actual CWD;
  path actions are unavailable rather than falling back to the worktree root.
- R6: Normal Arrangements rows expose Zoom for Zoom-capable panes.
- R7: Active Zoom hides Pane Visibility and renders only the Pane Zoom
  status/details block beneath arrangement controls.
- R8: Pane Zoom identity is `repo | branch | worktree folder`; its secondary
  value is the full actual CWD.
- R9: The explicit `Cancel Zoom` button uses the canonical Zoom icon and exits
  Zoom.
- R10: Viewer companion chrome exposes no pane number, transport `sourceId`, or
  raw companion identity.
- R11: Switching or traversing durable arrangements preserves Zoom and changes
  only the arrangement underneath it.
- R12: Arrangement creation remains enabled during Zoom and snapshots only the
  underlying durable layout.
- R13: Arrangement transitions exclude Zoom and its Viewer companion from
  durable arrangement state.
- R14: Only explicit Zoom exit or real source/lifecycle invalidation forcibly
  ends Zoom.
- R15: Active source management titles render
  `<pane ordinal> · <active arrangement name> · Zoom` and update the arrangement
  segment when the underlying selection changes.
- R16: The Arrangements popover remains open across Zoom, arrangement
  selection/creation, and inline rename actions; rename focus is stable.
- R17: The bottom Pane Zoom toolbar control is icon-only while inactive and
  morphs into the selected canonical icon plus `Zoomed` while Zoom is active.
- R18: The source/Viewer split ratio is remembered per source across transient
  Zoom presentation changes and remains excluded from durable persistence.
- R19: Zoom entry expands only the mounted Zoom control using standard timing;
  cancellation contracts it using fast timing before identity replacement;
  retargeting does not animate. Viewer show/hide retains the accepted
  center-to-side transition without changing host identity.
- R20: Active management chrome places Cancel Zoom immediately left of
  Arrangements at the top-left.
- R21: Opening normal Arrangements reveals minimized bars without changing
  minimized state or activating Management mode.
- R22: Minimized pane bars and Pane Visibility rows use `eye.slash.fill`;
  minimized bars reuse the ordinal badge geometry and have no number.
- R23: Pane ordinals and `Option-1` through `Option-9` address only expanded
  panes in dense layout order and never restore minimized panes.
- R24: The typed shortcut catalog exposes the accepted Viewer, editor, chooser,
  Copy Path, Pane Zoom, and Finder bindings; Viewer outside Zoom enters Zoom
  with Viewer visible, while Viewer inside Zoom only toggles Viewer visibility.

## Proof expectations

- Presentation tests assert exact normal and Zoom toolbar membership, order,
  dividers, and icon identity.
- Toolbar rendering tests assert standard divider padding, Copy Path
  availability, typed tooltips, and accessibility identifiers.
- Arrangement display tests assert mutually exclusive Pane Visibility and Pane
  Zoom sections plus explicit Cancel Zoom status-block presentation.
- Arrangement projection tests assert primary identity and full-CWD secondary
  value without duplicate fallback labels.
- Arrangement transition tests assert that switch, traversal, and creation
  preserve Zoom while changing the active durable arrangement.
- Arrangement persistence tests assert that arrangements created during Zoom
  exclude Zoom state, Viewer companion identity, and Viewer visibility.
- Management-chrome tests assert canonical Zoom icon reuse and suppression of
  the cancel icon, floating badge, and Viewer ordinal.
- Management-title tests assert the source ordinal, live arrangement name, and
  title-case `Zoom` suffix for Default and named arrangements.
- Popover presentation and native interaction tests assert that Zoom,
  arrangement selection/creation, and rename do not dismiss or flicker the
  Arrangements popover.
- BridgeWeb product tests assert visible File Viewer chrome never renders the
  transport `sourceId`.
- Runtime-state and mounted split tests assert per-source ratio restoration
  across Viewer hide/show and Cancel/re-entry, plus persistence exclusion.
- Transition-state tests and native recordings assert Zoom-control morph
  ordering, identity replacement after contraction, direction and duration
  bounds for Viewer, terminal/Viewer host continuity, and final geometry.
- Shortcut tests assert dense expanded-pane ordinals and prove that targeting
  an ordinal does not restore minimized panes.
- Shortcut and controller tests assert exact O-family decoding, typed tooltip
  projection, Pane Zoom decoding, and the normal-to-Zoom Viewer transition.
- Native screenshots assert Arrangements reveals minimized bars with matching
  filled hidden-eye indicators and unchanged badge geometry.
- PID-targeted native screenshots cover the normal toolbar, Zoom toolbar,
  normal Arrangements panel, active Pane Zoom details, and Viewer companion.

## Non-goals

- Changing Zoom runtime ownership or durable arrangement membership.
- Changing Viewer companion retention or Bridge lifecycle.
- Adding active-Zoom pane retargeting to the Arrangements panel.
- Showing Pane Visibility during active Zoom.
- Adding Copy Branch, Copy Folder Name, or a copy menu.
- Building a generic toolbar framework.
- Changing the Bridge protocol or source identity used for transport and
  diagnostics. Only its user-visible File Viewer projection changes.
- Implementing the separate CommandContext restoration.
