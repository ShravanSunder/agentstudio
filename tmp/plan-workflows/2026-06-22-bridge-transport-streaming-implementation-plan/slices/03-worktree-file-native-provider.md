# 03 Worktree/File Native Provider Boundary

## Ticket Output

Create the host/provider boundary for the Worktree/File Surface as a first-class
application protocol. This ticket does not need to build the full browser UI.

Deliverable:

- provider-issued `WorktreeFileSurfaceSourceIdentity`
- `worktree.snapshot` host frame with tree/status descriptors
- earliest-authoritative `treeSizeFacts` on snapshot and tree-window frames
  carrying exact row count or conservative estimated total extent before tree row
  bodies hydrate
- file descriptors with content handles and attached content descriptors
- file descriptors with explicit virtualization facts:
  `virtualizedExtentKind`, plus `lineCount` or
  `estimatedContentHeightPixels` before file content bytes are fetched or
  streamed
- provider-owned filesystem/watch and git-status classification seams
- invalidation and reset decisions
- binary/oversized metadata decisions
- source-scrubbed extent-diagnostics schema or fixture for ticket 04 canary
  reuse
- native proof that Worktree/File does not instantiate Review package lineage

## Source References

- `worktree-file-surface-protocol.md` sections 1-8
- `worktree-file-surface-protocol.md` section 10 tree windowing
- `worktree-file-surface-protocol.md` section 14 proof expectations
- `plan-review-report.md` B5 and I4
- current `BridgeReviewPipeline.swift` `browseTree`/`openFile` Review-shaped
  behavior

## Write Scope

Swift:

- `Sources/AgentStudio/Features/Bridge/Models/WorktreeFileSurface/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/**`
- transition edits to existing Review-shaped browse/open-file seams:
  `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewQuery.swift`
  and
  `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewPipeline.swift`
  only as needed to stop treating Worktree/File provider authority as Review
  query authority
- focused tests under `Tests/AgentStudioTests/Features/Bridge/**`

Browser:

- Shared fixtures only if Swift/TS frame parity requires them.
- No full browser UI surface in this ticket.

Do not remove ReviewFoundation browse/open-file paths until ticket 04 proves the
replacement browser/dev-server route.

## Red Tests First

- Worktree source request is a selector; provider mints source identity.
- Worktree snapshot carries source identity and attached tree/status
  descriptors.
- Worktree snapshot and tree-window frames expose `treeSizeFacts` with exact
  row count or conservative estimated total extent before any browser hydration,
  content-byte fetch, content stream, or DOM measurement dependency.
- File descriptor carries file id, content handle, size, binary flag, optional
  hash, and attached content descriptor.
- Every file descriptor exposes explicit `virtualizedExtentKind`; unknown extent
  is labeled, not inferred.
- Text file descriptors expose exact `lineCount` when cheaply known, otherwise a
  conservative `estimatedContentHeightPixels`; `unavailable` is reserved for
  binary, oversized, unreadable, or metadata-only content where the provider
  cannot trust either exact or estimated extent.
- Extent facts remain metadata when body content is stale, preview-only, binary,
  oversized, or unavailable.
- Provider extent diagnostics emit only allowlisted fields and reject raw path,
  source text, handle ids, capability URLs, comments, and comms seeds.
- Provider selector/canonicalization and scheme-handler rejection errors expose
  only allowlisted reason codes and grammar-safe metadata, never raw path/cwd
  scopes, handle ids, capability URLs, or unsanitized provider error text.
- Invalidation carries path/file/content-handle facts without replacing open
  browser content by default.
- Source reset revokes old descriptors and stale completions cannot commit.
- Binary file and oversized file produce metadata-only or preview-limited
  descriptors.
- Native browse/open-file proof uses Worktree/File source identity, not
  `BridgeReviewPackage`.
- Browser-supplied `pathScope`, `cwdScope`, path hints, symlinks, traversal
  attempts, and root tokens are canonicalized and containment-checked by the
  provider before any file authority or descriptor is issued.
- If transition edits touch existing ReviewFoundation browse/open-file seams,
  legacy browse/open-file behavior remains covered until ticket 04 replaces the
  browser/dev-server route.
- Disabled comments/comms flags remain unsupported/fail-closed.

## Implementation Notes

1. Add Swift Worktree/File transport models.
2. Add provider protocol for source identity, tree windows, status, file
   descriptors, invalidations, and resets.
3. Map existing filesystem/git capabilities behind Worktree/File provider
   seams instead of Review query kinds.
4. Add provider-side selector canonicalization and containment checks before
   tree/file/status descriptors are issued.
5. Publish tree/file virtualized-size facts from provider/materializer frames,
   not from browser measurement or hydrated body streams.
6. Add source-scrubbed extent diagnostics fixture/schema for ticket 04 browser
   canary reuse.
7. Add frame builder and method registration for opening a Worktree/File source.
8. Keep compatibility with old Review-shaped browse/open-file until ticket 04
   replaces the user-facing route.

## Proof Gates

Swift focused:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceNativeTests|BridgeReviewPipelineTests|BridgeSchemeHandlerTests|BridgeTransportIntegrationTests'
```

Current native transport entry proof adds:

- `BridgeWorktreeFileSurfaceTransportTests`
- `WorktreeFileSurfaceMethods.OpenSourceStreamMethod`
- `BridgePaneController+WorktreeFileSurface`

The focused Ticket 03 Swift gate should include the transport test:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 \
SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceNativeTests|BridgeWorktreeFileSurfaceTransportTests|BridgeReviewPipelineTests|BridgeSchemeHandlerTests|BridgeTransportIntegrationTests'
```

Proof captured 2026-06-23:

- red: `BridgeWorktreeFileSurfaceTransportTests` failed because the
  `worktreeFileSurface.openSourceStream` RPC response had no `result`
- green: same focused test passed with 1 selected test after native method
  registration, host-owned worktree authority resolution, descriptor lease
  registration, and off-main exact tree path count
- gate: focused Ticket 03 Swift command above passed with 83 selected tests in
  6 suites
- quality: `mise run lint` passed; swift-format OK, SwiftLint 0 violations,
  architecture lint OK, release script checks passed
- browser quality: `pnpm --dir BridgeWeb run check` passed; oxlint
  type-aware, BridgeWeb architecture check, oxfmt, and `tsc --noEmit` all
  passed
- fixtures: `bash scripts/bridge-web-sync-fixtures.sh --check` passed with 17
  files in sync

Review-fix proof captured 2026-06-23 after current implementation review:

- accepted/fixed: file-scoped `pathScope` returned `treeSizeFacts.pathCount`
  `0`; direct file scopes now report exact count `1`
- accepted/fixed: Worktree/File tree/status descriptor leases survived source
  reopen; `openSourceStream` now resets pane-scoped `worktree-file` leases
  before registering the next generation
- accepted/fixed: teardown now synchronously revokes Worktree/File authority and
  asynchronously clears remaining `worktree-file` leases
- accepted/fixed: blank selector authority fields are rejected during
  `BridgeWorktreeFileSurfaceSourceSpec` decode
- accepted/fixed: readable text `estimatedHeight` file descriptors now have a
  positive contract test
- red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests'`
  exited 1 before fixes with 7 issues across blank selector decode,
  file-scope count, and stale lease survival
- green:
  same command exited 0 after fixes with 27 tests in 3 suites passing
- changed-file lint:
  `swiftlint lint --strict <six changed Swift files>` exited 0 with 0
  violations
- quality:
  `mise run lint` exited 0; swift-format OK, SwiftLint 0 violations,
  architecture lint OK, release script verification passed
- diff hygiene: `git diff --check` exited 0

Resource body-serving proof captured 2026-06-23:

- accepted/fixed: Worktree/File descriptors were parseable and leased but
  `BridgeSchemeHandler` rejected every non-Review `agentstudio://resource/...`
  request before bytes
- added `BridgeWorktreeFileResourceStore` under
  `Runtime/WorktreeFileSurface` so Worktree/File resource bodies are
  app-protocol-owned instead of routed through Review `BridgeContentStore`
- `BridgeSchemeHandler` now routes leased `worktree-file` resources through the
  Worktree/File resource store while preserving the same lease, revocation, and
  max-byte checks around response and body emission
- `BridgePaneController` now passes the Worktree/File store into its
  per-pane scheme handler and registers fetchable `worktree.treeWindow` and
  `worktree.status` JSON bodies for `worktree.snapshot` descriptors
- lifecycle cleanup resets Worktree/File bodies on source reopen and teardown;
  stale bodies are not authority without a current native lease
- red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeSchemeHandlerWorktreeFileResourceTests`
  exited 1 before implementation because `BridgeWorktreeFileResourceStore` and
  the scheme-handler injection point did not exist
- green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeSchemeHandlerWorktreeFileResourceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests'`
  exited 0 with 29 tests in 4 suites passing
- changed-file lint:
  `swiftlint lint --strict <six changed Swift files>` exited 0 with 0
  violations
- diff hygiene: `git diff --check` exited 0

Initial file descriptor/content proof captured 2026-06-23:

- accepted/fixed: `includeFileDescriptors` no longer stops at selector
  validation; file-scoped `openSourceStream` now materializes an initial
  provider-owned `worktree.fileDescriptor` frame for selected file scopes
- `RPCRouter` now exposes a post-success-response callback; `BridgePaneController`
  uses it to flush pending Worktree/File intake frames only after the
  `openSourceStream` JSON-RPC response has been emitted, preserving snapshot
  before-delta ordering
- added `BridgeWorktreeFileMaterializer` to compute provider-owned content
  handles, content descriptors, exact text line counts, language/extension facts,
  and bounded file-content bodies without routing Worktree/File bytes through
  Review content stores
- file content descriptors are leased and registered in
  `BridgeWorktreeFileResourceStore`; the scheme handler can fetch
  `worktree.fileContent` bodies through native lease authority
- red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTransportTests`
  exited 1 before fixes with compile/test failures around the new
  post-response descriptor proof scaffolding
- green:
  same command exited 0 with 3 tests in 1 suite passing
- green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeSchemeHandlerWorktreeFileResourceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests'`
  exited 0 with 30 tests in 4 suites passing
- changed-file lint:
  `swiftlint lint --strict <five changed Swift files>` exited 0 with 0
  violations
- diff hygiene: `git diff --check` exited 0

Live source/status/invalidation proof captured 2026-06-23:

- accepted/fixed: `openSourceStream` now retains the active Worktree/File
  source identity, stream id, and next sequence after the initial snapshot and
  optional file-descriptor frames
- `BridgePaneController.publishWorktreeFileSurfaceStatus` emits
  `worktree.statusPatch` frames for the current generation only
- `BridgePaneController.publishWorktreeFileSurfaceChangeset` emits
  `worktree.fileInvalidated` frames for user-file changes, filters `.git`
  internals from file invalidation delivery, and can emit a status
  invalidation when the changeset only touches git internals
- live frames are dispatched through the same native intake envelope path as
  post-response file descriptors, preserving monotonic stream sequence numbers
- green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTransportTests`
  exited 0 with 4 tests in 1 suite passing
- green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeSchemeHandlerWorktreeFileResourceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSurfaceNativeTests'`
  exited 0 with 35 tests in 5 suites passing
- changed-file lint:
  `swiftlint lint --strict <three changed Swift files>` exited 0 with 0
  violations

Live reset/descriptor replacement proof captured 2026-06-23:

- accepted/fixed: `BridgePaneController.publishWorktreeFileSurfaceReset` now
  emits a live `worktree.reset` frame for the current generation, clears active
  source state, drops pending Worktree/File intake frames, revokes pane-scoped
  `worktree-file` leases, and resets the Worktree/File resource store before
  stale updates can publish
- accepted/fixed: live `worktree.fileInvalidated` frames can now carry a
  `latestDescriptor` for changed regular files, including a replacement content
  descriptor, exact text line count, content handle, native resource lease, and
  fetchable `worktree.fileContent` bytes through `BridgeSchemeHandler`
- changed-file materialization filters `.git` internals before descriptor
  creation; non-regular changed paths still invalidate by path without
  replacement content authority
- red:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter BridgeWorktreeFileSurfaceTransportTests`
  exited 1 before implementation because `publishWorktreeFileSurfaceReset` did
  not exist and the invalidation path did not materialize replacement
  descriptors
- green:
  same command exited 0 with 6 tests in 1 suite passing
- green:
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeSchemeHandlerWorktreeFileResourceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSurfaceNativeTests'`
  exited 0 with 37 tests in 5 suites passing
- changed-file lint:
  `swiftlint lint --strict <five changed Swift files>` exited 0 with 0
  violations
- diff hygiene:
  `git diff --check` exited 0
- workflow log:
  `events.jsonl` validated as JSONL with 52 lines after the proof event
- quality:
  `mise run lint` exited 0; swift-format OK, SwiftLint 0 violations,
  architecture lint OK, release script verification passed

Focused suites should include or add:

- `BridgeWorktreeFileSurfaceTests`
- `BridgeWorktreeFileSourceProviderTests`
- `BridgeWorktreeFileSurfaceNativeTests`
- schema/model tests that reject descriptors missing
  `virtualizedExtentKind`, accept exact line-count and conservative estimated
  extent variants, and reserve `unavailable` for binary/oversized/unreadable
  cases
- provider integration tests proving `treeSizeFacts` and file/code extent facts
  are present before the first tree-window body or file-content body fetch
- Worktree/File provider canonicalization cases for malicious path/cwd scopes,
  path hints, symlinks, traversal, and root-token containment
- source-scrubbed provider/scheme rejection cases for raw path/cwd scopes,
  handle ids, capability URLs, and unsanitized provider error text
- earliest-frame `treeSizeFacts` on snapshots/tree windows and explicit file
  `virtualizedExtentKind` coverage for exact line count, estimated height,
  preview bounded, and unavailable cases
- source-scrubbed extent diagnostics allowlist/leak-negative coverage
- `BridgeReviewPipelineTests` browseTree/openFile preservation cases when
  transition edits touch the existing ReviewFoundation seams
- `BridgeSchemeHandlerWorktreeFileResourceTests` cases for leased/revoked
  Worktree/File resource body serving
- `BridgeTransportIntegrationTests` cases for Worktree/File frame identity

Legacy dev-route preservation:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

Run when ticket 03 touches browser/dev-server scaffolding, shared fixtures used
by the worktree dev route, or ReviewFoundation transition behavior that could
change the live browse/open-file route before ticket 04 replaces it.

Fixture sync if shared TS/Swift fixtures change:

```bash
bash scripts/bridge-web-sync-fixtures.sh --check
```

Quality:

```bash
mise run lint
```

Run if Swift files changed enough to require lint proof at the checkpoint.

Implementation review:

- mandatory `shravan-dev-workflow:implementation-review-swarm` before ticket 04,
  focused on source identity minting, selector/path containment, descriptor
  issuance, reset/invalidation authority, and scrubbed extent diagnostics

## Handoff Output

- source identity example
- descriptor examples for tree/status/file content
- sample `worktree.snapshot` or `worktree.treeWindow` carrying `treeSizeFacts`
- sample file descriptors for each `virtualizedExtentKind`
- explicit note showing which sample facts arrive before content bytes and which
  proof asserted that ordering
- extent diagnostics allowlist example and leak-negative proof
- source-scrubbed rejection/error payload proof for provider containment and
  scheme-handler authority failures
- invalidation/reset proof
- binary/oversized behavior proof
- canonicalization/containment rejection proof for malicious selectors
- statement that Review package lineage is not used for this provider boundary
- statement that legacy browse/open-file and worktree dev proof remain
  preserved until ticket 04 replacement, or exact blocker if not
- remaining dev-only/provider limitations
- changed paths and commit hash if checkpoint committed

## Current Review Status

Current implementation review reducer:

- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-03-current/report.md`

Verdict: `not_ready`.

Open accepted blockers before Ticket 04:

- production runtime now retains an active Worktree/File source and has native
  methods to emit live `worktree.statusPatch`, `worktree.fileInvalidated`, and
  `worktree.reset` frames with replacement descriptor support, but full
  filesystem/status watcher wiring still has to call those methods
  automatically

Open accepted important item:

- reconcile Swift frame shape with the written Worktree/File protocol spec and
  add shared strict frame fixtures before browser Zod schemas consume it
- browser-side Worktree/File response seeding/materialization remains a Ticket
  04 concern; Ticket 03 native proof only asserts response-before-intake ordering
  through the injected sink and does not claim the full browser Worktree/File
  materializer exists yet

## Stop / Replan

Stop if the host/provider cannot mint stable Worktree/File source identity
outside Review package lineage. Do not let browser code synthesize this
authority.
