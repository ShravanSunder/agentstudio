# Pane/session reliability — Program Design

[Requirements](requirements.md) · [Specification](specification.md)

## Shape and ownership

```text
Existing workspace commands
  -> Core validates proposed ownership change
  -> existing SQLite writer commits composition + undo + cleanup obligation
  -> MainActor publishes committed state
  -> existing App/Terminal boundary applies exact native effects
       +-> SurfaceManager retires native instance
       +-> ZmxBackend closes exact unowned session
```

SQLite owns durable ownership and undo. Existing atoms publish committed UI state. SurfaceManager
owns native instances, including retained undo surfaces. ZmxBackend owns process operations.
No new atom, store, bus, event-sourcing system or process supervisor is introduced.

| Current source/path | Change or preservation |
| --- | --- |
| App/Coordination/WorkspaceSurfaceCoordinator.swift undoStack/maxUndoStackSize; +ActionExecution.swift close/eviction | Replace authoritative array with projection of SQLite undo; preserve capacity ten |
| App/Coordination/WorkspaceSurfaceCoordinator+Undo.swift | Validate/commit restore before consuming undo; materialization follows commit |
| Core/State/SQLite/WorkspaceSQLiteDatastore.swift workspaceSaveTail | Reuse one serialized writer order for lifecycle changes and saves |
| Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift | Existing pane/terminal rows remain open/backgrounded ownership source |
| Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift | Add ordinary journal schema and register existing durable terminal IDs; no custom upgrade framework |
| Features/Terminal/Ghostty/GhosttySurfaceView.swift deinit and SurfaceManager+RendererState.swift | Replace deinit-only free/independent undo expiry with explicit instance retirement |
| App/Coordination/WorkspaceSurfaceCoordinator+RendererVisibility.swift | Preserve window + pane visibility resolution and reconciliation measurement |
| Core/RuntimeEventSystem/Runtime/ZmxBackend.swift and vendor/zmx/src/main.zig | Existing process boundary; add verified identity/termination outcomes |

Source paths above are under Sources/AgentStudio unless prefixed vendor. Native implementation
must also inspect vendor/ghostty/src/Surface.zig, apprt/embedded.zig, renderer/generic.zig and
termio/Exec.zig. Existing prototype code is input to validation, not assumed production-ready.

## Three tables in existing core.sqlite

Types: IDs TEXT (existing opaque values; new app IDs use UUIDv7); times REAL UTC seconds;
sequences INTEGER; snapshots and typed process identity BLOB. Nullability is stated below.

| Table | Columns and constraints |
| --- | --- |
| workspace_terminal_session_ownership | session_id PK; cleanup_state NOT NULL in owned/pending/completed; cleanup_requested_at nullable; cleanup_completed_at nullable; last_cleanup_error nullable controlled code; process_identity nullable versioned record |
| workspace_undo_close | close_id PK; workspace_id NOT NULL; close_sequence NOT NULL; close_kind NOT NULL pane/tab; closed_at and expires_at NOT NULL; state NOT NULL available/restored/expired/evicted; snapshot_version NOT NULL; snapshot_payload required while available, nullable after completion; deadline_boot_id and deadline_uptime_ns NOT NULL |
| workspace_undo_close_member | close_id FK undo_close; pane_id NOT NULL; session_id nullable FK ownership; composite PK(close_id,pane_id) |

The process identity record includes its observation boot identity as well as zmx Info and process-start
evidence; once set, retries cannot replace it. The two deadline anchor fields preserve elapsed grace across same-boot restart without wall-clock
steps renewing it. process_identity records the observed original zmx Info identity and kernel
process-start evidence needed for safe retry; it is not a process genealogy or another log.
These fields serve R5/R6/R10 and avoid inferring identity or elapsed time from a reused PID/date.

Unique(workspace_id,close_sequence) orders retained operations. Allocate COALESCE(MAX(close_sequence),0)+1
over ALL retained rows for that workspace, regardless of state, within the writer transaction; sequence orders current retained entries, while close_id is permanent
operation identity. Sequence exhaustion rejects the operation rather than wrapping.
Index available undo by workspace/sequence and expiry; index members by session_id and registry
by cleanup_state. Existing terminal rows reference registry IDs after ordinary schema setup.

Enforce monotonic states: pending/completed sessions cannot gain ownership; completed cannot
reopen. Available undo requires a decodable snapshot whose pane/session membership matches rows.
Member identity is immutable. Foreign keys prevent orphan references; direct member/parent deletion
must reject available undo or unfinished cleanup. Deleting live pane rows must not cascade into
historical members. Snapshot DTO contains pane/layout/drawer restoration data, not views or tasks.

## Single write order and transitions

All structural lifecycle proposals and autosaves use the existing serialized writer admission.
A proposal captures the existing accepted composition generation. Before accepting a save or
transition, validate that generation against the current admitted composition; reject superseded
captures and recapture, never relabel stale payload with a newer generation. Advance generation
with every accepted structural change. While a lifecycle commit is awaiting, later structural
commands queue; unrelated UI/terminal output continues. Publish its committed delta before admitting
the next capture. Process-restart generations begin only after loading current durable state.
This is one application writer, not a new multi-process transaction or lease service.

The save tail's current swallow-previous-failure behavior supplies ordering only, not permission
for lifecycle work to use stale durable composition. Ownership-changing create/restore/close
always commits before UI publication. A failed structural save leaves the durable generation
unadvanced and blocks last-owner evaluation, new pending transitions and cleanup effects until
a current full composition save reconciles successfully. Reject stale generations during that
recovery too. Non-structural presentation/cache failures do not acquire this gate. No new durable
failure-state table is needed; the existing writer owns the pending failure and generation.

| Operation | One SQLite transaction | After commit |
| --- | --- | --- |
| Create | Register freshly minted session ID with live pane; reject historical-ID reuse | Admit and launch that instance; record observed process identity when available |
| Close | Validate snapshot; insert undo+members+300s deadline; remove live rows/placement; evict oldest excess entries; mark newly unowned sessions pending | Publish delta; hide/detach while retaining native instances for available undo |
| Undo | Inspect available entries newest-first; skip invalid placement without consuming it; restore the first valid entry and mark restored atomically | Reuse retained surface or attach existing session; render failure preserves restored owner |
| Expire/evict/discard | Finish affected ownership; query all owners; mark newly unowned sessions pending | End native retention and schedule exact session cleanup |
| Cleanup result | Confirm same session identity and pending state; completed only on verified result; otherwise preserve pending/error | Existing diagnostics report outcome |

The last-owner predicate is absence from BOTH pane_content_terminal.zmx_session_id and members
joined to available undo. Backgrounded panes are ordinary pane rows with residency_kind; no active
layout, visibility or workspace-provenance filter belongs in this query. Shared IDs in another
workspace remain protected. Workspace/drawer deletion and backgrounded-pane discard use this same
transition; merely failing undo is not discard. Skipped undo entries retain their original deadline
and expire normally; if none validates, report no restorable entry without discarding ownership.
Webview/bridge members have no zmx session to kill.

A single cancellable cleanup task drains pending work through the existing boundary, with bounded
process timeouts and capped retry delay from AppPolicies. No persisted worker leases or claim
service. Stopping the app leaves pending rows for restart. No second concurrent attempt for one
session in a run; state and identity checks make repeated recovery idempotent.

## Restart, deadlines and pruning

Normal startup applies ordinary schema setup, preserves existing IDs and loads composition/undo
before hydration or cleanup. Missing historical in-memory undo is not invented. Owned rows with
no actual owner are reconciled into pending cleanup only from complete valid durable state.

Use an injected time value containing UTC, kern.bootsessionuuid and mach_continuous_time-derived uptime. Same boot
uses the saved uptime deadline. A changed boot uses a conservative recovery deadline at most
300 seconds ahead and persists its new boot/uptime anchor before scheduling; ordinary relaunch
reuses that anchor. Never derive boot identity from wall-clock boot time. A missing clock reading
preserves the recorded deadline and reports uncertainty; it does not authorize early destruction
or manufacture a new boot on every launch. Machine reboot cannot promise command continuity.

Reuse existing expiry scheduling, now driven by durable deadlines rather than an independent
SurfaceManager TTL. Undo at/after the deadline is rejected; the due transition runs in the same
writer order. Periodic wakeups are triggers to check state, not separate ownership authorities.

Keep at most ten available operations. Completed diagnostic undo history is capped at 100 operations
per workspace (AppPolicies); prune oldest completed entries in bounded batches of 100. Available
undo and unfinished cleanup are exempt. Remove members before their finished parent and remove
completed session records only when unreferenced. Fresh creation never accepts an external old ID,
so pruning does not reopen old identity admission. No per-close VACUUM or separate log database.

## Native retirement and zmx termination

```text
Instance active/hidden/undo-owned
  -> permanently released: withdraw handle and close callback/frame admission
  -> draining: stop started threads; reap joins off MainActor; finish GPU callbacks
  -> finalizable: all users gone, shared runtime still alive
  -> dispose once on supported context; emit actual native-free evidence
```

The retiring operation retains the view/userdata, native allocation and shared App dependencies.
Every old-instance entry rejects further use. Layer-owned admission state outlives the renderer.
Callbacks acquire admission before reading renderer context; retirement rejects new admissions
and waits for admitted uses to finish. Do not hold its lock across
drawing, joins or GPU waits. Frame completion owns its obligation until its final renderer access.
Stop all started threads before waiting; completion includes outer I/O error/drain wrappers and
optional search. Partial initialization tracks only resources/threads actually created.
Final disposal runs only after off-main joins and callback/frame quiescence. Timeout reports a
stalled retirement and retains required memory; it does not force free or pass the leak gate.
The embedded API must split current Surface.deinit: begin-retirement runs on MainActor and
requests stop; drain-retirement executes native joins on a background executor; try-finalize runs
on MainActor only after join acknowledgment and callback/GPU quiescence. Finalize performs no join,
semaphore wait or GPU wait and does not call the old unsplit ghostty_surface_free path. Native
allocation destruction and renderer-context re-entry remain on MainActor after the barrier.

SurfaceManager is the sole production view creator. Both acceptance failure and permanent release
transfer the still-live view into its retiring-instance ownership before dropping local/active
references. It retains raw NSView/userdata targets until disposal completes, then clears the view's
handle. Deinit must find no live native handle; it cannot resurrect a dying view to start async
drain. Native partial construction remains owned by the construction path until its initialized
resources are cleaned up; a nil result cannot leave callbacks targeting released view memory.
Deferred callback tasks resolve/capture a safe owner or stable identity before their async hop;
integer-encoded raw pointers are not lifetime protection. Hidden/replaced surfaces do not imply zmx kill.

Remove the native completion path's forever mailbox send so it cannot block its own frame release.
Preserve ordered unhealthy/recovery delivery through the existing App loop, with bounded draining.
Bound attachment child-stop work without ever signalling the app's process group. Existing native
prototypes must prove these interactions in real retained-layer/Metal/resistant-child scenarios.

Before zmx cleanup, the App materialization boundary invalidates queued launches and retires/drains
all admitted attachments for that session. Its no-await final admission check and createSurface
call share the same instance owner; retain admission until attachment launch has quiesced, not
merely until the C constructor returns. Boot installs pending-retirement rejection before launch.

The zmx adapter probes Info, matches the stored incarnation, and sends Kill on that same connection.
It never reconnects by name between check and kill. The daemon remains signal owner for its PTY
group. Completion checks original process exit, original endpoint absence and a read-only original
group probe reporting ESRCH. If the identity record proves a different kernel boot, the old local
incarnation is completed without signalling, regardless of reused IDs in the new boot. Within
one boot, a reused leader PID proves only leader exit: the original group must still be absent.
A replacement endpoint is untouched. If original process/group extinction is proven, a distinct
replacement does not keep the old obligation alive; if not proven, retain pending. Missing stored
identity is uncertainty, not proof that no command launched. EPERM or an extant original group
is unresolved; the app does not guess PIDs to signal afterward. A deliberately detached service is outside this boundary.
The first trusted process observation is persisted; retries cannot replace it with a new incarnation.
Missing-session undo uses existing-only attachment, never attach-with-create under a recovery claim.

## Proof and removal checklist

S1–S13 in Specification own the full proof inventory. Existing UndoRestore/DrawerUndo,
SurfaceManagerRendererStateDelivery, coordinator visibility, TerminalRuntimeObservationRetention,
RepoExplorerProjectionLifetime and AtomFamilyObservation suites preserve their behavioral claims.
Real SQLite tests cover transactions/reopen/pruning; real isolated zmx covers identity/group
termination/restart; real native work covers callback/GPU/thread lifetime and responsive close/quit.
No mock or native helper test substitutes for these interactions.

Preserve the existing renderer conservation counters and post-release leak threshold; pending
retirement does not become a new owned bucket that hides retained memory. Fixed-geometry repeated
close cycles and multi-pane workload prove populations settle and existing MainActor performance
budgets remain satisfied. The final branch also requires the full repository test and lint gates.

Delete authoritative in-memory undo/pop-before-validation, distant-future pending-undo ownership,
independent native undo deadlines and blind stale snapshot replacement. UI undo lists become
projections, and native retained instances become a cache of durable undo ownership. Keep existing
visibility/attention fixes and the proven observation-capture correction; do not reopen unrelated
atom policy. Any further atom change requires an evidenced retention defect plus preserved
remove/reinsert/undo observation tests. No arbitrary slot TTL or broad reactive-state redesign.
