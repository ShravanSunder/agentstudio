# Workspace Settings JSON

## Status

Checkpoint C3 companion for the AgentStudio SQLite cutover.

This file owns intentional, user-editable workspace preferences.

## Target File

```text
<AppDataPaths.workspacesDirectory()>/<workspace-id>.settings.json
```

Settings stay JSON in Step 1 because the app already has Codable
infrastructure. A future TOML/JSONC decision can be made when a real
user-editing workflow exists.

## Settings File Sketch

```json
{
  "schemaVersion": 1,
  "workspaceId": "00000000-0000-0000-0000-000000000000",
  "editorChooser": {
    "bookmarkedEditorId": null
  },
  "sidebar": {
    "checkoutColors": {
      "checkout-key": "#7C9CFF"
    }
  },
  "notifications": {
    "grouping": "byTab",
    "sort": "newestFirst",
    "bellEnabled": false
  }
}
```

## Mapping

```text
WorkspacePersistor.PersistableUIState
  editorChooser.bookmarkedEditorId
    -> settings.editorChooser.bookmarkedEditorId

EditorPreferenceAtom
  bookmarkedEditorId
    -> settings.editorChooser.bookmarkedEditorId

EditorChooserRuntimeAtom
  openForPaneId
    -> runtime-only, not settings

  availableTargets
    -> runtime-only, not settings

SidebarCheckoutColorAtom
  checkoutColors
    -> settings.sidebar.checkoutColors

WorkspacePersistor.PersistableSidebarCache
  checkoutColors
    -> settings.sidebar.checkoutColors

InboxNotificationStore.Payload
  prefs.grouping
    -> settings.notifications.grouping

  prefs.sort
    -> settings.notifications.sort

  prefs.bellEnabled
    -> settings.notifications.bellEnabled

InboxNotificationPrefsAtom
  grouping
    -> settings.notifications.grouping

  sort
    -> settings.notifications.sort

  bellEnabled
    -> settings.notifications.bellEnabled
```

## Rules

- schema version is mandatory
- workspace id is mandatory
- unknown keys are stripped on write unless a later migration explicitly adds an
  opaque round-trip field
- new settings keys require a schemaVersion bump or an explicitly recoverable
  default
- JSON output is `.prettyPrinted` and `.sortedKeys`
- corrupt settings are quarantined and reset to defaults
- settings corruption never resets `core.sqlite`
- settings corruption never deletes `<workspace-id>.local.sqlite`

## Not Settings

These are not settings even though they are visible in the UI:

```text
active tab / active pane / active arrangement
  -> local cursor state

window frame / sidebar width
  -> local relaunch memory

sidebar filter text / sidebar collapsed
  -> local relaunch memory

recent targets
  -> local user activity history

notification inbox rows
  -> local notification history

repo/worktree enrichment
  -> rebuildable cache
```
