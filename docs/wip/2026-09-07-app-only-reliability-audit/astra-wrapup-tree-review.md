# Astra review of the app-only wrap-up tree

Reviewed 2026-09-08 on `takeover/remaining-performance-memory`, HEAD
`293cc48c7f57c3835bfb42b467eafc71355eaa67`, including the current uncommitted tree.
This is a bounded advisory review of the execution map and pruning, not final implementation
review or PR readiness. No tests, builds, app launches, process signals, or vendor mutations ran.

**Verdict: the tree is ready as the bounded execution map; no unresolved review correction
remains.** The actual implementation and final proof remain unfinished as stated.

## Verified correction

The initial pass found present-tense instructions in the retained attention rationale that
could revive the old broad audit and treat an unproven view retainer as a current defect.
A bounded recheck of the corrected ending of
`docs/wip/2026-09-06-attention-ordering/program-design.md` verified this is resolved: it now
describes historical limits, expressly authorizes no new sweep, vendor work or atom-family
redesign, and gives the current tree sole ownership of remaining delivery. The projector proof
paragraph also assigns final validation to the tree. Useful rationale remains preserved.

## Integration checkpoint already represented

The first-identity race is a real unresolved integration obligation, correctly retained at tree
lines 48, 52 and 103–104. `ZmxBackend.swift:109–112` says the daemon begins on surface attach,
while `WorkspaceCoreRepository+SessionOwnership.swift:29–42` accepts a first identity only in
`owned`. A first observation after transition to unidentified `pending` is intentionally rejected.
The permanent cleanup persistence test asserts that behavior.

Before wiring destructive cleanup, establish the actual launch/observation/commit ordering and
prove close or discard during launch cannot create a late replacement. An arbitrary observation
of an already-pending session cannot become trusted by relaxing that guard. If the existing app
path cannot provide the required ordering, report that concrete break before adding a new owner
or changing the contract. The tree already calls for this investigation; no extra architecture
phase or vendor work is needed to express it.

Uncertain cleanup is also covered adequately: exact daemon identity, original PTY group,
replacement/unknown/detached protection, crash-after-kill reconciliation, bounded attempts,
failure persistence and completion only with evidence. Keep pending rows and their protected
history incomplete when identity or extinction is unverified. Existing pruning deliberately
excludes them; “history pruning” must not become a reason to mark them completed.

## Coverage and verification

- The three existing journal tables, 300-second Undo, ten-operation oldest-first eviction,
  restart grace, shared owners, publication ordering, native retirement, missing-session restore,
  failure scenarios, current regression proof, and ready-but-unmerged delivery are represented.
- The removed September 7 reliability folder and old lane plans/repair sequence are absent.
  A search outside the historical audit found no remaining link to the removed spec folder.
  Historical audit references remain evidence, not active instructions.
- `git diff origin/main --name-only -- vendor .gitmodules Package.swift Package.resolved
  scripts/build-vendors.sh scripts/vendor-worktree.sh scripts/setup.sh` produced no entries.
  `bash scripts/vendor-worktree.sh verify` and `git diff --check` exited 0. Both vendor gitlinks
  are unhydrated; shared-output verification passed. This does not certify a future executable.
- The tree accurately marks storage writes as tested but unwired. Its same-run Undo and restart
  deadline observations are scoped historical evidence; actual restart-and-Undo UI proof is
  still TODO. GUI lock is not evidence of an app restore defect.
- Native safety and shutdown responsiveness remain current app/runtime proof obligations.
  `GhosttySurfaceView.swift:487–512` uses the existing synchronous free call. This review neither
  certifies retained-layer/callback safety nor infers a need to edit vendors.

No other scope or coverage correction found in this bounded review. The parent owns final
disposition and may mark this tree review complete. This does not mark implementation or
delivery complete.
