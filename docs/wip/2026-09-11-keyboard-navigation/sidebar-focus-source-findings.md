# Sidebar focus: current-source findings

Source checked 2026-09-12 on `navigation-cmds`, after arrangement implementation.
This is working evidence for the sidebar Program Design, not an accepted contract.

## Empty results still need a keyboard destination

`RepoExplorerMaterializationHost.applyRowlessPresentation` detaches and removes the
content child, then presents the empty/no-results child. A focus target that exists
only on `RepoExplorerTableMaterializer` would disappear when filtering finds nothing.
The host itself remains a visible, full-size list region across these transitions.

The smallest candidate is to make that existing host the list-region responder.
Its content child can own row selection and scrolling when present. The host can
still interpret P/R/F when no rows exist. The existing 1×1 `RepoExplorerFocusBridge`
would retain only its filter-request role, with no responder ownership.

```text
Command-Shift-S → existing shell reveal/focus request
                         |
                         v
             visible materialization host
                   /             \
           content table       empty/results message
           selection/scroll    P/R/F still available
```

Parent verified: `RepoExplorerMaterializationHost.swift` content/rowless transitions;
`RepoExplorerView.swift` 1×1 bridge and filter callbacks; `MainSplitViewController.swift`
existing focus lookup/retry. The source delegate's finding is accepted as evidence.
Updating the structural draft still needs to keep the actual row navigation path
explicit; a focused region alone does not deliver row navigation.

## Management is an observable choice

`KeyboardOwner.current` gives active Management precedence over sidebar focus.
Moving first responder into the sidebar while leaving Management active would
still suppress sidebar keyboard commands and hints. The pending owner question is
whether Command-Shift-S exits Management or stays unavailable during Management.
No extra keyboard-owner flag can fix that policy conflict.

## What can stay independent

Visibility rebinding, focus publication, P/R/F and filter Enter do not require new
row indexes. First-nine and group/row indexes belong with their actual navigation
consumer in the existing detached projection worker. Preview mount/geometry
admission, preview trigger and digit activation remain separate unresolved choices.
No new atom, store, event, observer, or projection-on-keypress is selected here.

Native proof must cover content→no-results→content focus continuity, filter typing,
Enter back to the list, hidden-sidebar entry and effective hint suppression.
No sidebar runtime proof or independent review is claimed yet.

## Native Bridge focus boundary observed during arrangement proof

The existing PaneFocusExecutor chooses BridgePaneMountView because it accepts first
responder. Its nested NSHostingView/WebView receives no explicit inner focus transfer.
BridgeWeb CmdShiftF listens on DOM document. Native sidebar activation can reveal and
focus the outer host while that shortcut remains unavailable until web interaction.
Native proof: Files reveal retained5016items; clicking search then typingREADME
filtered11items. Source: App/Panes/Hosting/PaneHostView.swift:134;
App/Panes/PaneFocusExecutor.swift:284; Features/Bridge/Views/BridgePaneMountView.swift:32.
This is a baseline keyboard-boundary gap for the sidebar design to resolve explicitly,
not an arrangement policy failure. No new source change approved or implemented here.
