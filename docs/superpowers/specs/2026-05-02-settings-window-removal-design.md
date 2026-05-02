# Settings Window Removal Design

**Date:** 2026-05-02

## Goal

Remove the Settings window entirely, delete stale settings/UI cruft, and keep only behavior that still materially belongs in the product. Do not replace the Settings window with a smaller preferences shell. Do not introduce a new global preference atom/store for behavior that is no longer user-configurable.

## Decision Summary

1. The Settings window is removed completely.
2. The app no longer has a direct `openSettings()` path or a Settings menu item.
3. The stale Zellij-era UI and terminology are removed.
4. Dead settings state is removed rather than migrated.
5. Hidden-pane restore behavior is hard-coded to `BackgroundRestorePolicy.existingSessionsOnly`.
6. No `AppPreferenceAtom` is introduced as part of this cleanup.

## Why

The current Settings window is not an honest representation of the product. Most controls either have no meaningful runtime reader or duplicate capability-local UI that already lives in the owning feature.

The one setting that still changes real behavior is `backgroundRestorePolicy`, but the agreed product decision is to stop exposing that as a user preference and to standardize on the current default behavior instead. Once that choice is made, a dedicated app-level preferences boundary for this cleanup does not earn its cost.

## Current State

### Settings window

`Sources/AgentStudio/App/Windows/SettingsView.swift` currently exposes:

- `terminalFontSize`
- `autoRefreshWorktrees`
- `detachOnClose`
- `backgroundRestorePolicy`
- webview favorites/history management
- a Zellij config section

### Menu/window wiring

`AppDelegate` currently adds `Settings...` directly to the app menu and opens a fresh `NSWindow` via `openSettings()`.

### Preference architecture reality

The repo already has real atom/store boundaries for:

- workspace UI state via `UIStateAtom` + `UIStateStore`
- inbox feature prefs via `InboxNotificationPrefsAtom` + `InboxNotificationStore`

But the Settings window still uses stray `@AppStorage` keys and legacy `UserDefaults` patterns instead of living on one of those boundaries.

## What Gets Removed

### Entire Settings surface

Remove:

- `Sources/AgentStudio/App/Windows/SettingsView.swift`
- the app menu `Settings...` item
- `AppDelegate.openSettings()`

There is no replacement Settings window.

### Dead or misleading controls

Remove the user-facing concept and storage plumbing for:

- `terminalFontSize`
- `autoRefreshWorktrees`
- `detachOnClose`
- webview settings management inside Settings
- Zellij config affordances and wording

These are removed, not migrated.

### Zellij-specific references

Remove user-facing or settings-related references to Zellij, including labels, actions, help text, and dead configuration affordances that no longer match the zmx-backed runtime architecture.

This cleanup does **not** remove zmx or session persistence. It removes stale Zellij naming and dead settings/UI around it.

## What Stays

### Product behavior

The app keeps hidden-pane restore behavior, but it is no longer user-configurable.

The product policy becomes:

- hidden zmx-backed panes restore with `BackgroundRestorePolicy.existingSessionsOnly`

This means:

- visible panes continue to restore as before
- hidden panes restore only when a live zmx session already exists
- the app no longer exposes alternate user-selectable restore modes

### Capability-local state in owning surfaces

These stay where they already belong:

- webview favorites/history in Webview feature UX
- inbox grouping/sort/bell prefs in the Inbox feature atom/store
- workspace UI shell state in `UIStateAtom`

None of these should be pulled into a replacement Settings shell.

## Architecture Direction

### No `AppPreferenceAtom` in this cleanup

Do not create an `AppPreferenceAtom` or `PreferencesStore` just to hold a now-hard-coded restore policy.

That would create a new abstraction with no meaningful mutable domain behind it.

If the product later grows a real set of global user-configurable app preferences, a dedicated app-level atom/store can be introduced then. That is a separate design problem.

### Simplify restore configuration flow

`SessionConfiguration` should stop resolving `backgroundRestorePolicy` from `UserDefaults` and instead use the product policy directly.

If the broader enum and alternate modes are only present to support removed user configuration, the implementation should simplify around the one remaining supported behavior.

## Command and Menu Model

The Settings window should not survive as a hidden shell-only escape hatch.

After this cleanup:

- there is no Settings command
- there is no Settings shortcut
- there is no Settings entry in command bar

If future product decisions introduce real app-level preferences again, they must enter through the existing command architecture (`AppCommand` / `CommandSpec` / command bar) rather than through ad hoc AppDelegate menu wiring.

## Non-Goals

- introducing a replacement mini Settings window
- introducing `AppPreferenceAtom`
- building `PreferencesStore`
- redesigning Webview favorites/history UX
- redesigning Inbox preferences UX
- removing zmx session persistence

## Implementation Notes

### Persistence posture

This cleanup follows the repo's hard-cutover preference:

- remove the obsolete settings UI
- stop reading the obsolete settings keys
- do not dual-write or preserve compatibility shims

Legacy `UserDefaults` values for removed settings are treated as dead state.

### Tests to adjust

Tests that currently exercise `.off` and `.allTerminalPanes` as user-selectable policy behavior will need to be updated to the new product boundary:

- keep tests that validate the supported restore behavior
- remove or rewrite tests that only exist to prove deprecated user-configurable modes

## End State

After this cleanup:

- the app has no Settings window
- the app has no stale Zellij settings/UI surface
- dead settings keys are no longer part of the product model
- hidden restore uses one consistent product policy
- real mutable preference/state domains continue to live in owning atoms/stores instead of one-off `@AppStorage` islands
