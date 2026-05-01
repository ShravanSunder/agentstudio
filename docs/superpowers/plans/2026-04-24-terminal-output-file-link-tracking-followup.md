# Terminal Output File-Link Tracking Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a later-stage pipeline that extracts file links and richer terminal output semantics from Claude/Codex terminal sessions without overloading the notification inbox.

**Architecture:** Keep terminal runtime facts on `PaneRuntimeEventBus`, then add a dedicated parser/projection layer for semantic output artifacts. The parser should emit typed facts such as file links, diagnostics, and structured agent updates; inbox notifications should remain a separate promotion layer with explicit gates.

**Tech Stack:** Swift 6.2, Swift Testing, existing `PaneRuntimeEventBus`, `@MainActor @Observable` atoms, Ghostty terminal integration, existing filesystem/git projection.

---

## Scope Boundaries

This follow-up does not run in the current PR. The current PR tracks activity facts already exposed by Ghostty events: progress, CWD, URL requests, secure input, and scrollbar-derived output bursts.

This follow-up owns richer semantic extraction from terminal output, including printed file paths from Claude/Codex, diagnostics, and structured agent status updates. Do not fake this by treating scrollbar growth as output content; scrollbar growth only proves more rows exist.

## Missing Systems

1. Raw terminal output content is not currently carried on `PaneRuntimeEventBus`.
2. Ghostty `scrollbarChanged` gives row totals, not text.
3. `openURLRequested` tracks URLs Ghostty asks the host to open, not every URL printed by an agent.
4. Printed file paths need a parser source: structured agent RPC, terminal text extraction, or a Ghostty semantic-link event if one exists.
5. Security/approval product emitters remain separate systems and should not be invented here.

## Proposed Event Model

```swift
enum TerminalSemanticArtifact: Sendable, Equatable {
    case fileReference(TerminalFileReference)
    case urlReference(TerminalURLReference)
    case agentStatus(TerminalAgentStatus)
    case diagnostic(TerminalDiagnostic)
}

struct TerminalFileReference: Sendable, Equatable {
    let path: String
    let line: Int?
    let column: Int?
    let sourceText: String
}
```

## Task A: Research Extractable Sources

**Files:**
- Modify: `docs/wip/luna361-terminal-semantic-output-research-2026-04-24.md`

- [ ] **Step 1: Audit Ghostty source for semantic link or screen-text APIs**

Run:

```bash
rg -n "link|hyperlink|screen|selection|text|copy|osc8|OSC 8|semantic" vendor/ghostty/src vendor/ghostty/include vendor/ghostty/macos
```

Expected: concrete notes showing whether Ghostty exposes printed links/text to the host.

- [ ] **Step 2: Audit Agent Studio bridge/RPC surfaces**

Run:

```bash
rg -n "inbox.post|agentNotification|Bridge|JSON-RPC|RPC|post" Sources/AgentStudio/Features/Bridge Sources/AgentStudio/Core/RuntimeEventSystem
```

Expected: concrete notes showing whether Claude/Codex can post structured file references without terminal scraping.

- [ ] **Step 3: Commit research**

```bash
git add docs/wip/luna361-terminal-semantic-output-research-2026-04-24.md
git commit -m "docs(terminal): research semantic output tracking sources

Co-authored-by: Codex <noreply@openai.com>"
```

## Task B: Add Typed Semantic Artifact Contract

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/TerminalSemanticArtifactTests.swift`

- [ ] **Step 1: Write failing tests for file-reference identity**

Add tests proving file references preserve path, optional line/column, and source text without forcing an inbox notification.

- [ ] **Step 2: Add contract types**

Add typed `TerminalSemanticArtifact` payloads only after Task A confirms the source.

- [ ] **Step 3: Run focused tests**

```bash
swift test --build-path ".build-agent-$PPID" --filter "TerminalSemanticArtifactTests"
```

Expected: pass.

## Task C: Add Projection And UI Surface

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/State/MainActor/Atoms/TerminalSemanticArtifactAtom.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/State/TerminalSemanticArtifactAtomTests.swift`

- [ ] **Step 1: Write failing projection tests**

Test bounded retention per pane and stable de-dupe for repeated file references.

- [ ] **Step 2: Implement projection atom**

The atom owns recent semantic artifacts per pane. It does not own notification routing.

- [ ] **Step 3: Run focused tests**

```bash
swift test --build-path ".build-agent-$PPID" --filter "TerminalSemanticArtifactAtomTests"
```

Expected: pass.

## Self-Review

Spec coverage:
- Later file-link tracking is scoped here.
- Security/approval emitters are explicitly out of scope.
- Current PR activity facts stay out of this follow-up.

Placeholder scan:
- No implementation placeholders are allowed before execution; Task A must produce source-specific findings before Task B starts.

Type consistency:
- Semantic artifacts are typed facts, not inbox notification payloads.
