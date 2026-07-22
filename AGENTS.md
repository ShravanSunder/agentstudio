# Agent Studio - Project Context

## What This Is
macOS terminal application embedding Ghostty terminal emulator with project/worktree management.

## Build & Test

Build orchestration uses [mise](https://mise.jdx.dev/). Install with `brew install mise`.

```bash
mise run setup                # Init submodules, build vendored artifacts, copy resources
mise run build                # Build the Swift app
mise run test                 # Run tests (Swift 6 `Testing`)
mise run format               # Auto-format all Swift sources
mise run lint                 # Lint (swift-format + SwiftLint + AgentStudio architecture lint)
.build/debug/AgentStudio      # Launch debug build
```

First-time setup: `mise install && mise run doctor-mac && mise run setup && mise run build`. See [Agent Resources](docs/guides/agent_resources.md) for full bootstrap.

> **Time-based note (2026-04): Xcode 26.4+ breaks vendored zig 0.15.2 builds.** Apple's Xcode 26.4 `MacOSX.sdk/usr/lib/libSystem.B.tbd` drops `arm64-macos` from top-level targets → zig 0.15.2's linker fails with `undefined symbol: _abort`, `_getenv`, etc. on Apple Silicon when building ghostty/zmx. Xcode 26.5 beta is also affected. Fixed in zig 0.16 (which ghostty hasn't adopted). Workaround: install **Xcode 26.3** side-by-side, `sudo xcode-select --switch /Applications/Xcode_26.3.app/Contents/Developer`, `xcodebuild -downloadComponent MetalToolchain`, `rm -rf ~/.cache/zig`. If `mise run setup` surfaces `undefined symbol: _abort` or similar libSystem errors, this is the cause. Refs: [ghostty#11991](https://github.com/ghostty-org/ghostty/issues/11991), [zig#31658](https://codeberg.org/ziglang/zig/issues/31658). Delete this note once ghostty bumps to zig 0.16 or Apple fixes the SDK.

Testing: Swift 6 `Testing` only — `@Suite`, `@Test`, `#expect`. No XCTest. A PostToolUse hook (`.claude/hooks/check.sh`) runs swift-format and SwiftLint automatically after every Edit/Write on `.swift` files.

## Progressive Disclosure For Agents

Use repo knowledge in layers. Start from the smallest source of truth that owns
the question, then inspect current code/tests before making claims.

1. Orientation: this file is the repo operating contract. Use
   [Agent Resources](docs/guides/agent_resources.md) for bootstrap and research
   sources, and [Architecture Overview](docs/architecture/README.md) for the
   architecture index.
2. Architecture: open the one architecture doc for the concern before broad
   searching. Examples: [Directory Structure](docs/architecture/directory_structure.md)
   for placement, [Commands and Shortcuts](docs/architecture/commands_and_shortcuts.md)
   for command routing, [Observability And Traceability](docs/architecture/observability_and_traceability.md)
   for trace/proof rules, and [AgentStudio IPC Architecture](docs/architecture/agentstudio_ipc_architecture.md)
   for programmatic-control boundaries. For UI shell, toolbar, tooltip, window,
   or native macOS affordance changes, also read
   [Style Guide](docs/guides/style_guide.md) and
   [App Architecture](docs/architecture/appkit_swiftui_architecture.md).
3. Testing: climb the proof pyramid. Start with focused Swift tests for the
   changed code, then `mise run lint`; use `mise run test` for broad repo
   health when the scope calls for it. Do not call unit tests, mocks, or fake
   integration coverage a smoke. If a higher proof layer is blocked, report the
   blocker separately from the passing lower-layer proof.
4. Observability: use the shared Victoria path below. AgentStudio produces
   telemetry; the shared stack owns VictoriaMetrics, VictoriaLogs, and
   VictoriaTraces. Prefer marker-scoped verifiers over screenshots, stale JSONL,
   or ad hoc log scraping.
5. Native UI debugging: prefer headless proof first. When visual/native
   interaction proof is required, run a debug or beta app and use Peekaboo with
   PID targeting. Treat Peekaboo evidence as visual/render/interaction proof,
   not a replacement for unit, integration, or observability proof.

## Local Observability

AgentStudio is an observability producer only. Do not add Docker Compose,
VictoriaMetrics, VictoriaLogs, VictoriaTraces, or collector ownership to this
repo. The shared local observability host is intended to live in shared tooling
at `~/dev/ai-tools/observability`, with shared service names and data
directories so unrelated projects can use the same stack.

Shared-host commands:

```bash
mise run observability:up
mise run observability:status
mise run observability:smoke
mise run observability:down
```

The underlying source of truth is
`~/dev/ai-tools/observability/observability-stack`.
The shared Docker Compose services are `ai-tools-otel-collector`,
`ai-tools-victoria-metrics`, `ai-tools-victoria-logs`, and
`ai-tools-victoria-traces`; app repos must target those shared containers
through loopback endpoints instead of creating or querying per-app stacks.

Standard debug proof path for PR branches:

```bash
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

To exercise a startup diagnostic during debug proof, pass
`AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=<action>` to the launcher. The launcher
records the selected action into the state file as
`AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION`; that state key is verifier
handoff, not the app input environment variable. Example:

```bash
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 \
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Use this path instead of raw `swift build` plus hand-written environment
variables. The runner allocates a shared Swift build slot, creates the debug app
identity, launches with the Victoria/OTLP environment, and records the marker
that the verifier queries in VictoriaLogs. Performance workload proof builds on
this same runner; it must not create a separate app identity, data root, zmx
root, build directory, trace marker, or process-discovery scheme.

The debug launcher wraps the debug binary in a signed per-worktree app bundle
named `Agent Studio Debug <code>`, where `<code>` is a deterministic
four-character base36 hash of the canonical worktree path. The short code is
intentional: zmx session names and Unix-domain socket paths are length-sensitive,
so debug identity spends as little path/name budget as possible. That launch
uses an isolated data root at `~/.agentstudio-db/<code>` and zmx directory at
`~/.agentstudio-db/<code>/z`, so a debug run from one worktree cannot share zmx
state with stable, beta, or another debug worktree. Debug observability bundles
also remove URL-handler registration so they cannot claim production
`agentstudio://` callbacks or deep links. Do not copy production or beta state
into this root unless a test plan explicitly calls for it. The generated debug
bundle, logs, traces, and zmx root live under `~/.agentstudio-db/<code>` rather
than repo `tmp/` so autonomous debug runs do not need to read their runnable app
from `~/Documents`.

To inspect the deterministic identity without launching:

```bash
scripts/run-debug-observability.sh --print-identity
```

The state file is `tmp/debug-observability/latest-observability.env`. It is a
marker/verifier handoff, not proof by itself; `mise run verify-debug-observability`
must still query VictoriaLogs and validate the live process identity.
The launcher refuses to start a second `Agent Studio Debug <code>` instance
while one is already running; quit the reported PID before collecting a new
debug observability proof for the same worktree. On refusal it overwrites
`tmp/debug-observability/latest-observability.env` with
`AGENTSTUDIO_OBSERVABILITY_STATUS=already_running` so stale markers cannot pass
verification.

Performance workload proof path:

```bash
mise run observability:up
mise run verify-git-refresh-performance-workload
```

This script creates disposable fixture repos/worktrees, calls
`scripts/run-debug-observability.sh --print-identity`, preflights the standard
debug app is idle, launches through `scripts/run-debug-observability.sh
--detach`, and then verifies marker-scoped performance telemetry through
VictoriaMetrics. Standard performance proof must use VictoriaMetrics when the
shared collection exists. JSONL is only a local artifact/debug aid and must not
be an automatic fallback; set `AGENTSTUDIO_PERF_ALLOW_JSONL_PROOF=1` only when a
test plan explicitly asks for JSONL proof.

Local beta diagnostic path:

```bash
mise run observability:up
mise run create-beta-app-bundle
mise run run-beta-observability -- --latest-local
```

This local beta helper is diagnostic only. The release workflow is the source of
truth for beta promotion: it builds, signs, notarizes, staples, and publishes the
real `AgentStudio Beta.app` artifact from a beta tag. Use the local debug runner
for PR-branch proof, then use the GitHub-produced beta artifact for promotion
proof.

`run-beta-observability` stays attached to LaunchServices with `open -W` so
task runners do not clean it up early. Leave it running, then verify from
another shell:

```bash
AGENTSTUDIO_EXPECTED_BETA_APP="$DOWNLOADED_WORKFLOW_BETA_APP" mise run verify-beta-observability
```

`run-beta-observability` does not install over `/Applications/AgentStudio
Beta.app`. With `--latest-local`, it prefers the newest local bundle under
`~/.agentstudio-db/beta-observability/`, falling back to legacy repo-local
bundles under `tmp/beta-observability/` only if present. Release-promotion proof
must pass `--app "$DOWNLOADED_WORKFLOW_BETA_APP"` and bind
`verify-beta-observability` with `AGENTSTUDIO_EXPECTED_BETA_APP`, so a stale
installed beta or local diagnostic bundle cannot satisfy the gate. Generated
beta apps, logs, and traces live outside `~/Documents` so local proof runs do
not trigger Documents-folder TCC prompts merely because this worktree is under
Documents.
The debug and beta observability launchers intentionally require the shared
collector health endpoint to be reachable; run `mise run observability:up`
first. They run from a minimal clean environment and pass only the candidate
app's trace/data variables (`open --env` for LaunchServices, equivalent direct
environment for debug fallback), so inherited production app identity, Ghostty
resource variables, `ZMX_DIR`, `ZMX_SESSION`, and `ZMX_SESSION_PREFIX` cannot
leak into the candidate process. The launchers write per-run markers to
`tmp/debug-observability/latest-observability.env` or
`tmp/beta-observability/latest-observability.env`; verification queries those
markers so stale logs cannot satisfy the gate.
The beta launcher likewise refuses to launch while any beta-channel
AgentStudio process is already running, even from another bundle path. Beta
promotion proof should start from one known beta process. Its refusal path also
writes `AGENTSTUDIO_OBSERVABILITY_STATUS=already_running` to the beta state
file. Repo-local observability helpers run under `/bin/bash`
rather than Homebrew bash because the Homebrew bash process has previously
wedged release/verification scripts on this machine. Detached debug and beta
launchers try LaunchServices `open` first. Debug may fall back to direct
`Contents/MacOS/AgentStudio` execution when a local generated bundle is rejected
by LaunchServices/Gatekeeper; the state file then records
`AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=direct_executable`. This is valid for
Victoria/OTLP debug proof and keeps the same isolated data/zmx root, but it is
not full GUI proof. Beta does not use this fallback: if LaunchServices returns a
launch error, beta writes `AGENTSTUDIO_OBSERVABILITY_STATUS=launch_failed` and
exits non-zero. Local ad-hoc beta bundles may be rejected by
AMFI/LaunchServices; Developer ID signing alone can still be rejected as
unnotarized. Beta promotion proof requires the accepted/notarized artifact
produced by the GitHub release workflow, or another explicitly notarized local
artifact. Developer ID signing is opt-in for local diagnostic bundles: set
`SIGNING_IDENTITY` when running `mise run create-beta-app-bundle`.

Debug and beta builds use a safe baseline when `AGENTSTUDIO_TRACE_TAGS` is
unset: JSONL plus OTLP logs/metrics to `http://127.0.0.1:4318`. Stable builds stay
disabled unless trace tags are explicit, and explicit stable tracing defaults to
JSONL. `AGENTSTUDIO_TRACE_TAGS=off` disables the debug/beta baseline.
Trace tags are the only instrumentation selection surface. Do not add ad-hoc
per-emitter environment variables such as `AGENTSTUDIO_TRACE_*_METRICS`;
high-volume lanes such as atoms must be selected with
`AGENTSTUDIO_TRACE_TAGS=atoms` or the debug helper's `*` tag set. Standard
performance workload proof excludes `atoms` by default and should enable it only
for a dedicated atom telemetry proof run.

Use `AGENTSTUDIO_TRACE_BACKEND=jsonl|otlp|both` for explicit selection.
`OTEL_EXPORTER_OTLP_ENDPOINT` is accepted only for loopback HTTP endpoints and
is treated as a collector base URL; AgentStudio sends logs to `/v1/logs` and
metrics to `/v1/metrics`.
Collector absence or exporter failure must be fail-open for normal app startup
and must not prevent JSONL writes.

AgentStudio currently exports OTLP logs and performance metrics. The shared
stack also runs VictoriaTraces for other local producers, and its smoke gate
exercises all three ingestion lanes.

OTLP output is source-scrubbed. Allowed resource identity is limited to safe
runtime labels plus deterministic repo/worktree hashes and branch, for example
`dev.repo.hash`, `dev.worktree.hash`, `dev.branch.name`,
`dev.runtime.flavor`, and `dev.release.channel`. Raw paths, raw UUIDs, prompts,
payload text, errors, and tool output must not be exported over OTLP.

## Release Process

Releases are tag-driven from `main` via `.github/workflows/release.yml`; tag parsing lives in `scripts/release-tag-metadata.sh`.

- Stable: `vX.Y.Z` → `AgentStudio.app`, `com.agentstudio.app`, `~/.agentstudio`, `agentstudio://oauth/callback`, Homebrew `agent-studio`.
- Beta: `vX.Y.Z-beta.N` → `AgentStudio Beta.app`, `com.agentstudio.app.beta`, `~/.agent-studio-b`, `agentstudio-beta://oauth/callback`, Homebrew `agent-studio@beta`.

Before pushing a release tag, verify from the merged `main` commit:

```bash
mise run lint
mise run test
bash scripts/verify-release-scripts.sh
```

After the workflow finishes, smoke the downloaded `.app` plist/signature/notarization and confirm the matching Homebrew cask SHA was updated.

### No Wall-Clock Tests

Wall-clock sleeps make tests flaky. CI machines run at different speeds, so "sleep 50ms and expect X" is not a contract.

Do not:
- use `Task.sleep(...)` in test bodies to wait for async work
- use `Task.sleep(for:)` in AgentStudio code. It has caused crash issues in this
  app; use `Task.sleep(nanoseconds:)` with explicit `Duration` conversion only
  when a sleep is unavoidable, and prefer event/state waits or injected clocks.
- assert intermediate state after an arbitrary delay
- rely on suite serialization to hide leaked async work

Instead:
- wait for the exact event or state you care about, with a bounded timeout
- use injected clocks for debounce/timer behavior
- fully shut down tasks, streams, actors, and observers before the test returns
- use explicit protocol seams and fakes for testability
- do not add new `#if DEBUG` test hooks in production files

## Architecture at a Glance

AppKit-main architecture hosting SwiftUI views. Shared app state is actor-bound and accessed through `AtomRegistry` + `AtomScope`, with `atom(\.foo)` as the primary read path. Canonical mutable state lives in `@MainActor @Observable` atoms under `Core/State/MainActor/Atoms`, and persistence wrappers live under `Core/State/MainActor/Persistence`. Two coordinators handle cross-slice sequencing. An `EventBus<RuntimeEnvelope>` connects runtime actors to the main-actor state system, and a separate app lifecycle monitor owns AppKit ingress.

`AtomRegistry` is the single root-level composition file at `Sources/AgentStudio/AtomRegistry.swift`. It may compose Core and Feature atoms. `Infrastructure/AtomLib` owns only generic atom primitives and access helpers (`atom(\...)`, `AtomScope`, `AtomReader`, `Derived`, `DerivedSelector`, `AtomValue`, `AtomEntityMap`, `DerivedValue`) and must not own product atoms or feature-specific registry fields. Hot UI reads for keyed entity state should use keyed atom-family-style slots such as `AtomEntityMap.value(for:)`; dictionary-shaped snapshots are for persistence, cold bulk bridges, and measured exceptions.

Architecture boundaries are enforced by stock SwiftLint plus the repo-local
SwiftPM/SwiftSyntax tool in `Tools/AgentStudioArchitectureLint`. `mise run lint`
runs swift-format, `swiftlint lint --strict`, the local architecture linter, and
release script checks. The architecture linter is AgentStudio-owned tooling; it
must not add SwiftSyntax dependencies to the app package. Do not reintroduce
repo-local shell/`rg` architecture lint scripts for rules that can be expressed
with SwiftSyntax, and do not restore an external custom-SwiftLint toolchain.

### Folder Arcs

Use these broad ownership rules first, then consult [Directory Structure](docs/architecture/directory_structure.md) for exact placement:

- `App/`
  Composition root and host-specific assembly. App-owned shells, pane/window controllers, lifecycle wiring, and cross-slice orchestration live here.
- `Core/`
  Shared domain state and contracts. Models, atoms, persistence wrappers, validated action routing, runtime contracts, and shared split/drawer primitives live here.
- `SharedComponents/`
  Reusable UI building blocks that are not themselves product features and do not own host placement. Use this for reusable menu content, row rendering, and small UI-facing models.
- `Features/`
  User-facing capability slices such as Terminal, Bridge, Webview, CodeViewer, CommandBar, RepoExplorer, InboxNotification, and feature-owned EditorChooser state. Features own capability-specific behavior that is broader than a reusable component.
- `Infrastructure/`
  Domain-agnostic utilities and external integrations. Organize these in subfolders by concern, such as `AtomLib/`, `Extensions/`, `Icons/`, `StateMachine/`, and integration-specific folders like `ExternalApps/`. `Infrastructure/AtomLib` holds generic atom access helpers and primitives only; the concrete `AtomRegistry` lives at the source root because it composes Core and Feature atoms.

### Shared UI, Styles, And Policies

When two app surfaces need the same visual control, extract a shared primitive into `SharedComponents/` instead of copying styling between features. Shared components render from direct values, `@Binding`, callbacks, or explicitly passed observable view models; they do not read atoms, reach into global stores, or import `Core/`, `Features/`, or `App/`.

Before creating a feature-local UI primitive, check for an existing shared component with the same interaction semantics. Reuse or extract keyboard, focus, selection, and command-toggle behavior even when row content differs. Styling parity alone is not enough.

BridgeWeb React UI uses shadcn-style owned source primitives. For reusable React
controls, do not hand-roll route-local toggles, segmented controls, buttons,
menus, inputs, or toolbar widgets because one route happens to have nearby
markup. First check `BridgeWeb/src/components/ui/`. If the needed shadcn
primitive is missing, add the primitive source there, edit that owned component
to match Agent Studio's product tokens and sizing, then compose it through a
feature-neutral BridgeViewer/shared wrapper. Product-specific chrome may wrap
shadcn primitives, but it must not replace them with one-off custom controls.
For BridgeViewer specifically, FileViewer and ReviewViewer controls with the
same interaction semantics must share the same primitive layer and visual scale.

Bridge worktree and review git data prepared on the Swift/native side must use
the repo's `agentstudio-git` library. TypeScript may shell out to `git` only in
clearly scoped Vite dev-server utilities or test fixture utilities; do not use
TS git helpers as production Bridge protocol or source-adapter plumbing.

Use `AppStyles` for presentation constants only: spacing, radii, icon sizes, opacity, typography, colors, and paint dimensions. Use `AppPolicies` for behavioral constants: limits, thresholds, retention caps, validation rules, routing rules, and accept/reject decisions. If changing the value can change state transitions or command/event behavior, it belongs in `AppPolicies` even when the UI reads it.

Search rule of thumb:
- Sidebar search surfaces use `SharedComponents/SidebarSearchField`.
- Command bar search remains command-bar-owned because it owns scope and shortcut semantics.
- Webview select-all fields remain Webview-owned until a second feature needs that exact AppKit behavior.

### Command Specs And Execution Owners

Before adding or changing a command, read [Commands and Shortcuts](docs/architecture/commands_and_shortcuts.md). Use `AppCommand` for identity, `AppShortcut` for bindings, `AppCommandSpec` for command-bar/tooltips, and `LocalActionSpec` for UI-only actions. Dense toolbar/titlebar/drawer tooltip work must use the typed tooltip source contract in that doc and [Style Guide](docs/guides/style_guide.md), not parallel `.help`, AppKit `toolTip`, or custom hover strings. App/window/sidebar shell commands may route through `AppDelegate`; pane, drawer, focus, layout, and workspace commands route through `PaneTabViewController` so keyboard shortcuts, command-bar rows, and drawer buttons share the same resolver.

Command-bar scopes have separate ownership:
- `>` owns verbs and command execution.
- `$` owns existing pane/tab navigation.
- `#` owns repo/worktree locations and opening.

Keep this split explicit. Do not add repo/worktree management rows to `$`, do
not add arbitrary verbs to `#`, and do not duplicate `LocalActionSpec` labels or
icons when a sidebar/local action already defines the presentation.

| Component | Owns | Location |
|-----------|------|----------|
| `AtomRegistry` | concrete root composition file for Core and Feature atoms plus derived helpers | `Sources/AgentStudio/AtomRegistry.swift` |
| `SQLiteDatabaseFactory` | generic GRDB database construction, pragmas, WAL, and capability-test connection setup; no product schema knowledge | `Infrastructure/SQLite/SQLiteDatabaseFactory.swift` |
| `SQLiteSidecarQuarantine` | generic SQLite database/WAL/SHM quarantine helper; no product schema knowledge | `Infrastructure/SQLite/SQLiteSidecarQuarantine.swift` |
| `WorkspaceCoreMigrations` | `core.sqlite` migration identifiers and core workspace schema DDL; repository-facing only, not a live atom read model | `Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift` |
| `WorkspaceLocalMigrations` | `<workspace-id>.local.sqlite` migration identifiers and local UX/cache schema DDL; repository-facing only, not a live atom read model | `Core/State/MainActor/Persistence/WorkspaceLocalMigrations.swift` |
| `SQLitePaneContentTypeStorage` | repository-facing storage tokens for live `PaneContentType` values used by `pane.content_type` and content-table triggers | `Core/State/MainActor/Persistence/SQLitePaneContentTypeStorage.swift` |
| `SQLiteLocalUXStorage` | repository-facing storage tokens for sidebar surface and recent workspace target vocabulary used by local UX schema checks | `Core/State/MainActor/Persistence/SQLiteLocalUXStorage.swift` |
| `SQLiteInboxNotificationClaimStorage` | repository-facing storage tokens for inbox claim-lane merge predicates used by local notification schema indexes | `Core/State/MainActor/Persistence/SQLiteInboxNotificationClaimStorage.swift` |
| `InboxNotificationSQLiteRepository` | feature-owned local SQLite repository for notification inbox rows, collapsed inbox groups, claim coalescence, retention, empty-lane marking, and legacy-import materialization proof | `Features/InboxNotification/State/MainActor/Persistence/InboxNotificationSQLiteRepository.swift` |
| `ActiveWorkspaceSelectionAtom` | global active workspace id selection, independent from per-workspace metadata hydration | `Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtom.swift` |
| `WorkspaceIdentityAtom` | workspace id, name, and creation timestamp | `Core/State/MainActor/Atoms/WorkspaceIdentityAtom.swift` |
| `WorkspaceWindowMemoryAtom` | local sidebar width and window frame memory | `Core/State/MainActor/Atoms/WorkspaceWindowMemoryAtom.swift` |
| `WorkspaceRepositoryTopologyAtom` | repos, worktrees, watched paths, availability | `Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift` |
| `WorkspacePaneGraphAtom` | core pane graph: pane identity, content (including stored terminal zmx anchors), residency, durable metadata with live facets, drawer identity, drawer membership | `Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift` |
| `WorkspaceDrawerCursorAtom` | local drawer expansion cursor keyed by drawer id | `Core/State/MainActor/Atoms/WorkspaceDrawerCursorAtom.swift` |
| `WorkspacePaneAtom` | compatibility mutation facade over pane graph + drawer cursor | `Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` |
| `WorkspacePaneDerived` | UI read model composing rich `Pane` values from pane graph, drawer cursor, topology, and cache facts | `Core/State/MainActor/Atoms/WorkspacePaneDerived.swift` |
| `WorkspaceTabShellAtom` | tab shell identity and ordering | `Core/State/MainActor/Atoms/WorkspaceTabShellAtom.swift` |
| `WorkspaceTabCursorAtom` | local active-tab cursor | `Core/State/MainActor/Atoms/WorkspaceTabCursorAtom.swift` |
| `WorkspaceTabGraphAtom` | tab membership and arrangement/drawer-view layout graph | `Core/State/MainActor/Atoms/WorkspaceTabGraphAtom.swift` |
| `WorkspaceArrangementCursorAtom` | local active arrangement, active pane, and active drawer-child cursors | `Core/State/MainActor/Atoms/WorkspaceArrangementCursorAtom.swift` |
| `WorkspacePanePresentationAtom` | runtime-only pane presentation overrides such as tab zoom | `Core/State/MainActor/Atoms/WorkspacePanePresentationAtom.swift` |
| `WorkspaceTabArrangementAtom` | compatibility mutation facade over tab graph, arrangement cursor, and presentation owners | `Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift` |
| `WorkspaceTabLayoutAtom` | compatibility tab-layout facade over shell, cursor, graph, arrangement cursor, and presentation owners | `Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift` |
| `WorkspaceTabLayoutDerived` | UI read model composing rich `Tab`, `PaneArrangement`, and `DrawerView` values from tab write owners | `Core/State/MainActor/Atoms/WorkspaceTabLayoutDerived.swift` |
| `WorkspaceMutationCoordinator` | cross-atom workspace mutations spanning pane and tab layout state | `Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift` |
| `RepoEnrichmentCacheAtom` | rebuildable repo enrichment, worktree enrichment, PR counts, keyed revisions, and rebuild metadata; notification unread counts are inbox-owned | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `RecentWorkspaceTargetAtom` | local recent workspace target history | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `RepoCacheAtom` | UI-facing compatibility read surface over repo enrichment cache + recent targets; does not own notification unread counts | `Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| `SidebarExpandedGroupAtom` | local sidebar expanded-group memory | `Core/State/MainActor/Atoms/SidebarCacheState.swift` |
| `SidebarCheckoutColorAtom` | legacy checkout color memory; new sidebar presentation uses automatic colors and settings must not persist checkout colors | `Core/State/MainActor/Atoms/SidebarCacheState.swift` |
| `SidebarCacheState` | UI-facing composition surface over sidebar expanded groups plus legacy checkout color cleanup | `Core/State/MainActor/Atoms/SidebarCacheState.swift` |
| `WorkspaceSidebarMemoryAtom` | persisted workspace sidebar shell memory: filter text, filter visibility, collapsed state, active surface | `Core/State/MainActor/Atoms/WorkspaceSidebarState.swift` |
| `SidebarFocusRuntimeAtom` | runtime-only sidebar focus fact for keyboard-owner derivation | `Core/State/MainActor/Atoms/WorkspaceSidebarState.swift` |
| `SidebarVisibleWorktreesRuntimeAtom` | runtime-only sidebar visible worktree ids for git enrichment admission | `Core/State/MainActor/Atoms/SidebarVisibleWorktreesRuntimeAtom.swift` |
| `WorkspaceSidebarState` | UI-facing composition surface over sidebar memory + runtime focus atoms | `Core/State/MainActor/Atoms/WorkspaceSidebarState.swift` |
| `WorkspaceFocusOwnerAtom` | runtime focus owner for main-pane, empty-drawer, and drawer-pane focus | `Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtom.swift` |
| `WorkspacePaneFocusDerived` | shared app-wide pane focus reader for command visibility and status UI | `Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift` |
| `ManagementLayerAtom` | management layer active/inactive state | `Core/State/MainActor/Atoms/ManagementLayerAtom.swift` |
| `CommandBarSurfaceAtom` | runtime command-bar keyboard surface scope | `Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift` |
| `TransientKeyboardSurfaceAtom` | runtime transient keyboard surface stack | `Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtom.swift` |
| `ArrangementPanelPresentationAtom` | runtime pending arrangement panel presentation request | `Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift` |
| `SessionRuntimeAtom` | runtime status per pane | `Core/State/MainActor/Atoms/SessionRuntimeAtom.swift` |
| `EditorPreferenceAtom` | settings-bound bookmarked editor preference | `Features/EditorChooser/State/MainActor/Atoms/EditorChooserState.swift` |
| `EditorChooserRuntimeAtom` | runtime editor chooser open pane and discovered targets | `Features/EditorChooser/State/MainActor/Atoms/EditorChooserState.swift` |
| `EditorChooserState` | UI-facing composition surface over editor preference + chooser runtime atoms | `Features/EditorChooser/State/MainActor/Atoms/EditorChooserState.swift` |
| `InboxSidebarMemoryAtom` | persisted inbox sidebar collapsed-group memory | `Features/InboxNotification/State/MainActor/Atoms/InboxSidebarState.swift` |
| `InboxSidebarRuntimeAtom` | runtime pending inbox filter handoff | `Features/InboxNotification/State/MainActor/Atoms/InboxSidebarState.swift` |
| `InboxSidebarState` | UI-facing composition surface over inbox sidebar memory + runtime atoms | `Features/InboxNotification/State/MainActor/Atoms/InboxSidebarState.swift` |
| `WorkspaceStore` | persistence wrapper over the workspace-domain atoms | `Core/State/MainActor/Persistence/WorkspaceStore.swift` |
| `WorkspaceSQLiteDatastore` | actor boundary for product SQLite I/O, repository caching, strict core/local composition loading, and commit sequencing; does not own atoms | `Core/State/SQLite/WorkspaceSQLiteDatastore.swift` |
| `WorkspaceSQLiteSnapshot` | immutable live SQLite bridge snapshot passed across the MainActor/datastore boundary; not a legacy JSON DTO and not a row projection | `Core/State/SQLite/WorkspaceSQLiteSnapshot.swift` |
| `WorkspaceSQLiteRecoveryClassifier` | GRDB corruption/not-a-database classifier shared by product SQLite recovery paths; no repository or atom ownership | `Core/State/SQLite/WorkspaceSQLiteRecoveryClassifier.swift` |
| `WorkspaceSQLiteStoreBackendFactory` | product-specific SQLite backend bootstrap, core migration, core sidecar quarantine, and local repository construction | `Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackendFactory.swift` |
| `RepoCacheStore` | persistence wrapper for `RepoEnrichmentCacheAtom` + `RecentWorkspaceTargetAtom` | `Core/State/MainActor/Persistence/RepoCacheStore.swift` |
| `UIStateStore` | persistence wrapper for workspace sidebar shell memory only | `Core/State/MainActor/Persistence/UIStateStore.swift` |
| `WorkspaceSettingsStore` | persistence wrapper for editor bookmark, repo explorer sidebar preferences, and inbox notification preferences until feature-specific settings stores split; checkout colors are intentionally ignored/cleared | `Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift` |
| `InboxNotificationStore` | persistence wrapper for inbox notification history and collapsed inbox groups; uses feature SQLite repository when the local backend is available and legacy JSON only for uninitialized import | `Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift` |
| `AppLifecycleAtom` | application active/terminating state | `Core/State/MainActor/Atoms/AppLifecycleAtom.swift` |
| `WindowLifecycleAtom` | key/focused window identity, registration, transient terminal geometry, launch-settle facts | `Core/State/MainActor/Atoms/WindowLifecycleAtom.swift` |
| `AttendedPaneDerived` | pure current attended-pane read composed from tab, window, and management state; observation and transition delivery stay in `PaneFocusTracker` | `Core/State/MainActor/Atoms/AttendedPaneDerived.swift` |
| `FilesystemProjectionIndex` | off-main pane/worktree filesystem indexing, canonicalization, filtering, and typed projection intents; `WorkspaceSurfaceCoordinator` sequences and publishes the resulting pane envelopes | `App/Coordination/FilesystemProjectionIndex.swift` |
| `SurfaceManager` | Ghostty surface lifecycle, health, undo | `Features/Terminal/` |
| `SessionRuntime` | backend coordination, health checks, zmx/runtime orchestration over `SessionRuntimeAtom`; zmx attach identity comes from stored `TerminalState.zmxSessionId` anchors | `Core/RuntimeEventSystem/Runtime/SessionRuntime.swift` |

**Worktree model is structure-only:** `id`, `repoId` (FK), `name`, `path`, `isMainWorktree`. No branch, no status. All enrichment lives in `RepoEnrichmentCacheAtom`, populated by the event bus and exposed to existing UI readers through `RepoCacheAtom`.

**Event bus pattern:** Mutate the store directly → emit a fact on the bus → coordinator updates the other store. This is NOT CQRS — no command bus, no command handlers. `ApplicationLifecycleMonitor` is ingress-only and mutates lifecycle stores directly from AppKit callbacks. See [State Management Patterns](#state-management-patterns) below and [Event System Design](docs/architecture/workspace_data_architecture.md#event-system-design-what-it-is-and-isnt) for full detail.

**Embedded Ghostty host split:** Keep `Ghostty.shared` as the subsystem entrypoint and keep `Ghostty.App` thin. Host-side runtime responsibilities are split by isolation contract:
- `Ghostty.AppHandle` owns `ghostty_app_t` and config lifetime
- `Ghostty.CallbackRouter` owns the C callback table and userdata reconstruction
- `Ghostty.ActionRouter` owns the action switch and runtime routing seam
- `Ghostty.AppFocusSynchronizer` owns app-level focus sync via `AppLifecycleAtom.isActive`
Future terminal event-routing expansion belongs in `Ghostty.ActionRouter` plus adapter/runtime layers, not back in `Ghostty.swift`.

**High-volume source rule:** Use the owning domain's typed source-admission path.
Preserve exact commands and facts. Contract Terminal-local samples before
MainActor/EventBus publication, publish only changed projected semantic outcomes
from that contracted evidence, and use affected-key filesystem effects for ordinary
pane/CWD changes. See [Pane Runtime Contract 7](docs/architecture/pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction),
[EventBus Design](docs/architecture/pane_runtime_eventbus_design.md#typed-admission-before-multiplexing),
and [Workspace Data Architecture](docs/architecture/workspace_data_architecture.md#filesystem-effect-admission-and-projection).

### Architecture Docs

Each doc owns a specific concern. See [Architecture Overview](docs/architecture/README.md) for the full document index.

| Doc | Covers |
|-----|--------|
| [Component Architecture](docs/architecture/component_architecture.md) | Data model, stores, coordinator, persistence, invariants |
| [Workspace Data Architecture](docs/architecture/workspace_data_architecture.md) | Three-tier persistence, enrichment pipeline, event bus contracts, sidebar data flow |
| [Atom Persistence Boundaries](docs/architecture/atom_persistence_boundaries.md) | Atom-to-SQLite boundary model, lifecycle lanes, derived read models, runtime-only surfaces |
| [Pane Runtime Architecture](docs/architecture/pane_runtime_architecture.md) | Pane runtime contracts (C1-C16), RuntimeEnvelope, event taxonomy |
| [EventBus Design](docs/architecture/pane_runtime_eventbus_design.md) | Actor threading, connection patterns, multiplexing rule |
| [Session Lifecycle](docs/architecture/session_lifecycle.md) | Pane identity, creation, close, undo, restore, zmx backend |
| [Surface Architecture](docs/architecture/ghostty_surface_architecture.md) | Ghostty surface ownership, state machine, health, crash isolation |
| [App Architecture](docs/architecture/appkit_swiftui_architecture.md) | AppKit+SwiftUI hybrid, controllers, events |
| [Observability And Traceability](docs/architecture/observability_and_traceability.md) | Trace tags, debug/beta OTLP proof, source-side projection, Victoria proof rules |
| [Commands and Shortcuts](docs/architecture/commands_and_shortcuts.md) | The four-file system (AppCommand / AppShortcut / AppCommandSpec / LocalActionSpec), execution-owner decision tree (`AppDelegate` shell vs `PaneTabViewController` pane/drawer), contexts, alternateTriggers, and where constants live (AppShortcut vs AppPolicies vs AppStyles vs LocalActionSpec) |
| [Directory Structure](docs/architecture/directory_structure.md) | Module boundaries, Core vs Features, import rule, component placement |
| [Architecture Lint Inventory](docs/architecture/architecture_lint_inventory.md) | SwiftLint rule IDs, former shell-script coverage, and blocking/report-only/test/review classifications |
| [AgentStudio IPC Architecture](docs/architecture/agentstudio_ipc_architecture.md) | App-level programmatic-control contract, AppIPC port, composition, and zmx separation boundaries |
| [Bridge Viewer Architecture](docs/architecture/bridge_viewer_architecture.md) | End-to-end Bridge Viewer ownership and flow; routes to the [native runtime](docs/architecture/bridge_native_runtime_architecture.md) and [web runtime](docs/architecture/bridge_web_runtime_architecture.md) source documents |
| [Style Guide](docs/guides/style_guide.md) | macOS design conventions and visual standards |
| [Agent Resources](docs/guides/agent_resources.md) | Bootstrap, official Swift/macOS docs, DeepWiki sources, and research guidance |

### Plans

Active implementation plans live in `docs/plans/`. Plans are date-prefixed (`YYYY-MM-DD-feature-name.md`). If a plan's date is before the current branch's work started, it's likely completed — verify before executing.

## Before You Code

### UX-First (Mandatory for UI Changes)

**STOP. Before implementing ANY UI/UX change:**
1. Talk to the user FIRST — discuss the UX problem, align on the experience
2. Research using Perplexity/DeepWiki BEFORE coding
3. Propose the approach, get alignment, then implement
4. Verify with [Peekaboo](https://github.com/steipete/Peekaboo) after

Swift compile times are long. A wrong UX assumption wastes minutes per iteration. Research → discuss → implement → verify.

### Visual Verification

Agents **must** visually verify all UI/UX changes using Peekaboo after the
lower proof layers that apply to the change. **Never target apps by name** when
testing debug builds — use PID targeting. **Never `pkill` AgentStudio** — it
kills the user's running app. The build dir is auto-allocated by `mise run build`
(see [Running Swift Commands — Detail](#running-swift-commands--detail)); locate
the binary and launch from there:

```bash
mise run build                              # claims a slot, prints "[swift-build-slot] using .build-agent-N"
BUILD_PATH=$(ls -dt .build-agent-*/debug/AgentStudio 2>/dev/null | head -1 | xargs dirname | xargs dirname)
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
peekaboo see --app "PID:$PID" --json
```

### Definition of Done

1. All requirements met
2. All tests pass (`mise run test` — show pass/fail counts)
3. Lint passes (`mise run lint` — zero errors)
4. Code reflects the shared mental model
5. Evidence provided (exit codes, counts)

### Agent Resources

Use DeepWiki and official documentation for grounded context. Never guess at APIs.
- **Guide**: [Agent Resources & Research](docs/guides/agent_resources.md) — first-time setup, DeepWiki knowledge base
- **Core Repos**: `ghostty-org/ghostty`, `swiftlang/swift`

---

## State Management Patterns

These four patterns govern all code. Follow them. Breaking them creates bugs that are expensive to find.

### 1. Atoms — canonical state

`@Observable @MainActor`, `private(set)` reads, and mutations through narrow methods. Atoms own canonical state or pure derived state, Jotai-style.

Atom methods may only assign values, perform simple local transforms, suppress equal writes, and maintain storage indexes or observation invariants. They must not contain business rules, command interpretation, validation, mutation planning, semantic effects, persistence, I/O, async work, or cross-atom coordination.

Business rules belong in pure domain types; coordinators sequence them; persistence adapters capture and restore state.

**Write-owner atoms are not SQL table models.** When moving persistence to SQLite, keep atom boundaries aligned to lifecycle and semantic write ownership, not relational normalization. A write-owner atom may project to multiple normalized tables when one validated user command must update those rows coherently. Use derived readers/atoms to compose rich UI/domain values from several write-owner atoms. Do not create one atom per table such as `pane`, `drawer_pane`, `tab_pane`, and `arrangement_layout_pane`; that pushes table orchestration into coordinators and destroys domain cohesion.

**Disclose atom and type roles.** When adding or splitting atom-backed state, name and document whether each affected type is write-owner atom state, a derived read model, a SQLite row projection, or a legacy import DTO. Rich UI names such as `Pane`, `Drawer`, `Tab`, `PaneArrangement`, and `DrawerView` may remain derived read-model names, but write-owner atoms should store explicit graph/cursor/presentation state, legacy JSON should use explicit `Legacy*Payload` DTOs, and future SQLite repositories should use explicit `*Row` projections. Do not let `Codable` legacy payload names become the live SQLite storage contract by accident.

**Survey does not mean persist.** During SQLite planning, every atom-backed field must be classified into one lifecycle lane: core graph, local UX memory, settings, cache, runtime/presentation, derived read model, legacy import DTO, or future row projection. Only the durable lanes get storage. Runtime/presentation atoms such as command-bar surfaces, transient keyboard surfaces, arrangement-panel requests, pane-note popover/draft state, focus handoffs, health snapshots, and ordinal helpers stay out of SQLite unless a separate UX decision explicitly promotes them to local memory with tests. Pane note text itself is durable pane metadata and belongs with the pane graph.

**SQLite cutover alignment.** The planned SQLite cutover splits lifecycle-mixed atoms before repository work: workspace identity vs window memory, tab shell vs cursor, pane graph vs drawer cursor, tab graph vs arrangement cursor vs runtime presentation, cache enrichment vs recent targets, and settings/runtime feature state. `active_workspace_id` is global core state and needs its own selection owner. Step 0 starts from `main` after pane-shortcuts and command-bar repo/worktree changes merged through `54c99b91`; action snapshots, validators, runtime shortcut/presentation atoms, `KeyboardRoutingContext`, `ActiveKeyboardSurface`, `PaneOrdinalMap`, pane-note metadata/presentation, CWD context updates, and RepoCacheStore observation are part of the Step 0 survey. When these boundaries are implemented, update this `AGENTS.md` component table and the architecture docs in the same changeset as the code.

**SQLite recovery invariants.** Legacy archive readiness requires matching core and local SQLite snapshot completion timestamps, not just a core row. If local completion is stale or missing during restore, hydrate the canonical core workspace with deterministic local defaults and repair the local snapshot completion when possible. SQLite sidecar quarantine is corruption-only (`SQLITE_CORRUPT` / `SQLITE_NOTADB`); non-corruption open failures must not move database sidecars. Legacy workspace import materialization must not mutate `active_workspace_id`; select the active workspace only once through the explicit importer outcome path.

**Path convention (universal):** `<owner>/State/MainActor/Atoms/` for all atoms, whether Core or Feature. Shared atoms in `Core/State/MainActor/Atoms/`; feature-scoped atoms in `Features/<slice>/State/MainActor/Atoms/`. Existing features without the `MainActor/` subpath are grandfathered; new features adopt the full path.

**Composition state vs feature state.** Composition state (app-wide UI shell — which surface is showing, whether the sidebar is collapsed, and whether the sidebar owns focus) is split by lifecycle in Core. Persisted shell memory lives on `WorkspaceSidebarMemoryAtom`, runtime-only focus lives on `SidebarFocusRuntimeAtom`, and UI call sites read the composed `WorkspaceSidebarState`. Feature state (domain data specific to one feature) lives in feature atoms inside the feature slice. Never add a feature-specific property to a Core atom; never add a feature type to `Core/Models/` just because an atom references it — that forces feature types into Core.

Shared reads use `atom(\.foo)` or `AtomReader`; `@Atom(\.foo)` is optional convenience sugar. See [component_architecture.md](docs/architecture/component_architecture.md) and [directory_structure.md — Feature Slice Self-Containment](docs/architecture/directory_structure.md) for canonical examples.

### 2. Stores — persistence wrappers

One store per persistence boundary. A store may wrap one atom (`RepoCacheStore`) or many that persist together in one file (`WorkspaceStore`). Stores own file I/O, debounced saves, and schema versioning. Stores never contain domain logic.

**Path convention (universal):** `<owner>/State/MainActor/Persistence/` for all stores, whether Core or Feature. Shared stores in `Core/State/MainActor/Persistence/`; feature-scoped stores in `Features/<slice>/State/MainActor/Persistence/`. See [Three Persistence Tiers](docs/architecture/workspace_data_architecture.md#three-persistence-tiers) for the file-level mapping.

**Atom and store boundaries are architectural decisions — always ask the user before changing them:**
- **Adding a new atom or store:** "Does this earn its own atom/store? What's the one-sentence job description? What's the single reason it changes?"
- **Adding properties to an existing atom:** "Does this property belong here, or is it polluting this atom's job? Could it belong elsewhere or be derived?" An atom that accumulates unrelated properties is becoming a god-atom by accretion.
- **Adding new event types or coordinator responsibilities:** These expand the system's surface area. Discuss before implementing.

### 3. Coordinator Sequences, Doesn't Own

A coordinator sequences operations across stores for a user action. Owns no state, contains no domain logic. **The test:** if a coordinator method has an `if` that decides *what* to do with domain data, that logic belongs in a store. See [WorkspaceSurfaceCoordinator](docs/architecture/component_architecture.md#36-workspacesurfacecoordinator) for the cross-store pattern.

### 4. Event-Driven Enrichment — Bus → Coordinator → Stores

Runtime actors produce facts → `EventBus` → `WorkspaceCacheCoordinator` → updates stores.

```
FilesystemActor ──► .repoDiscovered(linkedWorktrees: .scanned([...])) ──┐
GitProjector    ──► .snapshotChanged, .branchChanged ───────────────────┤──► EventBus
ForgeActor      ──► .pullRequestCountsChanged ──────────────────────────┘      │
                                                                               ▼
                                                              WorkspaceCacheCoordinator
                                                              (topology accumulator)
                                                                       │
                                              ┌────────────────────────┼──────────────────────┐
                                              ▼                        ▼                      ▼
                                       WorkspaceRepositoryTopologyAtom  RepoCacheAtom  TopologyEffectHandler
                                       WorkspacePaneAtom facade + WorkspaceTabLayoutAtom
                                       WorkspacePaneGraphAtom + WorkspaceDrawerCursorAtom
                                              │                        │              orphan panes +
                                              └────────────┬───────────┘              sync FS roots
                                                           ▼
                                                    Sidebar (@Observable reader)
```

**Topology accumulator pattern:** For topology events with `LinkedWorktreeInfo.scanned(...)`, the coordinator uses `WorktreeReconciler` (pure function) to compute a `WorktreeTopologyDelta`, then calls `TopologyEffectHandler.topologyDidChange(delta)` for ordered effects. Cache pruning happens in the coordinator; pane orphaning + filesystem root sync happens in WorkspaceSurfaceCoordinator via the handler. WorkspaceSurfaceCoordinator does NOT subscribe to topology events on the bus. See [Workspace Data Architecture — Topology Accumulator Pattern](docs/architecture/workspace_data_architecture.md).

**This is NOT CQRS.** The event bus carries facts, not commands. Stores are mutated by their own methods. Typed command planes still exist, but they do **not** run through the bus:
- `WorkspaceActionCommand` for workspace mutations (`AppCommandDispatcher` → `WorkspaceCommandResolver` builds `ActionStateSnapshot` → `WorkspaceCommandValidator` validates against snapshot → `WorkspaceSurfaceCoordinator`)
- `PaneRuntimeCommand` for pane-runtime commands (`WorkspaceSurfaceCoordinator` → `RuntimeRegistry` → `runtime.handleCommand(...)`)
- `AppEventBus` for app-level notifications/facts that do not fit either command plane
- `ApplicationLifecycleMonitor` for AppKit/macOS lifecycle ingress into the lifecycle stores

**The pattern:** mutate store directly → emit fact on bus → coordinator updates other store.

**Do NOT:** add command enums, route mutations through the bus, create command/event type pairs, build read/write segregation.

**Do:** emit topology events after canonical mutations, make handlers idempotent (dedup by stableKey/worktreeId), use the bus for notification only.

### Coordination Plane Decision Table

Use the narrowest plane that still preserves the architecture boundary.

| If the change is... | Use | Notes |
|---------------------|-----|-------|
| Workspace mutation | `WorkspaceActionCommand` | Validator-gated, then sequenced by `WorkspaceSurfaceCoordinator` into stores. |
| Runtime command | `PaneRuntimeCommand` | Direct `WorkspaceSurfaceCoordinator -> RuntimeRegistry -> runtime.handleCommand(...)`. |
| Runtime fact | `PaneRuntimeEventBus` | Fact fan-out only; never route commands through it. |
| Topology fact (repo/worktree discovered/removed) | `PaneRuntimeEventBus` | Fact fan-out. Coordinator is the single accumulator. Uses `WorktreeReconciler` + `TopologyEffectHandler`. |
| Ordered post-topology effects (root sync, pane orphan) | `TopologyEffectHandler` | Direct handler call from coordinator to WorkspaceSurfaceCoordinator. NOT via bus — ordering must be deterministic. |
| App-level notification that is not a command | `AppEventBus` | Notification fan-out only. Not a workspace command boundary. |
| AppKit/macOS lifecycle ingress | `ApplicationLifecycleMonitor` | Owns AppKit ingress and writes `AppLifecycleAtom` / `WindowLifecycleAtom`. |
| UI-only local state | Local `@Observable` state | Keep it in the owning view/controller. Do not bounce it through a bus or `NotificationCenter`. |

The old `AppCommand -> AppEventBus -> controller -> WorkspaceActionCommand` chain has been removed. User-triggered workspace work now enters through validated `WorkspaceActionCommand` routing directly.

For full detail:
- [Event namespaces](docs/architecture/workspace_data_architecture.md#event-namespaces) — which events exist and who produces them
- [Lifecycle flows](docs/architecture/workspace_data_architecture.md#lifecycle-flows) — boot, Add Folder, branch change step-by-step
- [Integration test examples](docs/architecture/workspace_data_architecture.md#writing-integration-tests-with-events) — how to test event flows with real stores
- [Idempotency contracts](docs/architecture/workspace_data_architecture.md#idempotency-contract) — dedup keys and ordering tolerance
- [Actor threading](docs/architecture/pane_runtime_eventbus_design.md#architecture-overview) — how actors connect to the bus

### Additional Patterns

**AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. No new Combine subscriptions. No new NotificationCenter observers.

**Choose the right coordination plane**:
- Asking the workspace to change shape: `WorkspaceActionCommand`
- Asking one runtime to do work: `PaneRuntimeCommand`
- Reporting that something already happened: `PaneRuntimeEventBus`
- Broadcasting an app-level fact/notification that does not belong on the command planes: `AppEventBus`
- Handling AppKit/macOS lifecycle ingress: `ApplicationLifecycleMonitor`

**Injectable Clock** — All store-level time-dependent logic accepts `any Clock<Duration>` as a constructor parameter. This makes undo TTLs, health checks, and debounce timers testable.

**Bridge-per-Surface** — Each Ghostty surface gets a typed bridge conforming to `PaneBridge` with its own observable state. See [Surface Architecture](docs/architecture/ghostty_surface_architecture.md).

**What we don't do:** No god-store. No Combine for new code. No NotificationCenter for new app-domain coordination. No `ObservableObject/@Published`. No `DispatchQueue.main.async` from C callbacks.

---

## Project Structure

See [Directory Structure](docs/architecture/directory_structure.md) for the full module boundary spec, Core vs Features decision process, and component placement rationale.

```
agent-studio/
├── Sources/AgentStudio/
│   ├── App/                          # Composition root — wires everything, imports all
│   │   ├── Boot/AppDelegate.swift
│   │   ├── Windows/MainWindowController.swift
│   │   ├── Coordination/WorkspaceSurfaceCoordinator.swift  # Cross-feature sequencing and orchestration
│   │   └── Panes/                    # Pane tab management and NSView registry
│   ├── Core/                         # Shared domain — models, stores, pane system
│   │   ├── Models/                   # Layout, Tab, Pane, Repo, Worktree, SidebarSurface,
│   │   │                             #   KeyboardOwner, ...
│   │   ├── State/
│   │   │   └── MainActor/
│   │   │       ├── Atoms/            # WorkspaceIdentityAtom, WorkspacePaneGraphAtom,
│   │   │       │                     #   WorkspaceDrawerCursorAtom, WorkspacePaneAtom facade,
│   │   │       │                     #   WorkspaceSidebarState, ManagementLayerAtom,
│   │   │       │                     #   WorkspacePaneFocusDerived, KeyboardOwnerDerived, ...
│   │   │       └── Persistence/      # WorkspaceStore, RepoCacheStore, UIStateStore
│   │   ├── RuntimeEventSystem/       # Runtime actors, event bus, SessionRuntime, ZmxBackend
│   │   ├── Actions/                  # WorkspaceActionCommand, WorkspaceCommandResolver, WorkspaceCommandValidator
│   │   └── Views/                    # Tab bar, splits, drawer, arrangement
│   ├── Features/                     # Each feature is self-contained; see
│   │   │                             #   directory_structure.md — Feature Slice Self-Containment
│   │   ├── Terminal/                 # Ghostty C API bridge, SurfaceManager, views
│   │   ├── Bridge/                   # React/WebView pane system (transport, runtime, state)
│   │   ├── Webview/                  # Browser pane (navigation, history)
│   │   ├── CommandBar/               # ⌘P command palette
│   │   ├── RepoExplorer/             # Repo explorer (renamed from Features/Sidebar/ in
│   │   │                             #   LUNA-361; the "sidebar" itself is composition in
│   │   │                             #   App/, not a feature)
│   │   └── <NewFeature>/             # Features/<Feature>/{Components,Models,Routing,
│   │                                 #   State/MainActor/{Atoms,Persistence},Views}/
│   ├── SharedComponents/             # Shared UI primitives (design system). Currently
│   │                                 #   hosts EditorChooser/; more primitives land here
│   │                                 #   over time. Imports only Infrastructure. No atom
│   │                                 #   or global-store access. State flows via @Binding,
│   │                                 #   values, callbacks, or explicit observable view models.
│   └── Infrastructure/               # Domain-agnostic utilities
├── docs/architecture/                # Authoritative design docs (see table above)
├── docs/plans/                       # Date-prefixed implementation plans
├── vendor/ghostty/                   # Git submodule: Ghostty source
└── vendor/zmx/                       # Git submodule: zmx session multiplexer
```

**Import rule:** `App/ → Core/, Features/, Infrastructure/, SharedComponents/` | `Features/ → Core/, Infrastructure/, SharedComponents/` | `Core/ → Infrastructure/` | `SharedComponents/ → Infrastructure/` | Never `Core/ → Features/`, `Features/X → Features/Y`, `SharedComponents/ → Core|Features|App`

**Key config files:** `Package.swift` (SPM manifest), `.mise.toml` (build tasks), `.swift-format`, `.swiftlint.yml`

### Component → Slice Map

Where each key component lives — use this to decide where new files go. Apply the 4 tests from [directory_structure.md](docs/architecture/directory_structure.md): (1) Import test (2) Deletion test (3) Change driver (4) Multiplicity.

| Component | Slice | Role |
|-----------|-------|------|
| `AppDelegate` | `App/Boot/` | App lifecycle, restore, boot sequence |
| `WorkspaceSurfaceCoordinator` | `App/Coordination/` | Cross-store sequencing, action dispatch |
| `WorkspaceSurfaceCoordinator+ActionExecution` | `App/Coordination/` | Action command execution flow |
| `WorkspaceSurfaceCoordinator+FilesystemSource` | `App/Coordination/` | Filesystem root sync for pane runtimes |
| `WorkspaceSurfaceCoordinator+RuntimeDispatch` | `App/Coordination/` | Runtime command dispatch to pane runtimes |
| `WorkspaceSurfaceCoordinator+TerminalPlaceholders` | `App/Coordination/` | Terminal placeholder creation and management |
| `WorkspaceSurfaceCoordinator+Undo` | `App/Coordination/` | Pane close undo support |
| `WorkspaceSurfaceCoordinator+ViewLifecycle` | `App/Coordination/` | NSView lifecycle orchestration for panes |
| `WorkspaceCacheCoordinator` | `App/` | Event bus consumer, updates stores |
| `WorkspaceIdentityAtom` | `Core/State/MainActor/Atoms/` | Workspace id, name, and creation timestamp |
| `WorkspaceWindowMemoryAtom` | `Core/State/MainActor/Atoms/` | Local sidebar width and window frame memory |
| `WorkspaceRepositoryTopologyAtom` | `Core/State/MainActor/Atoms/` | Repos, worktrees, watched paths, availability |
| `WorkspacePaneGraphAtom` | `Core/State/MainActor/Atoms/` | Core pane graph: identity, content (including stored terminal zmx anchors), residency, durable metadata with live facets, drawer membership |
| `WorkspaceDrawerCursorAtom` | `Core/State/MainActor/Atoms/` | Local drawer expansion cursor |
| `WorkspacePaneAtom` | `Core/State/MainActor/Atoms/` | Compatibility mutation facade over pane graph + drawer cursor |
| `WorkspacePaneDerived` | `Core/State/MainActor/Atoms/` | Rich pane read model composed from graph, cursor, topology, and cache facts |
| `WorkspaceTabShellAtom` | `Core/State/MainActor/Atoms/` | Tab shell identity and ordering |
| `WorkspaceTabCursorAtom` | `Core/State/MainActor/Atoms/` | Local active-tab cursor |
| `WorkspaceTabGraphAtom` | `Core/State/MainActor/Atoms/` | Tab membership and arrangement/drawer-view layout graph |
| `WorkspaceArrangementCursorAtom` | `Core/State/MainActor/Atoms/` | Local arrangement focus and drawer-child cursors |
| `WorkspacePanePresentationAtom` | `Core/State/MainActor/Atoms/` | Runtime-only pane presentation overrides |
| `WorkspaceTabArrangementAtom` | `Core/State/MainActor/Atoms/` | Compatibility mutation facade over tab graph, arrangement cursor, and presentation |
| `WorkspaceTabLayoutAtom` | `Core/State/MainActor/Atoms/` | Compatibility tab-layout facade over split tab owners |
| `WorkspaceTabLayoutDerived` | `Core/State/MainActor/Atoms/` | Rich tab read model composed from shell, cursor, graph, arrangement cursor, and presentation |
| `WorkspaceMutationCoordinator` | `Core/State/MainActor/Atoms/` | Cross-atom workspace sequencing for pane + tab layout mutations |
| `RepoEnrichmentCacheAtom` | `Core/State/MainActor/Atoms/` | Derived enrichment (branches, git status, PR counts) and rebuild metadata; notification unread counts are inbox-owned |
| `RecentWorkspaceTargetAtom` | `Core/State/MainActor/Atoms/` | Local recent workspace target history |
| `RepoCacheAtom` | `Core/State/MainActor/Atoms/` | Compatibility read surface over repo enrichment + recent targets; does not own notification unread counts |
| `WorkspaceStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for the workspace-domain atoms |
| `WorkspaceSQLiteDatastore` | `Core/State/SQLite/` | Actor boundary for product SQLite I/O, repository caching, strict core/local composition loading, and commit sequencing |
| `WorkspaceSQLiteSnapshot` | `Core/State/SQLite/` | Immutable live SQLite bridge snapshot passed across the MainActor/datastore boundary; not a legacy JSON DTO or row projection |
| `WorkspaceSQLiteRecoveryClassifier` | `Core/State/SQLite/` | GRDB corruption/not-a-database classifier shared by product SQLite recovery paths |
| `RepoCacheStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for repo enrichment cache + recent workspace targets |
| `UIStateStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for workspace sidebar shell memory only |
| `WorkspaceSettingsStore` | `Core/State/MainActor/Persistence/` | Persistence wrapper for editor bookmark, repo explorer sidebar preferences, and inbox notification preferences until feature-specific settings stores split; checkout colors are intentionally ignored/cleared |
| `SessionRuntime` | `Core/RuntimeEventSystem/Runtime/` | Session backends, health checks, zmx attach orchestration using stored pane anchors |
| `SurfaceManager` | `Features/Terminal/` | Ghostty surface lifecycle, health, undo |
| `WorkspaceCommandResolver` | `Core/Actions/` | Resolves AppCommand into WorkspaceActionCommand, builds ActionStateSnapshot |
| `WorkspaceCommandValidator` | `Core/Actions/` | Validates WorkspaceActionCommand against ActionStateSnapshot |
| `BridgePaneController` | `Features/Bridge/` | WKWebView lifecycle for React panes |
| `RPCRouter` | `Features/Bridge/Transport/` | JSON-RPC dispatch for bridge messages |
| `CommandBarState` | `Features/CommandBar/` | Command palette state machine |

---

## Swift Concurrency

Target: Swift 6.2 / macOS 26. `@MainActor` for all stores, coordinators, and UI mutations.

1. **Isolation first** — `@MainActor` for UI/stores, `actor` for boundary work
2. **`@concurrent nonisolated` for blocking I/O** — In Swift 6.2 (SE-0461), plain `nonisolated async` inherits the caller's actor executor. Without `@concurrent`, blocking I/O called from inside an actor blocks that actor's serial executor. `@concurrent` forces escape to the global concurrent executor. **This is a correctness requirement in 6.2, not a style choice.**
3. **Structured concurrency** preferred; `Task.detached` only when isolation inheritance must be broken
4. **C callback bridging** — capture stable IDs synchronously, never defer pointer dereference across async hops
5. **AsyncStream standard** — `AsyncStream.makeStream(of:)`, explicit buffering policy, always cancel on shutdown

See [EventBus Design — Swift 6.2 concurrency rules](docs/architecture/pane_runtime_eventbus_design.md#swift-62-concurrency-rules-se-0461) for the full gotchas table and threading model.

---

## Running Swift Commands — Detail

**Always use `mise run` for build and test.** Mise tasks handle the WebKit serialized test split, benchmark mode, and build path isolation.

**For filtered test runs:** prefer mise (it allocates a slot for you):
```bash
mise run test -- --filter "CommandBarState"
```
If you must invoke `swift test` directly, source the slot helper first so you don't collide with another agent's build dir:
```bash
source scripts/swift-build-slot.sh
swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarState"
```

| Env Var | Default | Purpose |
|---------|---------|---------|
| `SWIFT_BUILD_DIR` | auto-allocated `.build-agent-1` or `.build-agent-2` via `scripts/swift-build-slot.sh` | Helper claims the first slot whose `.slot-claim` dir doesn't exist (atomic `mkdir`). Local overrides are not supported. |
| `SWIFT_TEST_PARALLEL` | `1` (enabled) | Set to `0` to disable parallel workers |

**Bounded 2-slot pool.** Every swift-running mise task sources `scripts/swift-build-slot.sh`. Debug builds, release builds, and tests all share `.build-agent-1` and `.build-agent-2`. The helper uses an atomic `mkdir <dir>/.slot-claim` to claim a slot; an EXIT trap on the calling shell removes the claim on normal exit. SwiftPM's own kernel-level flock handles serialization within a slot. Main agents and subagents share the pool; the helper handles allocation.

**Concurrent agents land on different slots.** Atomic `mkdir` guarantees that two callers racing simultaneously claim distinct slots. A third caller fails instead of creating another build directory.

**If both slots are busy** the helper aborts with `swift-build-slot: all 2 slots are busy`.

**SIGKILL leaks.** If a calling shell is `kill -9`'d, the EXIT trap doesn't fire and `.slot-claim` is left behind. Run `mise run clean-agent-builds` to reap stale claims (it removes `.slot-claim` from any slot whose `lsof +D` shows no open file descriptors, so it's safe to run while other agents are working).

**Timeouts are mandatory.** `60000` (60s) for test, `30000` (30s) for build. Tests complete in ~15s, builds in ~5s. Anything longer means lock contention.

**Lock recovery:** Do not blanket-kill SwiftPM or `swift-build`; another agent
may own that process. First run `mise run clean-agent-builds` for leaked
`.slot-claim` directories. If SwiftPM still reports an active lock, inspect the
specific owning PID/slot and wait for it or terminate only that confirmed stale
process.

---

## Linear Work Organization

Architecture documents in `docs/architecture/` are the source of truth for design. Linear tickets track progress. Docs answer "how does it work and why." Tickets answer "what's done and what's next."

- **Two levels only:** milestones and tasks. No sub-tasks — checklists in the description.
- **A task is a concept, not an implementation step.** "Dynamic view engine" is a task. "Facet indexer" is a checklist item.
- **Dependencies are first-class.** `blockedBy`/`blocks` relations in Linear.
