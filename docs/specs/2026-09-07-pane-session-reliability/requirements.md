# Pane/session reliability — Requirements

[Specification](specification.md) · [Program Design](program-design.md)

## Goal and users

Make Agent Studio reliable when its user hides, closes, restores and reopens terminal panes.
Keep commands that still belong to a pane or undo entry; release native resources and close known
zmx sessions when their ownership ends. Developers need reproducible tests and real runtime proof.
This is a focused reliability change in the current app, not a new persistence platform.

## Agreed outcomes

Authority for every row is the user's instructions in this session, including the final scope
reset and explicit approval of ordinary SQLite schema setup. All rows are authorized and required
for this change; their order expresses the lifecycle, not a new priority ranking.

| ID | Need | Reason / governing decision |
| --- | --- | --- |
| U1 | Persist pane/session correlation and close/undo ownership in existing core.sqlite | Restart must not forget which commands are still owned |
| U2 | Five-minute undo restores the same logical pane/session, reusing retained native content in the same run | User confirmed grace and continuity; retain existing ten-close capacity |
| U3 | End only the closing operation's ownership; clean up an exact known zmx session only after its last owner ends | Other panes, backgrounded panes and undo entries must remain safe |
| U4 | Free Ghostty resources safely and keep the app responsive | Dropping a manager reference is not sufficient memory proof |
| U5 | Preserve visibility, focus, drawer/tab/arrangement behavior and correct atom/async lifetimes | Reliability fixes must not introduce pane or observation regressions |
| U6 | Prove old and new scenarios with TDD, integration tests, native proof and repository checks | Passing model tests does not establish actual memory reclamation |
| U7 | Replace superseded ownership logic and bound completed history | Avoid parallel authorities and accumulating dead records |

## Boundaries

Use ordinary schema changes through the existing SQLite setup. The journal table names remain
workspace_terminal_session_ownership, workspace_undo_close and workspace_undo_close_member.
Existing pane tables continue to hold open/backgrounded panes and their terminal identities.
Necessary app and vendor lifetime corrections are in scope; broad vendor upgrades are not.

Preserve five-minute grace, ten-entry capacity, opaque IDs, existing commands and stable/beta/debug
isolation. If restart timing is uncertain, at most five extra minutes of recovery grace is allowed;
ordinary relaunch must not repeatedly renew it. A machine reboot does not preserve local commands.

Explicitly excluded: a separate database, general event sourcing, process genealogy/supervision,
killing deliberately detached services, custom upgrade/downgrade management, and automatic sweeping
of unknown legacy sessions. The agentstudio-git review-comment lane and resolved disk incident are
also excluded. The rejected earlier design is not authority for this replacement.

## Source-grounded starting point

The current coordinator has an in-memory undoStack with capacity ten. Close places retained panes
in pendingUndo with a distant-future deadline; native retention has separate expiry behavior.
Ghostty.SurfaceView.deinit calls ghostty_surface_free. zmx handleKill signals its PTY process group.
These are current implementation facts, not permission to preserve competing ownership decisions.
See Program Design's source map. Existing fixes and native prototypes are retained for validation;
none is assumed to satisfy the final end-to-end behavior merely because it exists.
