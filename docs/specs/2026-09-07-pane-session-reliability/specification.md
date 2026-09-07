# Pane/session reliability — Specification

[Requirements](requirements.md) · [Program Design](program-design.md)

## User-visible lifecycle

```text
Open / backgrounded pane -> owns session -> command continues
Close pane/tab -> durable five-minute undo entry
  +-> Undo in time -> same pane/session restored
  +-> Expiry / capacity eviction -> remove this undo ownership
        +-> another owner -> session continues
        +-> no owner -> native retirement + exact zmx cleanup
Restart -> recover ownership and remaining grace before cleanup or attachment
```

The pane, its zmx session and a native rendering surface are distinct. Hiding or replacing a
renderer does not itself end ownership of the command. Deliberately detached services remain
outside terminal cleanup. The journal contains recovery state, never terminal output or handles.

## Behavior contracts

| ID | Required observable behavior | Basis |
| --- | --- | --- |
| R1 | Register exact session ownership durably before launching a new persistent command. Existing durable terminal IDs are preserved through ordinary schema setup. Unknown processes are not adopted by naming/age heuristics. | U1,U3 |
| R2 | Accepted close saves a complete pane/tab undo snapshot and removes live placement atomically. If storage fails, the close is not acknowledged and destructive cleanup does not run. | U1,U2 |
| R3 | Undo within 300 seconds restores the same pane/session and valid placement; retained same-run surfaces are reused. Ten available close operations per workspace remain the capacity limit, with oldest-first eviction. | U2 |
| R4 | Expiry/eviction/permanent discard removes only its own ownership. Open/backgrounded panes and other available undo entries protect shared session IDs across workspaces. | U3 |
| R5 | Undo and expiry have one winner. Stale saves, callbacks, duplicate requests or delayed cleanup cannot restore expired ownership, kill a replacement, or free an instance twice. | U1,U3,U4,U5 |
| R6 | Restart recovers available undo and pending cleanup before attachment/cleanup. Preserve remaining grace; uncertain elapsed timing may add at most 300 seconds once per recovery, not once per ordinary relaunch. Missing commands are reported honestly and never silently recreated as successful recovery. | U1,U2 |
| R7 | Rejected logical undo does not consume a still-valid entry or block selection of older restorable entries. If logical restore commits but rendering fails, retain the restored pane/session ownership and report the failure so it can be retried. | U2,U3 |
| R8 | After final native ownership ends, the exact Ghostty instance stops accepting work, drains outstanding use and reaches native free. A retained view cannot prevent explicit retirement. The UI does not block on thread/GPU shutdown. | U4 |
| R9 | Last-owner cleanup terminates the exact known zmx session within its existing PTY process-group boundary. A surviving member of that group prevents premature completion. Deliberately detached services remain running and do not block cleanup. Unknown or replaced identities are never signalled. | U3 |
| R10 | Failed or uncertain cleanup remains durable and retryable; CLI success or a missing socket alone does not establish termination. Restart after a termination attempt reconciles actual state before retrying. | U1,U3 |
| R11 | Hide/show, tabs, arrangements, moves, zoom and drawers preserve session identity and effective visibility/focus. Hidden panes stop starting frames; in-flight work may finish. Preserve existing equal-delivery suppression and measured responsiveness. | U5 |
| R12 | Stopped observations/tasks release captured graphs and cannot publish into replacement owners. Atom remove/reinsert and undo recurrence retain valid observation behavior. | U5 |
| R13 | Completed history is bounded; available undo and unfinished cleanup remain protected. SQLite becomes the sole durable undo/ownership authority. | U7 |
| R14 | Proof distinguishes manager release, actual native free and process termination. A safe but stalled drain still fails reclamation proof; do not hide it by changing counters or weakening tests. Diagnostics stay scrubbed and use existing facilities. | U4,U6 |

## Scenarios and proof boundaries

All scenarios are obligations, not claims of passing tests. Detailed logic uses focused tests;
SQLite and ownership interactions use real integration tests; native effects require real runtime.

| Scenario | Covers | Evidence that distinguishes success from failure |
| --- | --- | --- |
| S1 Close pane/tab with drawer children, then undo | R2,R3,R7 | Real composition + SQLite transaction; native identity/content reuse |
| S2 Deadline boundary, eleventh close, shared owners and permanent discard | R3–R5,R9 | Injected time, global owner queries, protected real command continues |
| S3 Storage failure, duplicate close, stale save, undo/expiry overlap | R2,R5 | Real rollback/conflicting transactions, including failed predecessor save; no premature external effects |
| S4 Restart inside/outside grace, clock discontinuity, repeated restart | R6,R10 | Reopened database and subprocess restart; deadline does not renew |
| S5 Missing session and failed renderer restoration | R6,R7 | Real existing-only attachment failure; ownership survives rendering failure |
| S6 Registered session teardown, original leader exits, detached service survives | R1,R9,R10 | Isolated real zmx; original group termination and unrelated service survival |
| S7 Crash after kill, replacement identity, delayed attachment | R5,R9,R10 | Real process/reopen checks plus controlled launch suspension |
| S8 Retained view/layer, callback/GPU in flight, repeated retirement, partial startup, quit | R5,R8,R14 | Real embedded native work; no early free, eventual free, MainActor heartbeat during drain and final disposal |
| S9 Tab/arrangement/zoom/drawer/minimize/move, bridge and webview close/undo | R3,R11 | Existing behavioral suites and representative native journeys |
| S10 Observation stop/replacement and atom remove/reinsert/undo | R5,R12 | Existing observation tests plus lifetime and stale-publication regressions |
| S11 Ordinary schema setup, old rows, pruning with unfinished work | R1,R13 | Real existing-schema fixture and reopened SQLite; identities preserved |
| S12 Repeated close cycles and normal multi-pane workload | R8,R11,R14 | Fixed-geometry native populations/memory trend; existing MainActor budget |
| S13 Final regression gates | R1–R14 | Full repository aggregate/lint, then scoped runtime evidence on final changes |

Native proof uses isolated debug data and exact process targeting. No production app/session is
used as disposable test input. Higher proof does not substitute for missing lower-level regressions,
and existing passing tests do not prove unimplemented behavior.
