# Worktree Annotations

This folder is the sole current design entry point for the Worktree
Annotations delivery sequence.

The first bounded design cycle is the Review comparison prerequisite:

```text
PR0 Requirements          PR0 Specification          PR0 Program Design
pr0-user-requirements.md → pr0-specification.md     → pr0-program-design.md
why and for whom          what must be observable     how Agent Studio realizes it
```

PR0 makes Review View show the work attributable to the selected worktree
against a visible, reviewer-selectable target. It also exposes trustworthy
comparison provenance for later annotation origins. PR0 does not implement
annotations.

The later sequence remains:

```text
PR1  durable human Worktree Annotations in File View and Review View
PR2  bidirectional agent participation and automated delivery
```

PR1 and PR2 require their own current Requirements identities and bounded
design cycles. The deprecated drafts below remain source material until those
cycles create new authoritative records.

## Deferred comparison-selector efficiency

PR0 loads branch candidates when the Compare Worktree control opens and filters
them locally. After PR0, consider sharing that transient catalog per worktree
instead of requesting it independently for each pane.

- Share one ref catalog per worktree across its tabs and panes.
- Coalesce concurrent requests for the same worktree.
- Refresh or invalidate through the existing Git refresh ownership.
- Do not introduce a separate watcher, cache service, or persistence system.
- Keep searchable commit history separate; PR0 accepts an exact commit OID.

The earlier folders are deprecated source material only:

- `../2026-08-03-worktree-annotations/`
- `../2026-07-30-review-comments/`

Nothing in those folders is current requirements, Specification, Program
Design, acceptance authority, or implementation authority. Useful evidence or
ideas must be re-derived against current owner decisions and current source
before entering this folder.
