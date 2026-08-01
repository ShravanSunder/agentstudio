# Bridge and View Regression Sidekick Ledger

## Relationship

- Agent: `bridge_view_bug_tracker`
- Pattern: Sidekick
- Assignment ID: `bridge-view-regression-ledger-2026-07-29`
- Continuity reason: maintain one persistent, ordered inventory while the user reports additional UI regressions
- Host/runtime/provider: Codex / native / Codex
- Model category: Frontier
- Parent conversation history: all
- Permission boundary: production/tests/runtime are read-only; this ledger is the only write
- Working scope: Bridge and pane/view regressions reported after `v0.0.67`
- Source version: `ad975f98c4bc75f021b651269fdbdb03d10c2c81`
- Receipt expected: assignment-bound inventory updates with evidence status and unresolved questions
- Parent verification: reproduce each item and validate code-path claims before accepting a diagnosis or fix

## Bug Inventory

### BVR-001 — Large empty gap above the bottom drawer/Bridge surface

- Evidence: user screenshots captured 2026-07-29.
- Expected: the bottom drawer/Bridge surface begins at the intended split boundary without an unallocated vertical band.
- Actual: a large empty dark band appears between pane content/identity chrome and the bottom surface; the split boundary or content placement appears displaced.
- Reproduction: not yet independently reproduced.
- Scope clarification: the issue occurs only in Zoom mode.
- Impact: visible Zoom-layout regression affecting the drawer/Bridge presentation shown in the screenshots.
- Root cause: `ad975f98` inserted `ManagementPaneIdentityStrip` as a separate row after the complete Zoom `SplitView`; the row reserves height beneath both source and companion even though only the source has identity content.
- Test gap: existing coverage asserts only that the identity accessibility element exists, not its frame or the unused companion-side geometry.
- Fix: `ManagementPaneIdentityStrip` now lives inside the Zoom source column rather than beneath the complete Zoom `SplitView`.
- Proof:
  - red geometry reproduced identity `maxX = 632` crossing companion `minX = 224`;
  - the focused geometry suite is now 15/15 green;
  - fresh current-branch proof with `mise run test -- --filter ZoomPresentationContainerGeometryTests` built the current Swift sources and passed 1 suite / 1 test.
- Status: fixed with fresh current-branch automated proof green; current-build native visual proof has not been rerun.

### BVR-002 — Bridge Review/File context does not retarget when pane CWD changes

- Evidence: user report on 2026-07-29.
- Expected: when a pane's live CWD changes, Bridge Review mode and File mode retarget to the current CWD/resolved worktree directory.
- Actual: Bridge Review mode and File mode continue using the prior CWD/worktree directory.
- Reproduction: not yet independently reproduced.
- Scope clarification: this is an older design issue rather than a regression introduced by `v0.0.67`.
- Relationship: this is the behavioral form of the previously reported stale pane location/worktree context.
- Impact: Bridge shows repository/file/review content for a stale location after terminal navigation.
- Root cause boundary:
  - live terminal CWD correctly updates the source pane atom and resolved repo/worktree;
  - the existing retained Zoom companion is not automatically reconciled or retargeted;
  - Review and File authorities remain bound to the context captured when the companion controller was created.
- Current ownership map:
  1. Surface-manager CWD events and runtime terminal `cwdChanged` events converge in `WorkspaceSurfaceCoordinator.updatePaneCWDAndResolvedContext`.
  2. The coordinator resolves the containing repo/worktree, atomically updates the source pane's CWD plus repo/worktree facets, and refreshes its filesystem-projection context.
  3. That mutation path does not reconcile a retained Zoom companion or update a mounted Bridge controller.
  4. An ordinary Bridge pane captures the resolved worktree at creation: its `BridgePaneSource.workspace.rootPath` and launch directory are the worktree root, while its metadata CWD is the source pane's CWD at that moment.
  5. The Bridge controller then constructs its Review provider and File authority once. Review prioritizes the workspace source root over metadata CWD; File binds an authority to the captured worktree root and currently publishes `cwdScope = nil`.
  6. Reusing an ordinary Bridge pane changes the active Review/File surface but does not replace its captured source, runtime metadata, or product authority.
  7. A Zoom companion likewise captures the source worktree root and source-pane CWD at creation. Its retained-companion identity records only the resolved worktree id.
  8. Explicit Zoom reconciliation retires a retained companion whose source pane now resolves to a different worktree, but the live CWD mutation path does not invoke that reconciliation. A same-worktree subdirectory change passes the retained-worktree-id check unchanged.
- Existing contract seam: File metadata already accepts an optional `cwdScope`, but the current native authority always returns `nil`; Review has no equivalent subtree-scope contract and remains a worktree-root Git comparison.
- Previously accepted source-resolution contract:
  1. resolve the deepest registered worktree containing the pane's live CWD;
  2. if a registered worktree matches, bind both Files and Review to that worktree;
  3. if no registered worktree matches, make both surfaces unavailable with `Not in a watched worktree`;
  4. remove stale companion content rather than leaving the previous worktree visible;
  5. preserve the selected Files/Review mode so it resumes when a watched worktree becomes available again.
- Scope semantics:
  - CWD is resolver input, not Bridge source identity;
  - Bridge Viewer remains registered-worktree-owned;
  - no arbitrary filesystem browsing, unregistered Git discovery, path-derived identities, or Files-only raw-CWD authority belongs in this fix.
- Verified resolution primitive:
  - `RepositoryTopologyAtom.repoAndWorktree(containing:)` already provides synchronous longest-path-first lookup, so the deepest containing registered worktree wins without a new resolver or asynchronous work.
- Superseded dead end:
  - the attempted `.filesystemRoot` / `sourceKind` expansion generalized native and web transport contracts, File construction ownership, fixtures, providers, and tests;
  - it also introduced an App-owned Git parent-ascent resolver plus task-generation and cancellation state;
  - that direction was rejected because it changed Bridge's authority model to solve a watched-worktree retargeting problem;
  - all filesystem-root, Git-discovery, synthetic-identity, and resolver-task changes must be removed rather than completed.
- Accepted implementation contract:
  - the pragmatic solution is the registered-worktree model described above;
  - the pane's live CWD is resolver input, while the deepest registered containing worktree remains the source identity and authority;
  - when no registered worktree contains the live CWD, both Files and Review show `Not in a watched worktree`;
  - no arbitrary filesystem authority, Git parent discovery, or synthetic source identity is permitted;
  - preserve the selected Files/Review mode and hidden/visible companion state across registered retargeting and temporary unavailability.
- Required proof:
  - registered worktree A to registered worktree B retargets both surfaces;
  - registered worktree to unwatched CWD clears stale content and shows the unavailable state;
  - unwatched CWD to registered worktree restores the selected surface;
  - hidden/visible companion state and selected Files/Review mode survive registered retargeting;
  - an unrelated sole registered worktree is never borrowed;
  - tests use event/state waits, never wall-clock sleeps.
- Status: implementation contract accepted; current production and test changes must be reviewed against this exact registered-worktree-only boundary.

### BVR-003 — File search toggle disappears and cannot cancel an empty search

- Evidence: user screenshot captured 2026-07-29.
- Expected behavior:
  - Search remains a coherent toggle with an obvious path into and out of search mode.
  - An empty search can be cancelled without first typing text.
  - The revealed search field uses balanced spacing consistent with Bridge Viewer chrome.
- Actual behavior:
  - activating Search removes the Search toggle;
  - with no query text, the user cannot exit/cancel search;
  - the search field has little or no top separation while retaining lateral gaps, producing inconsistent insets.
- Scope: Bridge File Viewer search state and chrome.
- Fix:
  - Search remains a persistent `aria-pressed` toggle while search mode is active;
  - closing Search clears the active query;
  - the field uses uniform `m-2` spacing.
- Proof:
  - focused browser tests are 59/59 green;
  - fresh current-branch File query browser proof passed 1 file / 3 tests;
  - full Bridge browser integration passed 21 files / 124 tests, with 1 file / 5 tests skipped.
- Status: fixed with fresh focused and full-browser automated proof green; current-build native visual proof has not been rerun.

### BVR-004 — Review remains indefinitely in “Projecting review”

- Evidence: user screenshot captured 2026-07-29.
- Expected behavior: switching/opening Review progresses from projection/loading to rendered review content or an actionable error state.
- Actual behavior: Review does not load and remains indefinitely in the “Projecting review” skeleton.
- Additional trigger evidence: the user reproduced the same stuck Review in another worktree, outside Zoom mode, after rapidly scrolling the File tree.
- Reproduction boundary: cross-worktree and non-Zoom; the durable Review wedge is not owned by Zoom layout or presentation state.
- Trigger classification: rapid File-tree scrolling is a reproducible trigger candidate, not yet a proven root cause.
- Severity: highest in the current inventory; Review is unusable.
- Relationship: cross-worktree, non-Zoom reproduction and the rapid-scroll trigger make Zoom presentation state, a single stale source, or one repository's data less likely; keep separate from BVR-002 unless later evidence joins them.
- Exact visible-state ingress:
  - `BridgeReviewViewerMode` selects `projectionPending` only after Review source metadata is no longer absent/loading/failed but `bridgeReviewPresentationSnapshotForDisplay` returns `null`.
  - the presentation adapter returns `null` when a non-empty source reports positive item/tree totals but the main display store has no ordered Review items or no tree rows.
  - therefore the screenshot is not a per-file body-demand loading state. It is a split-brain display state: a presentable Review source exists while its item/tree catalog is incomplete or absent.
- High-confidence missing terminal path:
  1. `ensureReviewMetadata` increments the Review worker-derivation epoch for every reopened subscription.
  2. a Review subscription/application failure with a retained active projection calls `handleMetadataFailure`, which publishes only the retained source patch with status `stale`.
  3. the main display store treats any higher-epoch Review display event as a full derivation replacement and clears the existing source, items, ordering, and tree before applying that event.
  4. because the higher-epoch stale publication contains only `reviewSource`, the retained source is reinstalled but the item/tree catalog remains empty.
  5. the presentation adapter consequently returns `null`, and the UI remains in `Projecting review`; no timeout or terminal error transition owns this state.
- Rapid-scroll relationship:
  - a File viewport command updates only File metadata demand; it does not directly reset Review projection state.
  - File and Review nevertheless share one product metadata stream. Any subscription-frame rejection poisons every subscription on that stream.
  - the stream poison path fails all subscriptions but leaves the transport's memoized metadata-ready promise installed, so reopening a subscription does not itself reopen the dead metadata stream.
  - this makes rapid File demand a plausible pressure trigger for a shared-stream failure, including native producer queue overflow, but the exact runtime failure code from the user's reproduction is not yet observed. Treat rapid scrolling and queue overflow as correlated hypotheses, not yet the proven first cause.
- Proven durable wedge:
  - the transport retains its memoized metadata-stream readiness after the shared stream is poisoned, so later subscription recovery does not establish a new physical stream;
  - the resulting higher-epoch Review failure publishes only the retained stale source, while the main display store clears the prior item/tree catalog as part of epoch replacement;
  - positive retained source totals plus the now-empty catalog leave the presentation adapter returning no presentation indefinitely.
- Implementation status:
  - Review metadata publication now replaces the full retained catalog when the worker derivation epoch changes, preventing a higher-epoch source-only event from clearing the item/tree catalog;
  - a failed physical metadata stream now clears the memoized readiness promise, so a later Review subscription establishes a new physical stream before reopening;
  - the main display/presentation adapter has coverage proving a complete stale catalog at the new epoch remains presentable.
- Mental-model break:
  - the shared recovery path currently cannot distinguish a logical subscription reset or application failure from physical metadata-stream poison;
  - a logical reset terminates only one subscription while the controller abandons an uncancelled sibling subscription;
  - the retry guard re-arms before a replacement subscription has applied successfully;
  - pending File discovery can outlive a failed replacement and continue against superseded recovery state;
  - therefore the current recovery changes do not establish a coherent production ownership or sequencing contract.
- Automated proof:
  - focused recovery unit command passed 3 files / 24 tests;
  - Review browser integration passed 1 file / 14 tests;
  - full Bridge browser integration passed 21 files / 124 tests, with 1 file / 5 tests skipped;
  - Node integration passed 8 files / 51 tests;
  - E2E passed 1 file / 3 tests;
  - `pnpm --dir=BridgeWeb run check` exited 0 with the existing warning baseline;
  - the latest full BridgeWeb unit run passed 229 files and 1,608 tests, with exactly 2 failures remaining;
  - both remaining failures are downstream expectations owned by the frozen BVR-004 recovery design: the Review retained-catalog epoch and the File clear epoch;
  - full `mise run lint` passed with 0 violations across 1,879 Swift files plus architecture lint;
  - the entry test's stale count was replaced with an exact request-correlated wait; it now passes 11/11 and observes exactly one physical replacement stream;
  - the temporary source-size failure was fixed by moving a pure unavailable-transport test helper into the existing entry-test support while retaining worker `postMessage` ownership in the entry test;
  - focused entry and source-structure proof passed 2 files / 35 tests;
  - targeted oxlint for the newly edited files reports no new warning; the navigation-helper warning at `bridge-file-viewer-query-lifecycle.browser.test.tsx:334` is pre-existing.
- Current native evidence:
  - the current debug build launched as `Agent Studio Debug 3dkh` PID `71770`, and its fresh Victoria marker verified;
  - a current-build screenshot proves Files Viewer renders;
  - this evidence proves launch, observability identity, and Files rendering only, not the rapid-scroll → Review recovery path.
- Proof boundary:
  - the automated tests prove individual catalog-republication and stream-replacement cases, but do not validate the unresolved production recovery ownership and sequencing model;
  - they do not prove the complete native rapid File-scroll/demand-pressure → shared-stream failure → Review switch/reopen → hydrated presentation sequence;
  - required manual/runtime proof remains: rapidly scroll the File tree in the native app, then open or switch to Review and confirm it leaves `Projecting review` with a hydrated item/tree presentation;
  - Peekaboo full AX `see` and bounded `inspect-ui` timed out on the large workspace, and background AX interaction could not target the custom WebKit file-tree content;
  - all stuck Peekaboo client processes were terminated without touching the foreground, which remained Brave;
  - the current PID `71770` was launched without debug-token escrow or unsafe no-auth, so a new external IPC client cannot authenticate; the running server has no supported token-reissue path;
  - authenticated `bridge.diff.load` would open a new Review tab rather than switch the existing Files pane;
  - IPC does not expose the existing internal `requestViewerSurface(.review)` same-pane transition;
  - IPC also exposes no File-tree scroll or viewport-demand command, so it cannot reproduce the rapid-scroll trigger;
  - no rapid-scroll → same-pane Review native proof was completed; the exact proof must wait for an addressable interaction path.
- Ranked hypotheses:
  1. source-only retained-active failure publication crosses a Review epoch and atomically clears the catalog — high confidence for the observed indefinite UI state;
  2. rapid File demand trips a shared metadata-stream failure, possibly native producer queue overflow, before the Review epoch wedge — medium confidence, missing the live failure diagnostic;
  3. a no-match Review projection filter emits positive source totals with zero projected items/tree — valid independent `Projecting review` bug, but low confidence for this screenshot because no active filter is visible;
  4. lazy Review-shell chunk loading never resolves — low confidence and unsupported by the cross-worktree/scroll evidence.
- Live-log boundary: the fresh Victoria marker verifies the current debug process and observability path, but without a completed rapid-scroll reproduction it cannot confirm the initiating transport failure code.
- Status: production recovery is frozen pending design concurrence on logical-reset versus physical-stream-poison ownership, sibling cancellation, retry re-arming, and pending-discovery lifetime; this lane is not ready or green. The current-build Files rendering receipt remains valid, while native rapid-scroll → same-pane Review recovery and the initiating failure diagnostic remain outstanding.

### BVR-005 — Files and Review filters are inconsistent and selections do not affect rows

- Evidence: two user screenshots captured 2026-07-29 plus the user's interaction report.
- Visible inconsistency:
  - Files presents a single-column `Filter by file class` popup with `All files`, `Text files`, and `Unavailable files`;
  - Review presents a two-column `Filter review files` popup with `Git Status` and `File Type`.
- Reported functional failure: filter selections do not work; the exact failing selection, state transition, and displayed-row result have not yet been independently reproduced.
- Agreed requirements:
  - when Files and Review controls have matching interaction semantics, they must share semantics and visual scale rather than presenting unrelated control behavior;
  - selecting a supported filter must actually affect the rows displayed by the owning surface;
  - when Bridge Files owns focus, Command-Shift-F toggles the Files Search control;
  - when Bridge Review owns focus, Command-Shift-F toggles the Review Search control;
  - both Command-Shift-F paths use the same Search open/close behavior, including closing an empty search;
  - when Bridge Files or Review owns focus, Command-Option-F toggles that surface's Filters popup;
  - opening Filters moves keyboard focus into the popup;
  - Up/Down navigates filter choices, Return selects the focused choice, and Escape closes the popup;
  - pressing Command-Option-F again closes the open Filters popup;
  - Review is the visual and interaction reference and retains both `Git Status` and `File Type`;
  - Files uses the same Base UI menu surface, width, header/section styling, icons and badges, checkmarks, active indicator, clear row, and keyboard behavior as Review;
  - Files exposes only `File Type`; it must not expose Review-only Git status values such as added, modified, renamed, or deleted;
  - Files uses the same `Source`, `Test`, `Docs`, `Config`, `Generated`, `Vendor`, `Large`, `Fixture`, and `Unknown` taxonomy and icons as Review, replacing `All files`, `Text files`, and `Unavailable files`;
  - every category exposed by Files must be produced by the native classifier and actually filter the displayed rows; any category that cannot be truthfully produced and made functional must be removed.
- Taxonomy hard cut:
  - the development frame schema requires the canonical nine-value Files `fileClass`;
  - the frame adapter propagates `fileClass` into the metadata-backed Files rows;
  - the development provider classifies path and size through the native taxonomy, with no `Binary` value and no default masking;
  - no duplicate TypeScript taxonomy or legacy availability-category compatibility path is permitted.
- Verified source diagnosis:
  - Files currently filters `all | fetchable | unavailable`, so its categories are availability states rather than the Review File Type taxonomy;
  - the File query projection implements those availability predicates, which explains why the existing menu can affect rows but cannot provide the requested category semantics;
  - Files tree metadata carries path and size but no `fileClass`; the native classifier is currently used only by Review;
  - `source`, `test`, `docs`, `config`, `generated`, `vendor`, `large`, `fixture`, and `unknown` are derivable from the existing Files path and size metadata through the native classifier;
  - `binary` is not knowable at the Files tree-filter boundary because binary detection currently happens only during on-demand content scanning;
  - adding a binary probe to every tree row would expand Files tree materialization I/O and is not part of this fix, so Files must omit `Binary` rather than expose a category it cannot classify truthfully;
  - Review may retain `Binary` because its source path supplies a real binary fact.
- Keyboard-proof diagnosis:
  - the original failing canary was defective rather than evidence of a production keyboard-navigation failure;
  - `document.activeElement` was the `role=menu` popup, whose aggregate descendant text created a false positive and prevented the helper from sending `ArrowDown`;
  - the corrected proof observes the Base UI `data-highlighted` state directly;
  - after `ArrowDown`, focus transfers to the highlighted menu item;
  - after `Return`, the selected item's `aria-checked` state and the visible filtered row projection both update.
- Automated proof:
  - combined Files and Review keyboard canaries passed 2 files / 17 tests, covering repeated Command-Option-F toggle, Base UI Escape dismissal, ArrowDown focus transfer, Return selection, and Search shortcuts;
  - focused development frame, adapter, and provider suites passed 3 files / 24 tests;
  - BridgeWeb typecheck passed;
  - the Files Browser Mode query lifecycle selected all nine categories against metadata-backed rows and passed 3/3 tests;
  - changed BridgeWeb unit files passed 18/18 files and 112/112 tests;
  - the full Files browser suite passed 56/56 tests;
  - the full non-stress browser integration passed 21 files with 1 skipped and 124 tests with 5 skipped;
  - `pnpm --dir BridgeWeb run check` exited 0 with no errors; the existing warning baseline remains;
  - the stale Clear expectation was reconciled as a hard cutover, and its file passed 5/5 tests.
- Design boundary: do not add Git Status to Files or duplicate Review's native classification logic in TypeScript.
- Status: automated keyboard, unit, Files browser, non-stress browser-integration, and BridgeWeb check proof is green; the truthful nine-category Files taxonomy remains `Source`, `Test`, `Docs`, `Config`, `Generated`, `Vendor`, `Large`, `Fixture`, and `Unknown`, with no `Binary`; native/manual completion remains outstanding.

### BVR-006 — Terminal Command-F Search opens but its controls and interactions are broken

- Evidence: user report captured 2026-07-29.
- Actual behavior:
  - Command-F opens the Terminal Search surface;
  - controls and interactions within the open Search surface are broken.
- Expected at the currently agreed level: Command-F continues to open Terminal Search, and the surfaced controls and interactions function correctly.
- Scope: Terminal Search; this is independent from the Bridge Files/Review Search and Filters requirements in BVR-005.
- Verified diagnosis:
  - showing the overlay did not move the window's first responder into the search field, so the field had no active AppKit editor and typed input remained outside the Search control;
  - the search field used target/action wiring for query changes, which did not deliver live text edits to the Ghostty search action.
- Fix:
  - focus the search field immediately after the mounted overlay is retained;
  - use `NSSearchFieldDelegate.controlTextDidChange` to deliver each edited query to the existing Search action.
- Automated proof:
  - red run: 8 tests produced 3 issues from the missing field editor/focus and absent query delivery;
  - green run: the same 8 tests passed with 0 failures after the focus and delegate-delivery changes.
  - expanded green run: 9 tests in 1 suite passed, including actual AppKit Previous, Next, and Close button target/action delivery.
- Proof boundary:
  - native/manual proof of the complete Command-F, typing, navigation-button, and close-button interaction remains outstanding.
- Execution boundary: preserve exactly the existing focused AppKit tests with no further test expansion; native/manual proof remains pending, and no foreground interaction is allowed.
- Status: root cause and focused AppKit automated proof are green; native/manual completion remains pending.

## Agent Status

- Runtime identity: `/root/bridge_view_bug_tracker`
- Status: BVR-006 remains bounded to its existing focused AppKit proof with native/manual proof pending and no foreground interaction; BVR-005 automated taxonomy, keyboard, unit, Files browser, non-stress integration, and BridgeWeb check proof is green while preserving the canonical nine-category Files taxonomy without `Binary`; BVR-004 production recovery is frozen after a mental-model break and is not ready or green, with exactly two downstream full-unit expectation failures remaining in its retained-catalog and File-clear epoch contracts; fresh current-branch automated proof remains green for BVR-001 and BVR-003; BVR-002 uses the accepted registered-worktree-only contract.
- Queued work: obtain design concurrence before resuming BVR-004 production recovery; complete BVR-005 native/manual proof without broadening its taxonomy; retain BVR-006's no-foreground boundary; independently review BVR-002 against the accepted boundary.
- Last prompt: continue implementation, ensure every exposed filter category is real and functional, and remove categories that cannot be truthfully produced.
- Last checked: 2026-07-29.
- Next follow-up: obtain BVR-004 design concurrence before production recovery resumes, complete BVR-005 native/manual proof, and leave BVR-006 native proof pending until foreground interaction is explicitly allowed.
