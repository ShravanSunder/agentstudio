# Bridge Review Comparison Target Loading — User Requirements

## Why this correction exists

The comparison-target correction already moved the branch catalog out of Review
initialization and into an on-demand picker query. The remaining query currently
captures Git data and materializes the complete response before its control
operation finishes. While that production is slow, the pane's single control
sequence can reject an unrelated command even though the catalog is delivered
through a separate content operation.

The reviewer needs both guarantees: ordinary Review loading must remain
independent from repository catalog size, and producing a requested catalog
must not monopolize unrelated pane control.

```text
reviewer opens Review View
        │
        ├─ current comparison appears from compact current state
        │
        └─ reviewer opens Compare Worktree
                 ├─ query authorization completes promptly
                 ├─ recent branch choices produce on content demand
                 ├─ remembered Commit mode → focus commit input
                 └─ remembered Branch mode → focus branch search
                    while unrelated pane controls remain responsive
                    and the current comparison remains intact
```

## Consumers and authority

- P0 human reviewer: chooses the branch or commit used by Review View.
- Bridge maintainers: need one reusable transport boundary that remains safe as
  repositories and future on-demand product queries grow.
- Decision authority: Agent Studio owner decisions in this session.
- Current-system evidence: the merged comparison-target implementation and Bridge transport
  sources cited by the companion Program Design.

## Authorized needs

### CT-U1 — Review opens independently of branch-catalog size

Review View must publish and display the current comparison without first
loading every branch choice. A closed comparison picker must add no branch-list
enumeration, transfer, worker materialization, or row-rendering work.

Priority: must.

### CT-U2 — Branch choices appear when requested

Opening the comparison picker must load locally available branch choices so a
later switch to Branch can show them immediately. The remembered mode still
owns focus: Branch focuses branch search and Commit focuses commit entry.
Switching modes while the picker remains open must preserve the preload rather
than starting or cancelling another query. Search, keyboard navigation, pointer
selection, and the existing remembered Branch/Commit modes must remain usable
while the result set is large.

Priority: must.

### CT-U3 — The picker is deliberately bounded

The picker is a recent-target convenience, not a complete Git client. It should
offer branches whose tip commits are within the rolling previous 30 days while
always retaining the repository default target and the current selected branch
when they can be resolved. The result must also have hard capacity bounds so
pathological repositories cannot overwhelm Bridge.

This deliberately narrows PR0's earlier promise that every resolvable branch is
available in Branch mode. A branch older than the recent window is absent unless
it is the repository default or current selection. Exact commit entry remains
available, but it is a pinned commit choice rather than a living replacement for
an omitted branch. The picker must make that recent-window boundary visible even
when the returned result did not hit a capacity limit.

Priority: must.

### CT-U4 — Current comparison truth remains pushed and compact

The active comparison target, whether it is the currently resolvable repository
default target, its attempt/current/stale state, and invalidation or movement
notifications must remain available without activating Branch selection.
Available target choices must not be mixed into that continuously pushed state.

Priority: must.

### CT-U5 — Picker failure does not damage the review

Cancelling, closing, superseding, or failing a target query must affect only the
picker request. It must not clear the current comparison, substitute another
target, reset Review metadata, or leave a late result able to replace a newer
query.

Priority: must.

### CT-U6 — Packaged and development paths have the same behavior

The Swift development backend and packaged WKWebView must use the same native
Core, Bridge transport, `agentstudio-git`, and comparison-target contracts. Vite
may change only the physical URL mapping used to reach those contracts.

Priority: must.

### CT-U7 — Catalog production does not monopolize pane control

After the picker has been authorized to load its catalog, producing that
catalog must not prevent unrelated valid pane controls from completing. The
reviewer must remain able to use the current comparison and other pane controls
while branch choices are being produced, even when Git discovery or catalog
materialization is slow.

A catalog-production failure remains local to that picker load. It must not
occupy or reopen the query control operation after authorization has completed.

Priority: must.

## Confirmed boundary

In scope:

- comparison-target discovery and picker loading;
- compact current-comparison metadata;
- the existing command and content routes;
- bounded `agentstudio-git` target discovery;
- a virtualized Base UI/shadcn-style branch selector;
- production-backed development-server and packaged-app proof.

Out of scope:

- changing comparison semantics or the current Base Branch presentation;
- changing durable comparison intent in `core.sqlite`;
- a target cache, persistent or cross-pane service, generalized producer
  framework, new transport, or new metadata subscription;
- dynamic producer plugins or runtime producer registration;
- network fetch, full Git history browsing, pagination, or a general Git client;
- annotation storage, comments, delivery, or agent IPC;
- staged/unstaged comparison redesign.

## Success

The correction succeeds when Review loads from compact current state, opening
the comparison picker performs one bounded foreground query through the
established command/content path regardless of remembered mode, switching to
Branch can use the preloaded result immediately, a production-scale catalog
remains searchable and keyboard operable without rendering the complete list,
unrelated pane controls can complete while catalog production is in flight, and
cancellation or failure leaves the displayed comparison untouched.
