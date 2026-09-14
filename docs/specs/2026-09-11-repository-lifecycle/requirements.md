# Repository and Checkout Lifecycle Requirements

[Specification](specification.md)

## Goal and boundary

Agent Studio users should be able to move or delete folders in watched directories without stale usable rows, indefinite “Scanning,” duplicate active entries for the same canonical path, or disappearing panes. The lifecycle must reconcile changes made both while running and while the app is closed.

The existing application repository/worktree UUIDs, watched parent scopes, pane lifecycle, and separate core/local persistence boundaries remain the foundation. Repository cleanup concerns application records, not deletion or modification of user folders or Git metadata. At expiry the collected repository’s own notes, pinning, tags and checkout notes are part of that record; separate pane, undo, annotation and review history remain protected. No archival store is added for expired repository metadata.

## Authorized needs

The user is the decision authority. Every row below is authorized by the quoted session instruction; all are required for this scope, without an additional priority ranking.

| ID | Need and reason | Owner authority |
|---|---|---|
| U1 | Show available repositories/checkouts accurately; stale or missing folders must not look usable or indefinitely scanning. | “repos ... removed do not ... update the watch list”; production screenshot and request to fix stale entries |
| U2 | Retain hidden records temporarily so returning folders can reuse their identity. No hidden-items screen is needed. | “hidden means ... allow a chance ... to show up again in the watch directories”; “Hide them with no recovery view” |
| U3 | Handle moves automatically within the evidence available, without asking users to repair or merge records. Do not claim two locations are the same without proof. | “i dont want users to do this”; “yes if its ... unproven we never know its the same” |
| U4 | Preserve panes and their terminal/undo lifecycle; clean optional repository/worktree references when they no longer resolve. | “Keep pane and clear optional repository/worktree facets; preserve terminal and undo lifecycle” |
| U5 | Delete application topology and collectible related state after 30 days hidden; avoid permanent abandoned data. | “if something was hidden for a month ... delete and garbage collect”; explicit “30 days” selection |
| U6 | Keep separate checkouts distinct even when they belong to the same repository family. | “how ... make sure we dont collapse separate checkouts?” |
| U7 | Keep Git semantics within agentstudio-git/libgit2 and keep the UI responsive during scans and cleanup. | “for any agent studio git related stuff ... use agentstudio-git”; “keeping performance and main actor in mind” |

U3 supersedes the earlier proposed Repair flow. No manual reassociation or persistent move-correlation identity is requested. An unproven new location is independent of a hidden old record; discovering it is not evidence authorizing earlier deletion of the old record.

## User journey

```text
Move/delete folders or reopen the app
  -> watched directories are reconciled
  -> usable locations appear; confirmed missing locations disappear from the list
  -> existing panes remain usable as panes, without invalid checkout links
  -> same-path return restores retained records
  -> records still hidden after 30 days become eligible for cleanup
```

This journey serves U1–U6. The observed pain is stale rows, duplicate-looking locations, and misleading “Scanning.” The reported terminal disappearance/navigation surprise is not yet a reproduced crash or deletion; U4 requires proof that repository reconciliation cannot remove or silently redirect a pane.

## Protected scope and exclusions

- No Repair/Locate/merge interaction or hidden-repository screen.
- No change to explicit Remove Repository or removal of a watched parent. Those user commands are not filesystem-absence evidence and must not enter the new 30-day policy merely because a scope changed.
- No merging independent clones because they share a name, remote, branch, commit, or content.
- No new persistent common-directory identity or move-correlation store.
- No direct Git CLI or wt integration; package calls own Git semantics.
- No deletion of folders or Git worktree administrative metadata.
- No pane deletion, terminal termination, undo expiration change, or deletion of saved annotations/history as a repository cleanup side effect.
- No performance workaround that scans, performs SQL, or schedules per-repository polling on MainActor.

Evidence must cover real filesystem/package discovery, durable data readback, pane continuity, runtime registrations, late-result rejection, visible projection, and bounded performance. Unit-only or screenshot-only evidence cannot prove the whole lifecycle.
