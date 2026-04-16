# Reserve `⌥IJKL` In Terminal Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reserve `⌥I`, `⌥J`, `⌥K`, and `⌥L` inside embedded terminal panes so those combos are consumed by Agent Studio and never passed through to Ghostty/macOS text input.

**Architecture:** Add a small terminal-host override policy that classifies decoded `ShortcutTrigger`s into three buckets: dispatch an app-owned terminal shortcut, consume a reserved no-op combo, or pass through to normal Ghostty input. Keep this separate from `AppCommand`/`AppShortcut` because reservation is a host input policy, not a user-facing command definition.

**Tech Stack:** Swift 6, AppKit, GhosttyKit, Swift Testing, existing `ShortcutDecoder`

---

## File Map

- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicy.swift`
  - Owns the narrow allowlist for reserved terminal-host combos (`⌥IJKL`) and the classification helper used by `Ghostty.SurfaceView`.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Add `i`, `j`, and `l` to `ShortcutCharacterKey` so `ShortcutDecoder` can represent those combos. Do **not** add new `AppShortcut` or `AppCommand` cases for these reservations.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
  - Replace the ad hoc terminal-app-owned shortcut interception with a policy-driven branch:
    1. dispatch known terminal app-owned shortcuts
    2. consume reserved `⌥IJKL`
    3. fall through to normal Ghostty behavior
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicyTests.swift`
  - Covers policy classification for dispatch / consume / pass-through.
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
  - Add decoding coverage for `⌥I`, `⌥J`, `⌥K`, `⌥L` as `ShortcutTrigger`s without mapping them to `AppShortcut`.
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
  - Keep the existing app-owned-shortcut coverage focused on actual `AppShortcut`s; do not assert reserved no-op combos there.

## Design Constraints

- `⌥IJKL` are **reserved terminal-host overrides**, not command-bar commands.
- They should not appear in `AppShortcut`, `AppCommand`, or command-bar surfaces unless later given explicit meaning.
- `performKeyEquivalent` should consume them **before** they reach Ghostty/macOS text input.
- This is an intentional Agent Studio policy, not Ghostty parity. Add a short code comment at the policy boundary saying so.

## Behavior Diagram

```text
NSEvent
  -> ShortcutDecoder.decode(event)
  -> GhosttyTerminalOverrideKeyPolicy.classify(trigger)

     ┌──────────────────────────────────────────────┐
     │ .dispatch(appShortcut)                      │
     │   -> CommandDispatcher.dispatch(...)        │
     │   -> return true                            │
     └──────────────────────────────────────────────┘

     ┌──────────────────────────────────────────────┐
     │ .consumeReserved                            │
     │   -> return true                            │
     │   -> no Ghostty input, no visible text      │
     └──────────────────────────────────────────────┘

     ┌──────────────────────────────────────────────┐
     │ .passThrough                                │
     │   -> existing Ghostty key handling          │
     └──────────────────────────────────────────────┘
```

## Task 1: Add a Dedicated Reservation Policy

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicy.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicyTests.swift`

- [ ] **Step 1: Write the failing policy tests**

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite
struct GhosttyTerminalOverrideKeyPolicyTests {
    @Test
    func reservedOptionIJKLClassifiesAsConsumeReserved() {
        let reserved: [ShortcutTrigger] = [
            .init(key: .character(.i), modifiers: [.option]),
            .init(key: .character(.j), modifiers: [.option]),
            .init(key: .character(.k), modifiers: [.option]),
            .init(key: .character(.l), modifiers: [.option]),
        ]

        for trigger in reserved {
            #expect(
                GhosttyTerminalOverrideKeyPolicy.classify(trigger) == .consumeReserved,
                "Expected \(trigger) to be consumed by terminal override policy"
            )
        }
    }

    @Test
    func terminalAppOwnedShortcutStillClassifiesAsDispatch() {
        let trigger = AppShortcut.showCommandBarEverything.trigger

        #expect(
            GhosttyTerminalOverrideKeyPolicy.classify(trigger) == .dispatch(.showCommandBarEverything)
        )
    }

    @Test
    func unrelatedOptionLetterPassesThrough() {
        let trigger = ShortcutTrigger(key: .character(.d), modifiers: [.option])

        #expect(GhosttyTerminalOverrideKeyPolicy.classify(trigger) == .passThrough)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'GhosttyTerminalOverrideKeyPolicyTests'
```

Expected:

```text
FAIL because GhosttyTerminalOverrideKeyPolicy does not exist yet
```

- [ ] **Step 3: Implement the minimal policy**

```swift
import Foundation

enum GhosttyTerminalOverrideDecision: Equatable {
    case dispatch(AppShortcut)
    case consumeReserved
    case passThrough
}

enum GhosttyTerminalOverrideKeyPolicy {
    private static let reservedTriggers: Set<ShortcutTrigger> = [
        .init(key: .character(.i), modifiers: [.option]),
        .init(key: .character(.j), modifiers: [.option]),
        .init(key: .character(.k), modifiers: [.option]),
        .init(key: .character(.l), modifiers: [.option]),
    ]

    static func classify(_ trigger: ShortcutTrigger) -> GhosttyTerminalOverrideDecision {
        if let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
           Ghostty.SurfaceView.appOwnedShortcuts.contains(shortcut) {
            return .dispatch(shortcut)
        }

        if reservedTriggers.contains(trigger) {
            // Agent Studio intentionally reserves these terminal host combos.
            return .consumeReserved
        }

        return .passThrough
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'GhosttyTerminalOverrideKeyPolicyTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicy.swift Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicyTests.swift
git commit -m "feat: add terminal option override policy

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 2: Extend Trigger Decoding To Represent `IJKL`

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`

- [ ] **Step 1: Write failing decoder coverage**

```swift
@Test
func shortcutDecoder_decodesReservedOptionIJKLTriggers() {
    let expectations: [(ShortcutCharacterKey, ShortcutTrigger)] = [
        (.i, .init(key: .character(.i), modifiers: [.option])),
        (.j, .init(key: .character(.j), modifiers: [.option])),
        (.k, .init(key: .character(.k), modifiers: [.option])),
        (.l, .init(key: .character(.l), modifiers: [.option])),
    ]

    for (character, expectedTrigger) in expectations {
        let decoded = ShortcutDecoder.decode(
            charactersIgnoringModifiers: character.rawValue,
            keyCode: nil,
            modifierFlags: [.option]
        )
        #expect(decoded == expectedTrigger)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'ShortcutCatalogTests/shortcutDecoder_decodesReservedOptionIJKLTriggers'
```

Expected:

```text
FAIL because .i, .j, and .l are not valid ShortcutCharacterKey cases yet
```

- [ ] **Step 3: Add the character keys only**

```swift
enum ShortcutCharacterKey: String, CaseIterable {
    case a
    case b
    case d
    case e
    case f
    case i
    case j
    case k
    case l
    case m
    // ...
}
```

Do **not** add matching `AppShortcut` cases here.

- [ ] **Step 4: Run the decoder tests**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'ShortcutCatalogTests'
```

Expected:

```text
PASS, including the new reserved-trigger decode coverage
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppShortcut.swift Tests/AgentStudioTests/App/ShortcutCatalogTests.swift
git commit -m "feat: add reserved option trigger decoding

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 3: Consume Reserved `⌥IJKL` In The Terminal Host

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicyTests.swift`

- [ ] **Step 1: Tighten the policy test around execution precedence**

```swift
@Test
func appOwnedShortcutBeatsReservedNoop() {
    let trigger = AppShortcut.showCommandBarEverything.trigger

    #expect(
        GhosttyTerminalOverrideKeyPolicy.classify(trigger) == .dispatch(.showCommandBarEverything)
    )
}
```

- [ ] **Step 2: Run the test to verify current behavior before wiring**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'GhosttyTerminalOverrideKeyPolicyTests'
```

Expected:

```text
PASS
```

- [ ] **Step 3: Refactor `performKeyEquivalent` to use the policy**

Replace the top branch with:

```swift
        if let trigger = ShortcutDecoder.decode(event: event) {
            switch GhosttyTerminalOverrideKeyPolicy.classify(trigger) {
            case .dispatch(let shortcut):
                if CommandDispatcher.shared.canDispatch(shortcut.command) {
                    CommandDispatcher.shared.dispatch(shortcut.command)
                    return true
                }
                return false

            case .consumeReserved:
                return true

            case .passThrough:
                break
            }
        }
```

This keeps existing `CommandDispatcher` behavior for real terminal app-owned shortcuts while swallowing reserved `⌥IJKL` as no-ops.

- [ ] **Step 4: Remove stale reserved-shortcut expectations from `GhosttySurfaceShortcutTests`**

Keep this suite focused on actual `AppShortcut` membership only. If it currently refers to reserved no-op combos, delete those assertions.

- [ ] **Step 5: Run focused terminal shortcut tests**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'GhosttyTerminalOverrideKeyPolicyTests|GhosttySurfaceShortcutTests|ShortcutCatalogTests'
```

Expected:

```text
PASS
```

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyTerminalOverrideKeyPolicyTests.swift Tests/AgentStudioTests/App/ShortcutCatalogTests.swift
git commit -m "feat: reserve option ijkl in terminal host

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 4: Verify No Command Surfaces Regress

**Files:**
- Modify: none expected
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarShortcutRouterTests.swift`

- [ ] **Step 1: Run command and command-bar focused suites**

Run:

```bash
swift test --build-path .build-agent-reserve-option-ijkl --filter 'AppCommandTests|CommandBarDataSourceTests|CommandBarShortcutRouterTests'
```

Expected:

```text
PASS with no new command or command-bar rows for reserved ⌥IJKL
```

- [ ] **Step 2: Run lint**

Run:

```bash
mise run lint
```

Expected:

```text
PASS
```

- [ ] **Step 3: Run the full test suite**

Run:

```bash
AGENT_RUN_ID=reserve-option-ijkl mise run test
```

Expected:

```text
PASS
```

- [ ] **Step 4: Build debug and release**

Run:

```bash
AGENT_RUN_ID=reserve-option-ijkl mise run build
AGENT_RUN_ID=reserve-option-ijkl mise run build-release
```

Expected:

```text
PASS for both builds
```

- [ ] **Step 5: Manual verification**

Run the debug or release app and verify inside a focused terminal pane:

1. Press `⌥I`, `⌥J`, `⌥K`, `⌥L`
2. Confirm:
   - no visible dotted/dead-key characters appear
   - no terminal input is sent
   - no command bar opens
   - no unintended app action fires
3. Press an unrelated `⌥` combo such as `⌥D`
4. Confirm it still follows the existing input path

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test: verify reserved option terminal overrides

Co-authored-by: Codex <noreply@openai.com>"
```

## Notes For The Implementer

- Do not thread this through `AppCommand` unless the product later assigns real meaning to one of the reserved combos.
- Do not add these reservations to command-bar data sources.
- Do not broaden the allowlist beyond `⌥IJKL` in this changeset.
- Keep the reservation comment local to the terminal policy file, not spread across the command system.

