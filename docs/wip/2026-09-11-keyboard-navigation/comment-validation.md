# Sidebar critique — source validation

Historical validation of the supplied critique, before the owner's later
first-nine list-result and Preview requests. Its source findings remain evidence;
its then-current feature-scope statements do not override the current
[Requirements](requirements.md) or [review map](keyboard-map.md).

Inspected navigation checkout HEAD `aae07e0a0d59d43d4522c43946b80564795f5d4e`.
This validates claims in the owner's supplied critique; it is not independent
three-artifact design review or native UI proof.

## Findings

| Claim | Disposition and evidence |
| --- | --- |
| Keyboard ownership must not be independently stored or manually assigned | Correct. `KeyboardOwner.current` derives from key-window registration, Management and sidebar visibility/focus. `KeyboardRoutingContext` additionally gives command-bar/transient surfaces precedence. |
| A mode icon necessarily creates a second state flag | Incorrect implication. An icon or hint layer can be a projection of effective focus ownership; no independent navigation Boolean is required. Our previous wording was too loose and is corrected. |
| `sidebarHasFocus` alone can gate navigation commands | Incomplete. The filter publishes this same Boolean. List versus text-input ownership must be distinguished from actual responder context before P/R/F or row keys are enabled. |
| The table explicitly rejects selection | Correct. `shouldSelectRow` returns false and selection changes call `deselectAll`. Adding keyboard selection is real work. |
| This proves selectable navigation is forbidden product behavior | Not established. The code proves the current implementation, not an immutable product constraint or rationale. The owner explicitly requests sidebar keyboard navigation. |
| Native arrows, type-to-filter, return focus and ring are free once focus moves | Not established for this view. The table uses hosted row views, rejects selection, exposes an integer row as object value, and has no inspected type-select override. The focus bridge's cancel operation is empty. Type-to-select is also not the same as filtering list membership. Native behavior must be deliberately integrated and verified. |
| Focused-list behavior needs no state | Too broad. It needs selected-row identity and potentially an origin for return focus. Those are legitimate transient interaction facts, not a second keyboard-owner flag. |
| Peek needs no state / only one overlay | Overstated. It needs at least modifier observation, visible hint presentation, valid target mapping and dismissal handling. If addresses can reorder, key-to-target stability matters. None of this requires durable state, but it is not zero work. |
| Pinned repositories/worktrees match the selected pinned-pane shortcut set | Incorrect. `pinRepo` targets repositories; `pinPane` targets panes. Repos rows dispatch `openWorktree`; pane rows dispatch `focusPane`. A repository can represent multiple worktrees and panes. |
| Nine pinned addresses cover 90% of the owner's work | Unsupported usage assumption. The screenshot and video do not establish frequency, working-set size or relevance of only nine destinations. |
| Option-Shift-1..9 is the accepted next feature | New proposal, not authorized meaning. Owner selected Option-Shift-Up/Down for pinned panes. No app assignment to this exact digit family was found in inspected shortcut catalog; that is not a full conflict audit. |
| Command-Shift-P is a suitable replacement for P | Conflicts now: it opens Commands. Command-P opens Everything, Command-Option-P opens Panes search. Do not quietly repurpose them. |
| Plain command letters conflict with native type-ahead | Real tradeoff. P cannot simultaneously mean switch surface and begin a typed name. Owner selected P/R/F; replacing them needs an owner choice, not a platform-convention claim. |
| Cursor's video is a different interaction model | Correct. It shows temporary shortcut discovery triggered around a modifier indication, rather than entering sidebar focus. The clip establishes visual behavior, not key-up telemetry or a measured 90% workflow. |
| The owner-requested icon must be dropped | Preference, not code requirement. It can honestly indicate sidebar-list keyboard ownership. Do not describe it as evidence that rows have numeric addresses; those are not selected features. |

## Corrected solution boundary

```text
Real focus / key window / transient surface
                   |
                   v
       Effective keyboard routing context
             /                  \
            v                    v
   enabled local actions    icon + hint layer

Selected row and return target are transient interaction data.
Neither may independently assert keyboard ownership.
```

The recommended design retains the owner's focus shortcut, P/R/F choices, visual
hint-layer direction, pinned-pane arrows and arrangement rules. It introduces no
sticky navigation flag and no nine-row addressing system. List selection/activation
and text input are explicit behavior work. Modifier-peek stays an alternative
hint-reveal trigger, not a replacement for the whole sidebar journey.

## Inspectable anchors

- [KeyboardOwner](../../../Sources/AgentStudio/Core/Models/KeyboardOwner.swift): derived owner and precedence.
- [KeyboardRoutingContext](../../../Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift): active-surface precedence.
- [Sidebar focus bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift): filter-only enum, focus publisher, empty cancel operation.
- [Sidebar state](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceSidebarState.swift): persisted preferences versus runtime focus fact.
- [Native table](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift): selection rejection and row object value.
- [Table subclass](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerContextMenuPresenter.swift): context-menu override, not a supplied navigation controller.
- [Hosted cells](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableRowCell.swift): row identity/reuse/currentness.
- [Command bindings](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcut.swift): existing P family and digit bindings.
- [Sidebar command catalog](../../../Sources/AgentStudio/Core/Actions/Commands/AppCommand+SidebarCatalog.swift): pinRepo versus pinPane.
- [Row activation](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializedRowView.swift): openWorktree versus focusPane.

No source changed. Native focus-ring geometry, input method behavior, overlay cost,
and end-to-end keyboard focus remain runtime proof obligations, not verified facts.
