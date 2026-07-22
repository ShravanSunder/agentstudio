# Ticket 03 Current Implementation Review Reducer

Date: 2026-06-23
Range: `aaf42428..6489c663`, plus same-session review fixes on top of
`6489c663`.

## Verdict

`not_ready`

Reason: the native Worktree/File source-opening path is materially improved, but
Ticket 03 is not ready to advance to Ticket 04 while live Worktree/File
resource body serving and production non-snapshot frame emission remain absent.

## Accepted Findings Fixed In This Pass

### File-scoped `pathScope` returned a zero-row exact tree extent

Status: fixed

Evidence:

- `BridgePaneController+WorktreeFileSurface.swift` now resolves first-open
  extents without a recursive tree walk and reports exact count `1` for direct
  file scopes.
- `BridgeWorktreeFileSurfaceTransportTests` covers a file-scoped open.

Proof:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 \
mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests'
```

Exit: 0. Result: 27 tests in 3 suites passed.

### Worktree/File leases survived source reopen and teardown

Status: fixed for snapshot tree/status descriptor authority.

Evidence:

- `handleWorktreeFileSurfaceOpenSourceStream` now resets pane-scoped
  `worktree-file` leases before registering a new source generation.
- `BridgePaneController.teardown()` now synchronously revokes `worktree-file`
  authority and asynchronously clears remaining leases.
- Transport test asserts an old tree descriptor lease is inactive after a second
  source open.

Proof: same 27-test focused command above, exit 0.

### Blank Worktree/File selector authority fields decoded successfully

Status: fixed.

Evidence:

- `BridgeWorktreeFileSurfaceSourceSpec.init(from:)` now rejects blank
  `clientRequestId`, `rootPathToken`, present `cwdScope`, and `pathScope`
  entries.
- Source-provider tests cover all four decode failures.

Proof: same 27-test focused command above, exit 0.

### Missing positive `estimatedHeight` descriptor example

Status: fixed.

Evidence:

- `BridgeWorktreeFileSurfaceTests` now has a readable-text
  `estimatedHeight` descriptor case that asserts extent metadata is present
  before content bytes.

Proof: same 27-test focused command above, exit 0.

## Accepted Findings Still Open

### Live Ticket 03 runtime stops at `worktree.snapshot`

Status: accepted blocker.

Current code registers the `worktreeFileSurface.openSourceStream` RPC and
returns a host-minted `worktree.snapshot`, but production code does not yet
retain an active Worktree/File subscription or emit live
`worktree.statusPatch`, `worktree.fileInvalidated`, `worktree.reset`, or real
file-descriptor frames from filesystem/status updates.

Smallest next fix:

- Persist opened Worktree/File source state in the controller/provider layer.
- Wire filesystem/git-status changes through
  `BridgeWorktreeFileSurfaceClassifier`.
- Emit the non-snapshot frames through the real production path.
- Add stale-generation rejection proof.

### Minted Worktree/File resource URLs are not body-fetchable yet

Status: accepted blocker.

`BridgeSchemeHandler.reply` currently classifies `worktree-file` resource URLs
but rejects non-`review/content` resources before bytes. This is fail-closed and
source-scrubbed, but it means Ticket 04 cannot consume tree/status/file
descriptor URLs until native body serving exists.

Smallest next fix:

- Add a Worktree/File resource body provider/executor for `worktree.treeWindow`,
  `worktree.status`, and `worktree.fileContent`.
- Add HEAD/GET scheme-handler proof for leased Worktree/File resources plus
  stale/revoked rejection cases.

### Spec/model drift needs reconciliation before browser schemas are written

Status: accepted important.

The Swift model currently carries `treeSizeFacts.extentKind` and source facts
that the written strict protocol sections may not reflect. The likely right fix
is to update the spec to the richer Swift shape and then add shared frame
fixtures before Ticket 04 Zod schemas are generated.

## Rejected Or Deferred Findings

- Security/trust-boundary lane found no current Ticket 03 issue under the
  reviewed closed-app native-lease authority boundary. Future Worktree/File body
  serving must be reviewed separately when implemented.

## Verification

- Red proof before fixes:
  - focused Worktree/File test command exited 1.
  - Failures matched blank selector decode, file-scope count `0`, and stale
    lease survival.
- Green proof after fixes:
  - focused Worktree/File command exited 0 with 27 tests in 3 suites passed.
- Changed-file SwiftLint:
  - exit 0, 0 violations in 6 files.
- `git diff --check`:
  - exit 0.
- Full quality:
  - `mise run lint` exit 0.
  - swift-format OK.
  - SwiftLint 0 violations in 1323 files.
  - architecture lint OK.
  - release script verification passed.

## Swarm Coverage

- Spec/proof lane: completed; 2 blockers and 1 important proof gap accepted.
- Security/trust-boundary lane: completed; no findings.
- Reliability/performance lane: completed; 2 blockers and 1 important finding
  accepted, with the lease and first-open extent items fixed in this pass.
- Contracts/tests/adversarial lane: completed; 2 important findings and 1
  follow-up accepted/fixed, 1 spec-drift item accepted as open.
