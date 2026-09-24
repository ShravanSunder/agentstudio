# IPC v2 / Bridge coordination message — not sent

Router endpoint discovery returned `Endpoint discovery unavailable` on both
attempts. No addresses were discovered and no message was submitted. This is
a current draft for the agent in `agent-studio.ipc-improvements`, not agreement
with that agent. Sibling design inspected at `cc0f0fdc8`; source remains in progress.

## Current scope to communicate

The owner asked this viewing worktree to design the Bridge behavior behind your
IPC-v2 boundary. We remain design-only and command-first, with new picker/control design deferred. Files must still expose all member
worktree trees plus loose files together and search that whole collection. Drawer work remains separate.

- Terminal CWD/repo/worktree association stays singular. IPC targets that
  terminal’s stable associated Bridge, including fullscreen. Drawer-terminal
  callers resolve to their owner pane's Bridge; only owner CWD determines
  protection, while the caller's captured CWD resolves relative paths. Its current known
  CWD member is injected/deduplicated and protected; old members remain removable
  when CWD changes. No known CWD means no protected member.
- Files can open supported accessible local files anywhere, including outside
  Git and inside repositories unknown to Agent Studio. The receiver retains an
  opened-file list, saved paths and annotation associations.
- Agent file.open is preparation-only: retain the document in the associated
  Bridge without entering fullscreen, taking focus or replacing the currently
  displayed document. Return prepared, not shown. Notifications/popovers/approval
  and Sessions-screen work are deferred; do not add notification plumbing here.
- Opening a file does not register its containing repository or add a browsing
  root. Standalone files are genuine file sources, not fake worktrees.
- Worktree-add and Git Review use only already-known worktrees. Worktree-add
  changes the receiving Bridge’s browsing membership without moving terminal
  CWD or modifying another collection. Explicit removal rejects the protected
  member, clears affected Files selection without loose-file reclassification,
  and switches affected Review to the next remaining member/comparison. With no
  members, loose Files remain and Review is empty. Removal is human/debug scope.
- Undiscovered-worktree intake, shared-collection mutation, other-Bridge
  mutation and new grant flows are outside this PR. Earlier questions about
  expanding workspace-wide authority are withdrawn following the owner’s scope
  clarification (Requirements S23/S24).

## C7 amendment to coordinate

Retain the reserved `file.open` method, dedicated `AppCommand.openFile`
relationship, exact path/captured-base inputs, v2 pane-target spelling,
CLI-generated correlation, replay/conflict handling and error taxonomy.

Change the stale reserved placement contract:

| Element | Required direction |
| --- | --- |
| Terminal `self` target | Resolve to the caller terminal’s associated Bridge, not the currently focused pane or an arbitrary worktree-matching Bridge. |
| Companion identity | Native companion/controller identity may change; the receiving terminal association remains the caller’s target. |
| Placement | Remove drawer/split/tab/new as the default contract for this Bridge operation. Fullscreen uses the targeted terminal’s associated Bridge; no Bridge drawer content. |
| File source | A local file need not have a known worktree. The app resolves and admits the exact file; callers do not manufacture Git IDs. |
| Result | Report the receiving owner and retained document/source. Agent preparation must not claim shown/arrived; preserve v2 acceptance/partial/error distinctions. |

Preparation-only is selected for this version; remove a foreground/show override
from this reserved file.open realization rather than adding an approval UI now.
Exact result/schema spelling needs joint agreement under v2’s outcome taxonomy.
Human/debug activation uses new typed activateBridgeFile/activateBridgeReview
identities, preserving existing showBridge tab-opening commands. No durable
prepared-line field or extra refreshBridgeFiles command is proposed. Collection
search uses the receiver's mounted JS worker and returns not-ready otherwise.
Human activation and unfinished-draft navigation are separate from preparation. Your IPC-v2-only slice can keep this
contract reserved/unadvertised until the Bridge implementation is supplied.

## Questions for the IPC owner

1. Which typed descriptor/contribution and command-execution APIs are implemented
   now, and which are design-only? Which shared files should this lane avoid
   editing while your v2 migration is in progress?
2. Can we amend reserved C7 to the associated-Bridge destination above while
   retaining your dedicated `openFile`, target/correlation and outcome contracts?
3. Which self-pane target/authority seam should the adapter use when the native
   recipient is a transient associated Bridge? Known-worktree membership is a
   local effect on that receiving Bridge; no new workspace-wide capability is
   requested.
4. Is there an existing snapshot/query projection seam for opened documents,
   known-worktree membership, selected worktree/comparison and arrival state?
   New commands should be testable through your typed debug command variants.

## Proposed ownership boundary

Your lane owns v2 transport, schema/registry infrastructure, target parsing and
authentication, correlation/replay, generated CLI, debug control and v1 cutover.
This lane owns Bridge document/source/annotation behavior, saved opened-file
state, known-worktree selection and native semantic command handlers. It will
contribute through your catalog rather than adding v1 methods, a second parser
or another operation/auth system. This division is proposed pending your reply.

No source changes or edits in your worktree have been made by this lane.
