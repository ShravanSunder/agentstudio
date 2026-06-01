# Markdown & file viewer pane — implementation plan

> **Status: PROPOSED (2026-06-01).** Branch `claude/add-markdown-viewer-DZdVY`. Plan rewritten after adversarial Opus review of an earlier sketch.

## Goal

Add a markdown editor/viewer pane plus a generalized "open a file into a pane" pipeline. v1 ships a native Swift editor with live preview (no React bundle). v2 wires three open-file entry points (drag-drop, command bar, CLI). v3 — separately, later — adds a diff viewer pane on a real React bundle.

## Decisions

| Decision | Choice | Notes |
|----------|--------|-------|
| Markdown renderer | `nodes-app/swift-markdown-engine` (Apache 2.0, pre-1.0) | TextKit 2 + SwiftUI wrapper, live styling, GFM, LaTeX, code highlighting. Pin to exact SPM version. |
| Editor or viewer | Editor with live preview | Single pane handles read + edit |
| Save model | Explicit ⌘S with dirty indicator on the tab | No autosave; reload on external change with a banner |
| Pane shape | New `PaneContent.markdownViewer(MarkdownViewerState)` case | Leave `codeViewer` untouched |
| Open-file command | Extend `PaneSource` with `case openFile(URL)` → normal `insertPaneRequest` | Do NOT add a top-level `PaneActionCommand.openFile` |
| Renderer selection | Pure `FileRendererSelector` in `Core/Actions/` consumed by `ActionResolver` | Validator only checks file exists + size cap |
| CLI | `NSApplicationDelegate.application(_:open:)` + Info.plist UTI registration | Optional `agentstudio` shell shim wraps `open -a`. No second SPM target, no NSDistributedNotificationCenter |
| Diff viewer | Separate later milestone with its own React bundle | Verify `diffs.com` package exists first; fall back to `react-diff-view` (MIT) |

## What we rejected

- **Extending `CodeViewerState` to carry render/diff modes.** Multi-mode union pollutes 5+ switch sites (`PaneContent`, icons, focus, undo, persistence) and requires a schema migration with no v2 fallback. Sibling pane kinds are cleaner.
- **Deleting `CodeViewerPaneMountView`.** It's instantiated at `PaneCoordinator+ViewLifecycle.swift:118` and covered by `Tests/.../CodeViewerPaneMountViewTests.swift` + `PaneContentTests.swift` + `RuntimeRegistryTests.swift`. Out of scope.
- **A new `CodeViewerRuntime`.** `BridgeRuntime.swift:169` already maps `.codeViewer` → `[.editorActions]`, and a `SwiftPaneRuntime` is already registered. Don't duplicate.
- **`PaneActionCommand.openFile` as a new top-level command.** Every pane-creation path today goes through `insertPaneRequest(PaneInsertRequest)`. Adding a parallel command bypasses target-resolution machinery.
- **Putting extension→renderer logic in `ActionValidator`.** Validator validates, doesn't decide. Logic moves to `ActionResolver` via a pure selector.
- **CLI via `NSDistributedNotificationCenter`.** Sandbox-hostile, unreliable on modern macOS, requires a second binary in `Package.swift`. `application(_:open:)` + Info.plist is the standard pattern.
- **Drag-drop "replace pane contents" target.** `DropTargetResolver` only models `.paneSlot / .paneSplit / .paneNewRow`. A drop always creates a new pane.

---

## v1 — Markdown editor/viewer pane

### v1.0 Spike (1–2 hr, do this first)

- [ ] **Verify swift-markdown-engine integrates with our pane mount + focus.** Throwaway branch off v1. Add SPM dep, instantiate `NativeTextViewWrapper` inside an `NSHostingView`, push it through `PaneMountedContent`. Check:
  - First-responder hand-off (does the editor steal `WorkspaceFocusDerived.activePaneId`?)
  - Keyboard owner tracking (does `KeyboardOwnerDerived` see the editor when focused?)
  - Command-bar `⌘P` still opens when editor has focus
  - `⌘W` close-pane still works
  - No retain cycle when the pane closes (instrument with Allocations)
- [ ] If any of the above fail, document the workaround in this plan before continuing.

### v1.1 Pane model + state

- [ ] Add `Features/MarkdownViewer/` slice (CLAUDE.md feature-slice rules).
- [ ] `Features/MarkdownViewer/Models/MarkdownViewerState.swift`:
  ```swift
  struct MarkdownViewerState: Hashable, Codable {
      var filePath: URL
      // schemaVersion handled by PaneContent
  }
  ```
  No scroll position, no dirty flag, no editor settings — those are view-local, not persisted in the pane content.
- [ ] Add `case markdownViewer(MarkdownViewerState)` to `Core/Models/PaneContent.swift`. Bump `PaneContent.currentVersion` if required by the schema; provide forward-compatible decoding (unknown case → `.unsupported`, following the existing pattern).
- [ ] Wire `ContentType.markdownViewer` discriminator with matching `rawValue` for persistence.
- [ ] Cover the new case in every existing switch:
  - `Sources/AgentStudio/Features/CommandBar/Data/CommandBarDataSource.swift` (icon — propose `.system(.docTextBelowRectangle)` or similar)
  - `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` (createViewForContent)
  - `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
  - `Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift` (capabilities — propose `[.editorActions]`)
  - Any `WorkspacePaneFocus` / focus deciders that switch on content type (grep `case .codeViewer`)

### v1.2 Document atom (open files, dirty state, conflicts)

- [ ] `Features/MarkdownViewer/State/MainActor/Atoms/MarkdownDocumentAtom.swift`:
  - `@MainActor @Observable`, `private(set)` reads, mutation via methods
  - Tracks `[URL: DocumentRecord]` where `DocumentRecord` holds last-known-on-disk content hash, in-memory editor content, dirty flag
  - Methods: `open(url:)`, `markDirty(url:)`, `markClean(url:)`, `reload(url:)`, `close(url:)`
  - No disk I/O in the atom — file reads/writes live in a `MarkdownFileService` actor
- [ ] `Features/MarkdownViewer/Services/MarkdownFileService.swift` — `actor`, reads/writes via `FileManager`, computes content hash. `@concurrent nonisolated` on the read/write methods (Swift 6.2 SE-0461).
- [ ] Register atom in `Sources/AgentStudio/AtomRegistry.swift`.
- [ ] **Not persisted.** Open-document state is session-local. Persisted pane state is just `filePath`.

### v1.3 View

- [ ] `Features/MarkdownViewer/Views/MarkdownViewerPaneMountView.swift`:
  - `NSView` conforming `PaneMountedContent`
  - Hosts `NativeTextViewWrapper` inside `NSHostingView`
  - Subscribes (via `AtomReader`) to its row in `MarkdownDocumentAtom` for content + dirty flag
  - Plumbs editor text changes back through the atom's mutation methods
- [ ] Dirty indicator surfaced on the tab. Reuse whatever tab-title rendering exists (`Core/Views/...TabBar...`). Append `•` or color the title.
- [ ] External-change detection: when `MarkdownDocumentAtom` notices the on-disk hash drifted, post a transient banner in the pane ("File changed on disk — reload / keep mine / diff"). v1 ships only "reload" and "keep mine"; diff button stays disabled until v3.

### v1.4 Save command (⌘S)

- [ ] New `LocalActionSpec.saveActivePane` in `Core/Models/LocalActionSpec.swift` (UI-only action — doesn't mutate workspace state, doesn't need PaneActionCommand routing).
- [ ] Bind `⌘S` via `AppShortcut`. Route through `PaneTabViewController` (per CLAUDE.md commands+shortcuts doc — pane-scoped actions go through it).
- [ ] Handler asks `MarkdownDocumentAtom` to flush the active pane's document via `MarkdownFileService.write(...)`.
- [ ] No-op (silent) when active pane isn't a markdown viewer.

### v1.5 Tests

- [ ] `PaneContentTests`: roundtrip `markdownViewer` encode/decode, v1 → v1 happy path, unknown-case → `.unsupported` decode.
- [ ] `MarkdownDocumentAtomTests`: open/dirty/save/reload state machine. Use `swift-async-algorithms` + a fake clock; **no `Task.sleep`** (CLAUDE.md no-wall-clock rule).
- [ ] `MarkdownFileServiceTests`: write-then-read roundtrip, hash detection of external change. Use a tmp dir; clean up in suite teardown.
- [ ] No view-level tests for `MarkdownViewerPaneMountView` in v1 (the swift-markdown-engine wrapper is the SUT, not our code). Revisit after v1 ships.

---

## v2 — Open-file entry points

All three surfaces funnel into the same resolver path.

### v2.1 Source + selector

- [ ] Add `case openFile(URL)` to `Core/Models/PaneSource.swift`.
- [ ] New `Core/Actions/FileRendererSelector.swift` — pure function `(URL) -> RendererKind` where `RendererKind = .markdown | .code | .unsupported`. Switch on `URL.pathExtension`:
  - `md`, `markdown`, `mdown`, `mkd` → `.markdown`
  - everything else with text-y UTI → `.code`
  - else → `.unsupported`
- [ ] Extend `Core/Actions/ActionResolver.swift` to handle `PaneSource.openFile`: call selector, build a `PaneInsertRequest` with the appropriate `PaneContent` (markdownViewer or codeViewer). Existing target-resolution (which tab, which split direction) reused as-is.
- [ ] Extend `Core/Actions/ActionValidator.swift` to validate `openFile`:
  - URL exists
  - Not a directory
  - Size under cap (propose `AppPolicies.maxOpenFileBytes` = 5 MiB, configurable later)
  - Returns `.unsupported` placeholder if oversized — don't silently drop
- [ ] **Focus-existing-pane behavior.** If a pane with the same `filePath` is already open in the active workspace, resolver returns a "focus existing" plan instead of building a new `PaneInsertRequest`. Add this to the resolver, not as a new command.

### v2.2 Drag-drop

- [ ] Register `NSPasteboard.PasteboardType.fileURL` at the window content view (`App/Windows/MainWindowController.swift`), NOT inside `DropTargetResolver`.
- [ ] On `performDragOperation(_:)`:
  - Translate cursor location to a `DropTarget` via the existing resolver
  - For each file URL on the pasteboard, dispatch a `PaneActionCommand.insertPaneRequest` built from `PaneSource.openFile(url)`
- [ ] Drops on the tab bar open in a new tab. Drops on a pane split it. No "replace content" target.
- [ ] Test: drag-drop a `.md` file → markdown pane appears in the expected split; drag-drop a `.swift` → code pane appears; drag-drop a directory → ignored with a log line.

### v2.3 Command bar

- [ ] New `CommandSpec` in `Features/CommandBar/Data/CommandBarDataSource.swift` for "Open File…":
  - Title `Open File…`, icon `.system(.docBadgePlus)` or similar
  - Action: presents `NSOpenPanel` (single file, files only), dispatches `PaneSource.openFile(url)`
- [ ] Bind to `⌘O` via `AppShortcut` (verify no conflict — currently free per `AppShortcut.swift`).

### v2.4 CLI

- [ ] Add `application(_:open:)` to `App/Boot/AppDelegate.swift`. For each `URL`, dispatch `PaneSource.openFile(url)`.
- [ ] `Resources/Info.plist`: add `CFBundleDocumentTypes` for `public.plain-text`, `net.daringfireball.markdown`, and the source-code UTIs we want to handle. `LSHandlerRank = Alternate` so we don't claim defaults.
- [ ] Optional `Scripts/agentstudio` shell shim (3 lines): `exec open -a AgentStudio "$@"`. Install via a new `mise run install-cli` task that symlinks into `/usr/local/bin/agentstudio`. Defer if mise task surface is contentious.
- [ ] Test: `open -a AgentStudio README.md` from a fresh shell launches/raises the app and opens the file.

### v2.5 Tests

- [ ] `FileRendererSelectorTests`: extension matrix.
- [ ] `ActionResolverTests`: `PaneSource.openFile` → correct `PaneInsertRequest`. "Already open" path returns focus plan.
- [ ] `ActionValidatorTests`: size cap, directory rejection, missing file.
- [ ] `AppDelegateOpenFilesTests`: `application(_:open:)` dispatches the expected command (use a fake dispatcher).

---

## v3 — Diff viewer pane (separate later milestone)

**Do not start until v1 and v2 ship.** This phase is the one that needs the React bundle.

### v3.0 Verify the dependency exists

- [ ] Confirm `diffs.com`'s package name on npm. Read its license. Build a 30-line standalone Vite spike that imports `CodeView` / `PatchDiff` and renders a hardcoded diff. If anything is unverifiable (no public npm, paid license, missing API), fall back to `react-diff-view` (MIT, well-maintained).

### v3.1 Frontend bundle (tracer-bullet PR)

- [ ] New `frontend/` workspace: Vite + React + TypeScript. Single page that renders "hello from the bridge". Deps: `react`, `react-dom`, `react-markdown` (for v3.2), the chosen diff library.
- [ ] New `mise run frontend-build` task. Wire into `mise run setup` and `mise run build`.
- [ ] Add bundle output to `Package.swift` `resources:` for the `AgentStudio` target.
- [ ] Replace the Phase-1 stub in `Features/Bridge/Transport/BridgeSchemeHandler.swift` with real asset resolution from the SwiftPM resource bundle.
- [ ] Dev hot-reload: scheme handler proxies to `localhost:5173` when `AGENTSTUDIO_BRIDGE_DEV=1`. Production reads from the bundle.
- [ ] WebKit Inspector + source maps: verify `WKPreferences.developerExtrasEnabled` and `WKWebpagePreferences` are set in `BridgePaneController` in debug builds.
- [ ] Codesign: confirm `mise run create-app-bundle` signs the new bundled JS/CSS/font files. Run the full notarization dry-run.

### v3.2 Diff viewer pane

- [ ] Add `case diffViewer(DiffViewerState)` to `PaneContent`. State: `filePath`, `baseRef`, `headRef`, view mode (inline | split).
- [ ] `Features/DiffViewer/` slice with view backed by `BridgePaneController` pointed at `agentstudio://app/diff.html`.
- [ ] Wire existing `Features/Bridge/Transport/Methods/DiffMethods.swift` (`diff.requestFileContents`, `diff.loadDiff`) to `GitProjector` for real content.
- [ ] Right-click on a markdown pane → "Show diff against `main`" / arbitrary ref picker. Routes through a new `PaneSource.openDiff(filePath, baseRef, headRef)`.

### v3.3 Markdown → diff link

- [ ] The "File changed on disk" banner from v1.3 gets its "diff" button enabled — opens a diff viewer pane next to the markdown pane.

---

## Risks

- **swift-markdown-engine API churn (pre-1.0).** Pin exact version, budget bumps as small PRs. If the wrapper API changes incompatibly before we ship, fork temporarily.
- **swift-markdown-engine focus/keyboard ownership.** Mitigated by v1.0 spike. If the spike reveals fundamental incompatibility, we fall back to `NSAttributedString(markdown:)` + a custom NSTextView (smaller scope, no live styling).
- **`diffs.com` may not exist as a real package.** Mitigated by v3.0 verification before any frontend work starts. Fallback is `react-diff-view`.
- **Vite bundle codesign / notarization** (v3.1). Highest-risk piece of the whole plan. Stays in its own tracer-bullet PR before any diff feature code.
- **Info.plist UTI registration may conflict with user's existing default app.** Use `LSHandlerRank = Alternate`. Document the behavior in user-facing release notes.

## Files touched (estimate)

**v1:** ~10 new files in `Features/MarkdownViewer/`, ~6 modified (`PaneContent.swift`, `AtomRegistry.swift`, `PaneCoordinator+ViewLifecycle.swift`, `BridgeRuntime.swift`, `CommandBarDataSource.swift`, `Package.swift`).

**v2:** ~3 new (`FileRendererSelector.swift`, CLI shim if shipped, tests), ~5 modified (`PaneSource.swift`, `ActionResolver.swift`, `ActionValidator.swift`, `AppDelegate.swift`, `MainWindowController.swift`, `Info.plist`).

**v3:** entire `frontend/` workspace + ~8 new Swift files in `Features/DiffViewer/`, modified `Package.swift`, `.mise.toml`, `BridgeSchemeHandler.swift`, `DiffMethods.swift`.
