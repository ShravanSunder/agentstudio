# LUNA-325 Contract Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close all `LUNA-325` owned gaps (Contracts 1,2,3,4,7,7a,8,10,11,12,14 + migration invariant) with deterministic tests, explicit scope boundaries, and synchronized docs/ticket state.

**Architecture:** Implement the canonical View / Controller / Runtime / Adapter layering (D5) for the terminal pane type (`GhosttyAdapter → TerminalRuntime → PaneCoordinator`) while removing migrated legacy dispatch paths atomically. Keep ownership boundaries strict: do not absorb `LUNA-295` (`5a`, `12a`), `LUNA-324` (`5b`), or deferred `LUNA-344` contracts (`13`, `15`, `16`). Drive all changes through contract-first tests and small, reversible batches.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), AsyncStream/event-stream plumbing, GhosttyKit C API bridge, mise task runner, SwiftLint/swift-format.

---

## Execution Ledger

- [x] Task 1: Stabilize Test Entrypoints (`mise run test` excludes E2E by default)
- [x] Task 2: Update Mapping Doc with Missing-Things Ledger + Scope Corrections
- [x] Task 3: Add Failing Contract Tests for GhosttyAdapter + TerminalRuntime Metadata
- [x] Task 4: Expand `GhosttyEvent`/`GhosttyAdapter` Coverage for Existing Action Tags
- [x] Task 5: Extend `TerminalRuntime` Event Handling + Envelope Metadata Guarantees
- [x] Task 6: Rename Runtime Command Vocabulary (`PaneCommand` → `RuntimeCommand`)
- [x] Task 7: Harden `RuntimeRegistry` Uniqueness Invariant
- [x] Task 8: Implement Tier-Aware `NotificationReducer` Scheduling + Tests
- [x] Task 9: Migrate Ghostty Action Dispatch Off Legacy Notification Posts (Atomic per Action Family)
- [x] Task 10: Final Verification, Docs, and Linear Sync

## Post-Merge Audit Tasks (PR #43 -> LUNA-325 Branch)

- [x] Replace merge-introduced non-v7 pane IDs in runtime-invariant tests.
  - Updated `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift` duplicate-pane path + pane-id helpers.
  - Updated `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift` duplicate-pane path + pane-id helpers.
- [ ] Keep scanning merge-touched tests for `PaneId(uuid:)` call sites fed by plain `UUID()` and convert pane identity inputs to `UUIDv7.generate()` where needed.
- [ ] Resolve merge-introduced lint regression in `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` (`file_length`, `type_body_length`) with an extraction refactor that preserves behavior.
- [ ] Validate all merge-touch gates in one pass after cleanup:
  - `mise run test`
  - `mise run lint`
  - `mise run build`
- [ ] Record UI-scope NotificationCenter posts introduced by merge as explicit EventBus migration backlog (LUNA-351), ensuring runtime data-plane remains typed-stream only.

---

### Task 1: Stabilize Test Entrypoints

**Files:**
- Modify: `.mise.toml`

**Step 1: Write the failing test**

Add a shell-level expectation in this plan’s execution notes: `mise run test` must skip E2E by default and expose a separate command for E2E.

**Step 2: Run test to verify it fails**

Run: `rg -n "SWIFT_TEST_INCLUDE_E2E:-1|\\[tasks\\.test-e2e\\]" .mise.toml`  
Expected: shows default include as `1` and no dedicated `test-e2e` task.

**Step 3: Write minimal implementation**

Update `.mise.toml`:

```toml
# default E2E off in tasks.test
if [ "${SWIFT_TEST_INCLUDE_E2E:-0}" = "1" ]; then
  AGENT_STUDIO_BENCHMARK_MODE=off swift test --filter E2ESerializedTests --build-path "$BUILD_PATH"
else
  echo "[test] skipping E2ESerializedTests (SWIFT_TEST_INCLUDE_E2E=${SWIFT_TEST_INCLUDE_E2E:-0})"
fi

[tasks.test-e2e]
description = "Run E2E serialized tests only (opt-in; may stall in current zmx state)"
depends = ["build"]
run = """
#!/usr/bin/env bash
set -euo pipefail
BUILD_PATH="${SWIFT_BUILD_DIR:-.build}"
AGENT_STUDIO_BENCHMARK_MODE=off swift test --filter E2ESerializedTests --build-path "$BUILD_PATH"
"""
```

**Step 4: Run test to verify it passes**

Run: `rg -n "SWIFT_TEST_INCLUDE_E2E:-0|\\[tasks\\.test-e2e\\]" .mise.toml`  
Expected: both patterns found.

**Step 5: Commit**

```bash
git add .mise.toml
git commit -m "build: split E2E tests from default mise test path"
```

---

### Task 2: Mapping Doc Missing-Things Ledger

**Files:**
- Modify: `docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`

**Step 1: Write the failing test**

Define a missing-things ledger section with explicit task IDs and scope boundary notes.

**Step 2: Run test to verify it fails**

Run: `rg -n "Missing Things Task Ledger|Current Snapshot \\(2026-02-22\\)" docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`  
Expected: no matches before edit.

**Step 3: Write minimal implementation**

Add:
- Current snapshot section with known drifts.
- Missing-things task ledger checkboxes.
- Correct stale checklist item for `Core/PaneRuntime/` directories.

**Step 4: Run test to verify it passes**

Run: `rg -n "Missing Things Task Ledger|Current Snapshot \\(2026-02-22\\)|Core/PaneRuntime/" docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`  
Expected: all sections present.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md
git commit -m "docs: add LUNA-325 missing-things ledger and snapshot corrections"
```

---

### Task 3: Add Failing Contract Tests (Ghostty + Runtime Metadata)

**Files:**
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import AgentStudio

@Suite("GhosttyAdapter")
struct GhosttyAdapterTests {
    @Test("known action tags map to typed events")
    func knownTagMappings() {
        let adapter = GhosttyAdapter.shared
        #expect(adapter.translate(actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue)) == .newTab)
    }
}
```

```swift
@Test("handleGhosttyEvent title/cwd updates metadata and preserves envelope ids")
func ghosttyEventMetadataAndEnvelope() async {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
    )
    runtime.transitionToReady()

    let commandId = UUID()
    let correlationId = UUID()
    runtime.handleGhosttyEvent(.titleChanged("Updated"), commandId: commandId, correlationId: correlationId)
    runtime.handleGhosttyEvent(.cwdChanged("/tmp"), commandId: commandId, correlationId: correlationId)

    #expect(runtime.metadata.title == "Updated")
    #expect(runtime.metadata.cwd == URL(fileURLWithPath: "/tmp"))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL because mappings/cases are missing.

**Step 3: Write minimal implementation**

Implement just enough `GhosttyEvent` cases + `GhosttyAdapter.translate` mappings to satisfy the new tests.

**Step 4: Run test to verify it passes**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

Run: `swift test --filter TerminalRuntimeTests/ghosttyEventMetadataAndEnvelope --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift
git commit -m "test: enforce initial ghostty adapter/runtime metadata contract coverage"
```

---

### Task 4: Expand Existing Action Coverage

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`

**Step 1: Write the failing test**

Add expectations for currently handled actions in `Ghostty.swift`: `newTab`, `newSplit`, `gotoSplit`, `resizeSplit`, `equalizeSplits`, `toggleSplitZoom`, `closeTab`, `gotoTab`, `moveTab`.

**Step 2: Run test to verify it fails**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL on unimplemented enum cases/mappings.

**Step 3: Write minimal implementation**

Add enum cases and translate mapping for those action tags; keep unknown tags as `.unhandled`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift
git commit -m "feat: expand ghostty adapter coverage for currently handled action families"
```

---

### Task 5: TerminalRuntime Contract Hardening

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

**Step 1: Write the failing test**

Add tests for unsupported runtime command families and command/correlation envelope propagation.

**Step 2: Run test to verify it fails**

Run: `swift test --filter TerminalRuntimeTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL on unsupported-command and envelope assertions.

**Step 3: Write minimal implementation**

Harden command handling and event emission to satisfy contract checks.

**Step 4: Run test to verify it passes**

Run: `swift test --filter TerminalRuntimeTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift
git commit -m "feat: harden terminal runtime command and envelope behavior"
```

---

### Task 6: Runtime Command Vocabulary Alignment

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeCommand.swift` (renamed from `PaneCommand.swift`)
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntime.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+RuntimeDispatch.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/PaneRuntimeContractsTests.swift`

**Step 1: Write the failing test**

Assert `RuntimeCommand` naming exists and remains distinct from workspace `PaneAction`.

**Step 2: Run test to verify it fails**

Run: `swift test --filter PaneRuntimeContractsTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL until vocabulary/typealiases are aligned.

**Step 3: Write minimal implementation**

Introduce `RuntimeCommandEnvelope`/`RuntimeCommand` naming (compat typealias allowed for incremental safety).

**Step 4: Run test to verify it passes**

Run: `swift test --filter PaneRuntimeContractsTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeCommand.swift Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntime.swift Sources/AgentStudio/App/PaneCoordinator+RuntimeDispatch.swift Tests/AgentStudioTests/Core/PaneRuntime/Contracts/PaneRuntimeContractsTests.swift
git commit -m "refactor: align runtime command vocabulary with architecture contract"
```

---

### Task 7: RuntimeRegistry Uniqueness Invariant

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Registry/RuntimeRegistry.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift`

**Step 1: Write the failing test**

Expect duplicate registration to be rejected (no replacement).

**Step 2: Run test to verify it fails**

Run: `swift test --filter RuntimeRegistryTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL because current behavior replaces existing runtime.

**Step 3: Write minimal implementation**

Enforce uniqueness with non-replacing registration path (and debug precondition guard if needed).

**Step 4: Run test to verify it passes**

Run: `swift test --filter RuntimeRegistryTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Registry/RuntimeRegistry.swift Tests/AgentStudioTests/Core/PaneRuntime/Registry/RuntimeRegistryTests.swift
git commit -m "fix: enforce runtime registry uniqueness invariant"
```

---

### Task 8: NotificationReducer Tier Scheduling

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift`

**Step 1: Write the failing test**

Add a fake tier resolver and assert p0/p1/p2/p3 ordering in batched emissions.

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationReducerTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL (tier ordering not enforced as expected).

**Step 3: Write minimal implementation**

Implement tier-aware ordering behavior in reducer batching path (without touching LUNA-295 ownership beyond reducer mechanics).

**Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationReducerTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift
git commit -m "feat: enforce notification reducer tier ordering with tests"
```

---

### Task 9: Migration Invariant (Atomic Action-Family Migration)

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift` and/or runtime dispatch extensions (as needed)
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`

**Step 1: Write the failing test**

Add adapter/runtime dispatch tests for one migrated action family (tab/split or metadata) and assert no legacy post path remains for that migrated family.

**Step 2: Run test to verify it fails**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: FAIL until migrated family is routed on typed path only.

**Step 3: Write minimal implementation**

Migrate one action family atomically:
- add typed route,
- remove corresponding NotificationCenter post(s),
- keep unmigrated families untouched.

**Step 4: Run test to verify it passes**

Run: `swift test --filter GhosttyAdapterTests --build-path "${SWIFT_BUILD_DIR:-.build}"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift Sources/AgentStudio/App/PaneCoordinator.swift Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift
git commit -m "refactor: migrate ghostty action family to typed runtime path without dual dispatch"
```

---

### Task 10: Verification + Docs + Linear Sync

**Files:**
- Modify: `docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`
- Modify: `docs/plans/2026-02-22-luna-325-contract-parity-execution-plan.md`

**Step 1: Write the failing test**

Define done criteria:
- LUNA-325 checklist statuses updated.
- verification evidence captured.
- Linear issue comment updated with what shipped and what remains.

**Step 2: Run test to verify it fails**

Run:
- `swift build --build-path "${SWIFT_BUILD_DIR:-.build}"`
- `swift test --build-path "${SWIFT_BUILD_DIR:-.build}"`
- `mise run lint`

Expected: identify any remaining failures before closure.

**Step 3: Write minimal implementation**

Fix remaining failures, update docs checkboxes, and post Linear progress note.

**Step 4: Run test to verify it passes**

Re-run the same three commands; expect zero failures.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md docs/plans/2026-02-22-luna-325-contract-parity-execution-plan.md
git commit -m "docs: close LUNA-325 parity execution ledger with verification evidence"
```
