# 03 Worktree/File Native Provider Boundary

## Ticket Output

Create the host/provider boundary for the Worktree/File Surface as a first-class
application protocol. This ticket does not need to build the full browser UI.

Deliverable:

- provider-issued `WorktreeFileSurfaceSourceIdentity`
- `worktree.snapshot` host frame with tree/status descriptors
- file descriptors with content handles and attached content descriptors
- provider-owned filesystem/watch and git-status classification seams
- invalidation and reset decisions
- binary/oversized metadata decisions
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
- File descriptor carries file id, content handle, size, binary flag, optional
  hash, and attached content descriptor.
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
5. Add frame builder and method registration for opening a Worktree/File source.
6. Keep compatibility with old Review-shaped browse/open-file until ticket 04
   replaces the user-facing route.

## Proof Gates

Swift focused:

```bash
mise run test-fast
```

Focused suites should include or add:

- `BridgeWorktreeFileSurfaceTests`
- `BridgeWorktreeFileSourceProviderTests`
- `BridgeWorktreeFileSurfaceNativeTests`
- Worktree/File provider canonicalization cases for malicious path/cwd scopes,
  path hints, symlinks, traversal, and root-token containment
- `BridgeReviewPipelineTests` browseTree/openFile preservation cases when
  transition edits touch the existing ReviewFoundation seams
- `BridgeSchemeHandlerTests` cases for Worktree/File resource kinds
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

## Handoff Output

- source identity example
- descriptor examples for tree/status/file content
- invalidation/reset proof
- binary/oversized behavior proof
- canonicalization/containment rejection proof for malicious selectors
- statement that Review package lineage is not used for this provider boundary
- statement that legacy browse/open-file and worktree dev proof remain
  preserved until ticket 04 replacement, or exact blocker if not
- remaining dev-only/provider limitations
- changed paths and commit hash if checkpoint committed

## Stop / Replan

Stop if the host/provider cannot mint stable Worktree/File source identity
outside Review package lineage. Do not let browser code synthesize this
authority.
