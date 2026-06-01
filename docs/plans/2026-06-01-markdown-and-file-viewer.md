# Markdown & file viewer pane — design discussion + implementation plan

> **Status: PROPOSED (2026-06-01).** Branch `claude/add-markdown-viewer-DZdVY`. This document is the discussion record, not a checklist handed down. Each trade-off below is open to revision. The implementation phases at the end depend on the trade-offs sticking.

This rewrite replaces an earlier checklist-shaped draft (commit `c648edf`) that an Opus adversarial review correctly flagged as hiding every decision it made.

---

## What we're building

A pane that opens a file from disk, renders/edits it, and saves it back. v1 is markdown (read + edit, live styling, ⌘S). v2 is the generic open-file pipeline that funnels three entry points — drag-drop, command bar, CLI — through one path. v3, separately, is a diff viewer pane that lives on a real React bundle; nothing in v1/v2 depends on it.

The thread tying v1–v3 together is: **`PaneSource.openFile(URL)`** routed through `ActionResolver` + a pure `FileRendererSelector`, producing a normal `PaneInsertRequest`. Every entry point feeds the same input; the resolver picks the renderer; the inserter places the pane. v3 hangs `.diffViewer` off the same resolver later.

---

## Trade-offs

This is the section the previous draft skipped. Each subsection presents the realistic alternatives, what each costs, and which I'd pick today — *and what would change my mind*. Nothing here is locked.

### 1. Renderer choice

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **`swift-markdown` (Apple)** | Official, AST-only. No UI. | Stable, BSD-style, no maintenance risk. Used by DocC. | We write the entire TextKit 2 live-styling layer ourselves. Editor surface is *all* our code. |
| **`MarkdownUI`** | Pure SwiftUI, read-only. | Easy v1 view. Active. | No editor. Would need a separate edit path. |
| **`Down`** | cmark wrapper. Outputs `NSAttributedString`. | Drops into `NSTextView` cleanly. Mature, 5k stars. | No live styling. No GFM tables. Maintenance is slowing. |
| **`swift-markdown-engine`** | TextKit 2 + SwiftUI wrapper, live styling, GFM, LaTeX, code highlighting. | Closest to "drop in and ship." Editor + viewer in one. | Pre-1.0 (0.5.1), single-team maintainer, unverified inside our pane mount + focus model. |
| **Split: Apple parse + custom `NSTextView`** | `swift-markdown` for AST, hand-written attribute applier + minimal `NSTextView` editor. | Maximum control, zero pre-1.0 risk. The "boring, most likely to ship" path. | A solid week of editor plumbing before anything visible. We'd reinvent live styling. |

**Picked:** swift-markdown-engine for v1, with the v1.0 spike as the kill switch. **What would flip me to the split-with-Apple path:** any of (a) the spike shows the wrapper can't be made focus-clean inside `NSHostingView`, (b) we hit a bug that requires the wrapper's maintainer to fix and they don't respond within a week, (c) the wrapper's API breaks more than once before our v3 ships.

**Pinning policy.** The previous draft said "pin to exact SPM version" without justifying against our `Package.swift` convention (every existing dep uses `.package(url:, from: "x.y.z")` — `swift-async-algorithms`, `swift-distributed-tracing`, `swift-otel`). I want to keep the convention. So: `.package(url:, from: "0.5.1")` and accept that minor bumps may break us. The kill switch above is what makes that survivable. We are *not* using `.exact` — that's a one-off discipline this repo hasn't adopted and shouldn't adopt for one dep.

### 2. `PaneContent` shape

The earlier draft rejected "extend `CodeViewerState`" in a bullet. That dismissal was too quick. Three options actually exist:

**Option A — new `PaneContent.markdownViewer(MarkdownViewerState)` case.** Costs: schema bump `currentVersion: 2 → 3`, plus a new case to handle in every switch on `PaneContent` (grep `case .codeViewer` returned 8+ sites — coordinator view lifecycle, undo, command-bar icon source, bridge runtime capabilities, multiple test files, plus likely focus deciders and trace summary). The forward-compat unknown-case path at `PaneContent.swift:50-58` maps to `.unsupported`, so a v3-saved workspace round-tripping through v2 survives — but worth a regression test.

**Option B — extend `CodeViewerState` with `renderMode: .source | .preview | .split`.** Steelman: same code reads any file, mode flag picks renderer. Tempting because we don't grow the discriminator. Why it loses: `mode: .diff(base, head)` *also* wants to live in this case (per v3), and now `CodeViewerState` carries git refs. That's a coupling — file viewer pane now knows about repos. Also: mode is view state. Persisting "user was looking at the source view of this file" inside `CodeViewerState` means workspace restore boots into source mode even if the user only wanted to skim — and we have no analog for any other content type. Mode belongs in transient UI state, not in `PaneContent`.

**Option C — reuse `bridgePanel` with a markdown route.** Killed by v1's no-React goal. But it's worth raising because v3 *introduces* the bridge. When v3 lands, do we collapse `.markdownViewer` back into `.bridgePanel(.markdown)`? Probably not — by then `.markdownViewer` has its own runtime, its own services, its own tests. Two pane kinds, two implementations, fine. But we should record this so the v3 author doesn't try to "unify" out of tidiness.

**Picked:** A. **What would change my mind:** if the spike finds we have to host swift-markdown-engine in a WKWebView anyway (e.g. for KaTeX rendering it ships via a JS bridge), then `.bridgePanel(.markdown)` becomes the right home and option A becomes wasted scaffolding.

**Schema migration.** v3 isn't optional once we add a new case to a discriminator. The plan ships the bump. Existing workspaces decoded against new code: untouched (no `markdownViewer` in them). New workspaces decoded against old code: `.unsupported(originalCase: "markdownViewer", originalData: ...)`. A regression test for that round-trip belongs in `PaneContentTests.swift`.

### 3. Document state — does `MarkdownDocumentAtom` earn its keep?

CLAUDE.md is blunt: every new atom must justify "one reason to change." If the answer is "this is UI state pretending to be canonical state," it goes on the view.

The single non-negotiable requirement: **two panes open on the same file must share dirty state and the external-change banner.** Without shared state, pane A edits → pane B still shows on-disk → pane A saves → pane B's external-change banner fires because *its* view of the on-disk hash hasn't been told about the save. That's broken UX. The atom is the simplest place to centralize the deduplication.

Without it, alternatives are:
- `@State` on `MarkdownViewerPaneMountView` + per-pane `MarkdownFileService` actor → fails the dirty-state-shared requirement above.
- A `MarkdownFileService` singleton that holds the map and exposes async streams → equivalent to the atom but loses the `@Observable` / `AtomReader` integration the rest of the app uses.

**Picked:** atom, feature-scoped in `Features/MarkdownViewer/State/MainActor/Atoms/`. One-sentence job: *holds the in-memory editor buffer, dirty flag, and last-known on-disk content hash for each open markdown file, keyed by canonicalized URL*. One reason to change: a file's editor state.

**Why feature-scoped, not Core.** Once v2 ships and `.txt`/`.swift` can also be opened, every file viewer wants this same atom. At that point we promote to `Core/State/MainActor/Atoms/OpenDocumentAtom.swift` or similar. Documenting the future migration up front so the v2 author knows it's coming.

**No persistence.** Dirty buffers are session-local. If the app quits with unsaved edits, we lose them. (See §"Undo" cross-cutting below for what we owe the user about that.)

### 4. Save model

**Decision recap from the earlier round:** explicit ⌘S with dirty indicator. That decision still holds. What the earlier draft missed: ⌘S is *how* the user triggers the save, but the routing question — which command plane carries it — is its own decision the plan asserted in one line.

Three options for the routing:

**A. `PaneActionCommand.saveActivePaneDocument(paneId:)`.** Goes through `ActionValidator` (confirms pane exists and is a markdown viewer) and `ActionResolver` (no-op pass-through). Slots into the existing command plane. Familiar shape.

**B. `LocalActionSpec.saveActivePane`.** Per CLAUDE.md, `LocalActionSpec` is for *UI-only* actions. Saving a file to disk is not UI-only — it crosses the persistence boundary. Wrong plane.

**C. Direct call from `PaneTabViewController` ⌘S handler into `MarkdownDocumentAtom.flush(url:)`.** Bypasses both planes. Justifiable because the action is pane-local and doesn't change workspace shape. But it sets a precedent that pane-local mutations skip the command plane, which we'd regret the next time we want to undo a save or log a save event.

**Picked:** A. The earlier draft had B; that was wrong. A new `PaneActionCommand` case is the right plane because it crosses a persistence boundary, and we get free validation that the pane is in the right state to be saved.

**Autosave was rejected because:** explicit ⌘S lets us show a dirty indicator that the user can act on; autosave races with our external-change detection (banner says "file changed" but it was *our* save that changed it); and it removes the "diff before clobber" affordance once v3 lands. Cost of explicit ⌘S: users with web-editor muscle memory will lose work on quit. We mitigate by prompting on app-quit-with-dirty-buffers (see §"Process model"). Not free.

### 5. `FileRendererSelector` — where it lives, how it extends

Three open sub-decisions:

**Location.** A pure classifier `(URL) -> RendererKind`. The earlier draft put it in `Core/Actions/` reasoning that resolver consumes it. But `Core/Actions/` is "things that mutate workspace shape." A classifier is a model concern. **Picked:** `Core/Models/FileRendererSelector.swift`. The resolver imports it; that's allowed.

**Extension map vs configurable.** v1 ships a hard-coded extension map:
- `md, markdown, mdown, mkd` → `.markdown`
- everything else, deferred to v2 → `.unsupported` (v1 doesn't claim non-markdown extensions)

When v2 extends `.code` for `.swift / .ts / .json / ...`, the same selector grows that branch. When *eventually* a user wants to override — open `README.md` as code, treat `.foo` as markdown — the override layer plugs in between selector output and resolver consumption. Concretely: `RendererKind`-returning function gets a sibling `UserRendererOverrides` (in `UIStateAtom`, per-workspace) that the resolver consults *first*. We don't ship the override layer in v1; we record the shape so v2 doesn't paint into a corner.

**Why isn't `.txt` (or `.swift`, or `.go`) a `.markdownViewer` with rendering disabled?** Tempting, because swift-markdown-engine *is* an `NSTextView`. The answer: rendering "disabled" means we'd push every visual feature behind a toggle and that toggle would have to be persistent or session-state somewhere. Cleaner: `.codeViewer` stays its own pane kind with its own (eventually syntax-highlighted) view, `.markdownViewer` stays its own. They share a `FileRendererSelector` and a v2-promoted `OpenDocumentAtom`. They don't share view code.

---

## Edges and shape problems

A walkthrough of v1 as a user, finding every awkward seam. Most of these need a one-line policy decision before the v1.0 spike runs.

### Same file in two panes

The atom shares state. So:
- Pane A edits → pane B's editor view (reading the same `DocumentRecord`) re-renders with A's changes mid-keystroke.

  That's surprising. The user typing in B sees their cursor jump. **Policy:** if a file is open in pane A and the user tries to open it in pane B, **focus pane A instead of creating B**. This is the "focus existing" behavior the resolver already needs. Cross-pane duplication of the same file is forbidden for v1. We revisit in v2 if there's a real use case (e.g. compare-with-itself for diffs).

### File deleted while open

`MarkdownFileService.read(url:)` fails. The editor still has its buffer. **Policy:** show a non-modal banner ("This file no longer exists on disk. Save to restore it, or close to discard."). ⌘S in this state calls `write(url:)` which recreates the file. Closing the pane discards the buffer.

### File renamed externally

`URL` is path-based. The pane's `filePath` becomes stale silently. Detecting rename properly needs filesystem-event watching (the same `FilesystemActor` that drives repo events). **v1 policy:** treat rename as delete (banner fires on next external-change poll). v2 hooks into `FilesystemActor` events to follow the rename automatically. Recording the gap.

### Encoding

We're going to assume UTF-8. Real markdown files include UTF-16-with-BOM (Windows), Latin-1 (old wiki exports), and the occasional mixed-encoding file. **Policy:** `MarkdownFileService` sniffs BOM, falls back to UTF-8, and surfaces a one-time banner ("Opened as UTF-8 — non-UTF-8 characters may be replaced") if the decoder reports invalid sequences. The actual encoding chosen lives on `DocumentRecord` (in-memory) — not persisted on `MarkdownViewerState`. If the user closes and reopens, we re-sniff.

### Symlinks, network mounts, no-read-permission, `.git/` internals, hidden files

- **Symlinks:** open the resolved path. Use `URL.resolvingSymlinksInPath()` for canonicalization in the atom's keying so symlink and target dedupe correctly.
- **Network mounts:** read is allowed but writes may hang. `MarkdownFileService.write` runs `@concurrent nonisolated`. ⌘S surfaces a non-blocking spinner; if the write takes >2s, banner ("Saving to network volume…").
- **No-read-permission:** read fails; pane opens with an error placeholder and a "Re-try" button.
- **`.git/` internals:** allowed by default. Power-user behavior. If we want to block, that's a `FileRendererSelector` policy, not a hard refusal at the file service.
- **Hidden files:** allowed. Drag-drop and `NSOpenPanel` already surface them or don't per user preference.

### Huge single-line file

The 5 MiB byte cap doesn't protect TextKit 2 from a 4.9 MiB file all on one line. **Policy:** `ActionValidator` adds a secondary check: file passes if `byteCount < 5 MiB` AND (`hasNewlinesAtReasonableInterval` OR `byteCount < 100 KiB`). The "reasonable interval" check reads the first 64 KiB and confirms at least one newline. If both fail, we offer a "View as plain text (read-only)" path that uses an `NSTextView` with `allowsRichText = false` — no live styling, no TextKit 2 line-wrap pathologies.

### Cold-start race: CLI before `applicationDidFinishLaunching`

`open -a AgentStudio README.md` against a not-yet-running app delivers the URL to `application(_:open:)` *before* `applicationDidFinishLaunching` completes — meaning the atom registry, command dispatcher, and pane coordinator may not exist yet. **Policy:** `AppDelegate` queues incoming URLs in a pre-boot buffer; `applicationDidFinishLaunching` drains the buffer at the end, after the coordinator is wired. This is standard macOS handling but it's not free — we have to write the queue.

### CLI opens a file already open elsewhere

Two windows, two workspaces. The "focus existing" behavior is scoped to the active workspace. **Policy:** search every workspace for a pane matching the canonicalized URL. If found, focus that workspace's window + tab + pane. If not, the active workspace gets the new pane. Recording: this requires the resolver to consult `WorkspaceMetadataAtom` and walk every workspace's panes — modest cost, fine.

### Drag-drop from outside the workspace's repo

User drops `/Users/me/Downloads/foo.md` into a workspace pointed at `~/proj`. **Policy:** allowed. The pane records the absolute URL; it's not tied to the workspace's repo topology. On workspace restore, we attempt to reopen the URL; if it's gone (Downloads cleared), the pane decodes as `.unsupported` and the user sees "file not found" — same as any other stale path.

### Drag-drop a directory of `.md` files

Earlier draft said "ignored with a log line." Reviewer correctly called that terrible UX. **Policy:** if a directory is dropped, open the first `.md` file inside it (one level deep, alphabetical), or do nothing if none. Future: open all into a new tab. Picking minimum-surprise behavior for v1.

---

## Cross-cutting concerns (raised, partly unresolved)

### Process model, sandbox, entitlements

The app is currently **unsandboxed** (no `.entitlements` file in the repo, no entitlements section in `Package.swift` or the bundle script). v1 / v2 ship under that assumption. Future sandboxing (for Mac App Store, or just security hygiene) requires:
- `com.apple.security.files.user-selected.read-write` — covers `NSOpenPanel` and drag-drop bookmarks
- Security-scoped bookmarks for any URL we persist across launches (e.g. the markdownViewer pane's `filePath` after restore)
- `application(_:open:)` paths arrive with implicit access — but only for the launch event, not for re-reads

**Documenting this as a known future migration**, not in scope for v1/v2. v3's Bridge React bundle adds its own entitlement surface (network for hot-reload, etc.) — separate concern.

### Undo across editor + pane-close

swift-markdown-engine ships its own `NSTextView`-based undo (⌘Z undoes typing). Our pane-close undo (`PaneCoordinator+Undo.swift`) restores closed panes from a TTL'd stash. Three failure modes:

1. **Pane closed with unsaved edits.** v1 policy: prompt to save before close (NSAlert: Save / Discard / Cancel). Standard editor behavior. No clever undo-stash-the-buffer logic.
2. **Pane reopened from close-undo.** The buffer is gone (we discarded or saved). Reopening reads from disk — clean state. Good.
3. **Within-editor undo.** Lives entirely inside swift-markdown-engine. Does not interact with our coordinator. ⌘Z when editor has focus = editor undo; ⌘Z when no editor has focus = pane-close undo. Resolution by first-responder.

### Find / replace conflict on ⌘F

`AppDelegate.swift:685` hard-binds ⌘F to `TerminalPaneMountView.startSearch(_:)`. When focus is on a markdown editor, ⌘F should go to *its* search, not the terminal's. **Policy:** add a v1.6 task to refactor ⌘F into the command plane: a `LocalActionSpec.findInActivePane` resolved by the active pane's runtime. swift-markdown-engine: does it ship a find UI? Confirm in the spike. If not, fall back to NSTextView's built-in `performFindPanelAction(_:)`. If neither works, document as known v1.7 gap.

### Cross-workspace open (raised in §Edges, resolved there)

### Encoding sniffing (raised in §Edges, resolved there)

---

## Folder layout

The earlier draft invented `Features/MarkdownViewer/Services/`. CLAUDE.md's feature-slice spec lists `Components, Models, Routing, State/MainActor/{Atoms,Persistence}, Views` — no `Services/`. Three places `MarkdownFileService` could live:

| Location | Argument | Verdict |
|---|---|---|
| `Features/MarkdownViewer/State/MainActor/Persistence/MarkdownFileService.swift` | Persistence "persists" by writing to disk. | Stretches the convention — Persistence in CLAUDE.md is store-shaped, not free file I/O. |
| `Infrastructure/FileIO/MarkdownFileService.swift` | Domain-agnostic file read/write. | Honest. But "markdown" in the name leaks domain into Infrastructure. |
| `Infrastructure/FileIO/TextFileService.swift` | Reusable for v2's `.code` viewer too. | Picked. |

**Picked:** `Infrastructure/FileIO/TextFileService.swift`, generic over file kind. Markdown viewer holds an instance. v2's code viewer reuses it.

---

## Risks (ranked)

| Rank | Risk | Surfaces in | Cost if it hits |
|---|---|---|---|
| 1 | swift-markdown-engine focus/keyboard integration | v1.0 spike, day 1 | Whole renderer choice flips to split (Apple parse + custom NSTextView). +1 week. |
| 2 | TextKit 2 perf on long-line files | v1.3, first real file test | Need fallback path + secondary validator check. +2 days. |
| 3 | Cold-start race in `application(_:open:)` | v2.4, first CLI invocation against cold app | Need pre-boot queue. +1 day. |
| 4 | PaneContent schema bump regression | v1.1, in CI on persisted-workspace fixture | Need explicit forward-compat test. +0.5 day. |
| 5 | Same-file-two-panes state machine | v1.3, QA on second-open attempt | Resolver "focus existing" path. +0.5 day (the alternative is bug land). |
| 6 | Find / replace not shipping in the editor | v1.6 | Add NSTextView fallback. +1 day. |
| 7 | swift-markdown-engine API churn on minor bumps | Whenever maintainer ships 0.6.0 | Pin + bump deliberately. Cost depends on size of change. |
| 8 | `diffs.com` not actually being a real package | v3.0 | Fall back to `react-diff-view`. +0.5 day. |
| 9 | Vite codesign / notarization | v3.1 | Tracer-bullet PR before any feature code. +3 days. |
| 10 | Sandbox future-migration | n/a in v1/v2; future | Whole security-scoped-bookmark layer. +1 week, deferred. |

Ranking is "what bites first in dev order," not "highest impact." Risk 1 is the kill-switch for the renderer choice; risks 9–10 are far away.

---

## Implementation phases

The phasing remains v1 (markdown pane) → v2 (open-file entry points) → v3 (diff viewer on React bundle). Below is a lighter checklist than the previous draft — the bulk of design lives in the trade-off sections above.

### v1.0 Spike (1–2 hr, blocks everything)

Throwaway branch. Add `swift-markdown-engine` to `Package.swift` via `from: "0.5.1"`. Instantiate `NativeTextViewWrapper` in `NSHostingView`, mount through `PaneMountedContent`. Verify: first-responder hand-off, `WorkspaceFocusDerived.activePaneId`, `KeyboardOwnerDerived`, ⌘P still opens, ⌘W still closes the pane, no retain cycle (Allocations). Test ⌘F behavior with a markdown pane focused. If any failure: document, switch to the split-renderer path in §Renderer choice, restart v1.1.

### v1.1 Pane model

- New `case markdownViewer(MarkdownViewerState)` in `Core/Models/PaneContent.swift`. Bump `currentVersion: 2 → 3`. Add `ContentType.markdownViewer` raw value.
- `Features/MarkdownViewer/Models/MarkdownViewerState.swift` — just `{ filePath: URL }`.
- Cover the new case in every grep'd `case .codeViewer` site. Grep returned 8+ — verify the full set first.
- Test: forward-compat round-trip (v3 case decoded by v2 → `.unsupported`).

### v1.2 Document atom + file service

- `Infrastructure/FileIO/TextFileService.swift` — actor, `@concurrent nonisolated` read/write, BOM sniffing, hash computation.
- `Features/MarkdownViewer/State/MainActor/Atoms/MarkdownDocumentAtom.swift` — `@MainActor @Observable`, keyed by `URL.resolvingSymlinksInPath()`.
- Register in `Sources/AgentStudio/AtomRegistry.swift`.
- Tests: open/dirty/save/reload state machine. Injected clock. No `Task.sleep`.

### v1.3 View

- `Features/MarkdownViewer/Views/MarkdownViewerPaneMountView.swift` — `NSView`, hosts `NativeTextViewWrapper`, subscribes to atom row.
- Dirty indicator on the tab title (reuse existing tab-title rendering).
- External-change banner state machine: idle → detected (poll on focus + every 5s when focused) → reload / keep-mine. v3 enables a "diff" button on the banner.

### v1.4 Save (⌘S)

- New `PaneActionCommand.saveActivePaneDocument(paneId: UUID)` (the routing decision from §4).
- `ActionValidator` confirms pane is a `.markdownViewer`.
- `ActionResolver` builds it from a `LocalActionSpec`-style ⌘S trigger via `PaneTabViewController`.
- Handler invokes `MarkdownDocumentAtom.flush(url:)` which calls `TextFileService.write(...)`.

### v1.5 Find (v1 stretch)

Confirm swift-markdown-engine ships a find UI. If yes, hook to ⌘F via a `LocalActionSpec.findInActivePane`. If no, refactor `AppDelegate.swift:685` ⌘F binding into the command plane and route to per-pane handlers.

### v1.6 Tests

- `PaneContentTests`: `.markdownViewer` encode/decode roundtrip; forward-compat with v2.
- `MarkdownDocumentAtomTests`: state machine.
- `TextFileServiceTests`: BOM sniffing, hash detection.
- `ActionValidatorTests`: 5 MiB cap, long-line check.

---

### v2.1 PaneSource + selector

- Add `case openFile(URL)` to `PaneSource` (in `Core/Actions/PaneActionCommand.swift` — that's where it lives, not `Core/Models/`).
- New `Core/Models/FileRendererSelector.swift` — extension map. Sibling: `Core/Models/RendererKind.swift`.
- `ActionResolver`: handle `openFile` by classifying, then producing `PaneInsertRequest` with the correct `PaneContent`. Pre-check: "focus existing pane with same URL in any workspace" (the cross-workspace policy from §Edges).
- `ActionValidator`: URL exists, not a directory, not oversized, passes long-line check.

### v2.2 Drag-drop

Drag-drop overlays already exist (`SplitContainerDropCaptureOverlay`, `DrawerSplitContainerDropCaptureOverlay`, `DraggableTabBarHostingView`) — all register internal pasteboard types. Extending them to also accept `NSPasteboard.PasteboardType.fileURL` is the right hook, NOT registering on the window content view. Plan:

- Add `.fileURL` to `SplitContainerDropCaptureOverlay.supportedPasteboardTypes`.
- In the overlay's drop handler, branch on payload type: existing internal types → existing path; file URLs → build `PaneInsertRequest` from `PaneSource.openFile`.
- Dropping on tab bar opens in a new tab (same branch in `DraggableTabBarHostingView`).
- No "replace pane contents" target.

### v2.3 Command bar

- New `CommandSpec` in `Features/CommandBar/Data/CommandBarDataSource.swift` for "Open File…". Action: `NSOpenPanel`, dispatch `openFile(url)`.
- Bind ⌘O via `AppShortcut`.

### v2.4 CLI

- Add `application(_:open:)` to `AppDelegate.swift`. Implement the pre-boot queue from §Edges/cold-start.
- `Info.plist` — wait, the repo has no `Info.plist` yet. SwiftPM-built apps get one synthesized; if we need `CFBundleDocumentTypes`, we add a custom `Info.plist` and reference it. Plan task: confirm with `.mise.toml` build path whether `create-app-bundle` accepts a custom plist.
- Document type registrations: `public.plain-text`, `net.daringfireball.markdown`, source-code UTIs. `LSHandlerRank = Alternate`.
- Optional `Scripts/agentstudio` shell shim: `exec open -a AgentStudio "$@"`. Defer if mise surface is contentious.

### v2.5 Tests

`FileRendererSelectorTests` (extension matrix), `ActionResolverTests` (openFile happy path + focus-existing), `ActionValidatorTests` (size cap, directory, missing), `AppDelegateOpenFilesTests` (pre-boot queue replay).

---

### v3 — Diff viewer (separate later milestone)

Discussion deferred. The v3 trade-offs (which diff library, React bundle codesign, hot-reload pattern, source maps in WKWebView) need their own discussion document when v3 starts. Sketch from the earlier draft kept as reference:

- v3.0: verify `diffs.com` package exists, license check, 30-line spike. Fall back to `react-diff-view` (MIT) if not.
- v3.1: stand up `frontend/` workspace, Vite, bundle into Swift resources, replace `BridgeSchemeHandler` stub, solve codesign + hot-reload + source maps.
- v3.2: new `PaneContent.diffViewer` case, `Features/DiffViewer/` slice, Bridge runtime, wire `DiffMethods.swift` to `GitProjector`.
- v3.3: enable "diff" button on the markdown external-change banner.

---

## Open questions after this draft

These are the things I'm not confident about yet. None block v1.0 (the spike), but they need answers before v1 ships:

1. **Same-file-two-panes: is "focus existing" right, or do power users want compare-with-self?** The plan picks focus-existing. Revisit if a user objects.
2. **Long-line validator gate: is 100 KiB the right threshold below which we don't sniff for newlines?** Picked arbitrarily. Real test data would refine it.
3. **External-change polling cadence: 5s while focused is a guess.** Filesystem events via the `FilesystemActor` would be cleaner — gated on whether `FilesystemActor` can be told to watch arbitrary paths outside repo roots.
4. **Find / replace in the editor.** Confirmed in the v1.0 spike. If it's missing, v1.5 ships an NSTextView-based fallback.
5. **Cross-workspace open implementation cost.** Need to walk every workspace's panes — `WorkspaceMetadataAtom` exposes the list, but the cost of iterating all open documents is small. Confirm in v2.1.
6. **`Info.plist` in a SwiftPM-built app bundle.** v2.4 task: is there a precedent in the repo? Probably not.
7. **`agentstudio` shell shim install path.** `/usr/local/bin` requires sudo. `~/.local/bin` may not be on `PATH`. Deferring is fine.
