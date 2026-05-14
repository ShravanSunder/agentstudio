# Settings Window Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Settings window entirely, delete stale Zellij-era and dead-settings cruft, and hard-code hidden restore behavior to `existingSessionsOnly` without introducing a replacement app preferences boundary.

**Architecture:** This is a hard-cutover cleanup. Delete the ad hoc settings surface and all dead `@AppStorage` settings concepts instead of migrating them. Keep real mutable state in existing owning atoms/stores, and treat hidden restore behavior as fixed product policy rather than user preference. Simplify runtime/config code to stop reading `backgroundRestorePolicy` from `UserDefaults`.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Testing, SwiftPM via `mise`

---

## File Map

### Remove

- `Sources/AgentStudio/App/Windows/SettingsView.swift`

### Modify

- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Sources/AgentStudio/Core/Models/SessionConfiguration.swift`
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift`
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- `Tests/AgentStudioTests/Core/Models/SessionConfigurationTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreTypesTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreRuntimeTests.swift`
- `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`

### Review for collateral references

- `docs/superpowers/specs/2026-05-02-settings-window-removal-design.md`
- `docs/architecture/component_architecture.md`
- `docs/architecture/workspace_data_architecture.md`

---

### Task 1: Remove the Settings window entry points

**Files:**
- Delete: `Sources/AgentStudio/App/Windows/SettingsView.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Test: targeted build + grep verification

- [ ] **Step 1: Write the failing test expectation as a grep check**

Run:

```bash
rg -n "SettingsView|openSettings\\(|Settings\\.\\.\\." Sources/AgentStudio/App
```

Expected: hits in `AppDelegate.swift` and `SettingsView.swift`.

- [ ] **Step 2: Remove the menu item and `openSettings()` path**

Edit `Sources/AgentStudio/App/Boot/AppDelegate.swift`:

- remove the `Settings...` app-menu item
- remove `@objc private func openSettings()`
- remove any now-unused `SettingsView` creation path

Keep the rest of the app menu structure intact.

- [ ] **Step 3: Delete the Settings view file**

Delete:

```text
Sources/AgentStudio/App/Windows/SettingsView.swift
```

- [ ] **Step 4: Run grep to verify the shell is gone**

Run:

```bash
rg -n "SettingsView|openSettings\\(|Settings\\.\\.\\." Sources/AgentStudio/App Sources/AgentStudio/App/Windows
```

Expected: no hits.

---

### Task 2: Remove dead settings concepts and stale Zellij affordances

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- Test: grep verification

- [ ] **Step 1: Write the failing verification check**

Run:

```bash
rg -n "openZellijConfig|Zellij|zellij|terminalFontSize|autoRefreshWorktrees|detachOnClose" Sources/AgentStudio
```

Expected: hits in `SettingsView.swift`, `UIActionPresentation.swift`, and any remaining settings-related code.

- [ ] **Step 2: Remove stale local action specs**

Edit `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`:

- remove `case openZellijConfig`
- remove its `ActionSpec` branch

Do not remove unrelated browser favorites/history actions, since those still belong to Webview feature UI.

- [ ] **Step 3: Re-run grep to verify the dead settings vocabulary is gone**

Run:

```bash
rg -n "openZellijConfig|Zellij|zellij|terminalFontSize|autoRefreshWorktrees|detachOnClose" Sources/AgentStudio
```

Expected: no hits.

---

### Task 3: Hard-code hidden restore behavior to `existingSessionsOnly`

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/SessionConfiguration.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Test: `Tests/AgentStudioTests/Core/Models/SessionConfigurationTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreTypesTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreRuntimeTests.swift`

- [ ] **Step 1: Lock current behavior with focused tests**

Keep or add tests that prove:

- `SessionConfiguration.detect(...).backgroundRestorePolicy == .existingSessionsOnly`
- hidden restore still depends on whether a live session exists

Do not add tests for `.off` or `.allTerminalPanes` as supported product modes.

- [ ] **Step 2: Remove `UserDefaults`-based policy resolution**

Edit `Sources/AgentStudio/Core/Models/SessionConfiguration.swift`:

- remove `resolveBackgroundRestorePolicy(...)`
- have `detect(...)` use `.existingSessionsOnly` directly

Target shape:

```swift
let backgroundRestorePolicy = BackgroundRestorePolicy.existingSessionsOnly
```

- [ ] **Step 3: Simplify restore gating around the one supported policy**

Edit:

- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift`
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`

Goal:

- remove branches that only exist to support user-selectable `.off`
- remove branches that only exist to support `.allTerminalPanes`
- preserve the actual current supported behavior:
  hidden panes restore only when a live session exists

If the enum itself no longer earns its existence after simplification, remove it and replace its call sites with the direct policy logic. If keeping the enum yields a smaller, clearer change set, keep only the supported case and simplify around it.

- [ ] **Step 4: Run the focused restore tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SessionConfigurationTests|TerminalRestoreTypesTests|TerminalRestoreRuntimeTests" 
```

Expected: PASS.

---

### Task 4: Remove deprecated policy variants from integration coverage

**Files:**
- Modify: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`
- Test: targeted filtered run

- [ ] **Step 1: Find test cases that still model removed product modes**

Run:

```bash
rg -n "backgroundRestorePolicy: \\.allTerminalPanes|backgroundRestorePolicy: \\.off" Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift
```

Expected: hits for deprecated modes.

- [ ] **Step 2: Rewrite or remove deprecated-mode tests**

Edit `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`:

- remove scenarios that only validate user-selectable `.off`
- remove scenarios that only validate user-selectable `.allTerminalPanes`
- keep scenarios that validate supported restore behavior under the fixed policy

- [ ] **Step 3: Run the targeted integration suite**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "Luna295DirectZmxAttachIntegrationTests"
```

Expected: PASS.

---

### Task 5: Verify the hard-cutover and run project checks

**Files:**
- Review only: docs for drift if implementation changes public wording

- [ ] **Step 1: Verify no dead settings surface remains**

Run:

```bash
rg -n "SettingsView|openSettings\\(|Settings\\.\\.\\.|openZellijConfig|terminalFontSize|autoRefreshWorktrees|detachOnClose|backgroundRestorePolicy\"|Zellij|zellij" Sources/AgentStudio
```

Expected:

- no Settings window hits
- no dead settings key hits
- no stale Zellij wording
- no `backgroundRestorePolicy` `UserDefaults` key lookup

- [ ] **Step 2: Run formatting/linting**

Run:

```bash
mise run lint
```

Expected: PASS with exit code 0.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
mise run test
```

Expected: PASS with exit code 0.

- [ ] **Step 4: Review docs drift**

If implementation removes supported policy variants or changes any user-facing product wording, update any directly incorrect architecture/spec references in:

- `docs/architecture/component_architecture.md`
- `docs/architecture/workspace_data_architecture.md`

Keep this scoped to clearly wrong statements introduced by the cleanup. Do not do a broad doc rewrite.

---

## Self-Review

### Spec coverage

Covered:

- delete Settings window entirely
- delete direct AppDelegate menu/window path
- remove stale Zellij-era UI and wording
- remove dead `@AppStorage` concepts
- hard-code restore behavior to `existingSessionsOnly`
- avoid introducing `AppPreferenceAtom`

### Placeholder scan

No `TODO` / `TBD` placeholders included. All tasks point at exact files and concrete verification commands.

### Type consistency

The plan consistently treats `backgroundRestorePolicy` as a fixed product behavior rather than a surviving mutable preference. If the implementation keeps `BackgroundRestorePolicy` as a type, it should keep only the supported semantics. If it removes the enum entirely, the tests and runtime call sites should be simplified in the same changeset.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-02-settings-window-removal.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
