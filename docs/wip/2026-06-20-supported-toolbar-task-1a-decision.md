# Supported Toolbar Task 1A Decision

Date: 2026-06-20
Goal: `2026-06-20-thin-titlebar-two-row`

## Decision

Do not adopt the supported native `NSToolbar` path for this change. Continue
with titlebar accessory controls and keep `window.toolbar == nil`.

## Evidence

The supported API exists in the active SDK:

```text
NSToolbar.allowsDisplayModeCustomization API_AVAILABLE(macos(15.0), ios(18.0))
```

The SDK header documents this as the control for whether the toolbar display
mode is user-modifiable. Package configuration targets macOS 26, so the API is
available to the app.

## Rejection Basis

Using this API still requires product actions to live in a real `NSToolbar`.
That conflicts with the accepted goal scope:

- default custom path: `window.toolbar == nil`
- no product `NSToolbarDelegate` action path
- no native toolbar right-click display surface for product controls
- row 1 actions are titlebar accessories, not toolbar items

The supported API can reduce one native toolbar customization behavior, but it
does not satisfy the accepted architecture boundary because the product actions
would still be toolbar items. Adopting it would change the goal back to native
toolbar chrome and would require user reconvergence before implementation.

## Proof Now In Repo

- `MainWindowControllerInboxToolbarButtonTests.mainWindowDoesNotInstallProductToolbar`
  asserts `window.toolbar == nil`.
- `WelcomeLauncherArchitectureTests.mainWindowDoesNotRestoreProductToolbarActions`
  guards against restoring `setupToolbar`, `NSToolbar(identifier:)`,
  `commandToolbarButtonItem(for: .watchFolder, ...)`, or
  `NSToolbarDelegate`.
- The runtime proof in
  `tmp/visual-proof/2026-06-20-thin-titlebar-two-row/pid-72062-titlebar.json`
  shows the four titlebar controls as accessibility elements:
  `worktreeToolbarButton`, `inboxToolbarBell`,
  `managementLayerTitlebarButton`, and `watchFolderTitlebarButton`.

## Remaining Native Proof Note

Peekaboo secondary-click probing hung in this run and was interrupted with exit
130. The right-click display-menu requirement is therefore proven by removing
the native toolbar owner (`window.toolbar == nil`) rather than by a captured
secondary-click menu screenshot.
