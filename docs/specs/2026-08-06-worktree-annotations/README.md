# Worktree Annotations

This folder is the sole current design entry point for the Worktree
Annotations delivery sequence.

The first bounded design cycle is the Review comparison prerequisite. Its core
comparison contract, accepted basis delta, and focused target-loading correction
are:

```text
core comparison contract
  Requirements → Specification → Program Design

accepted comparison-basis delta

target-loading correction
  Requirements → Specification → Program Design
```

- Core comparison contract:
  [`pr0-user-requirements.md`](./pr0-user-requirements.md) →
  [`pr0-specification.md`](./pr0-specification.md) →
  [`pr0-program-design.md`](./pr0-program-design.md)
- Accepted comparison-basis delta:
  [`2026-08-10-pr0-review-comparison-basis.md`](../2026-08-10-pr0-review-comparison-basis/2026-08-10-pr0-review-comparison-basis.md)
- Target-loading correction:
  [`user-requirements.md`](../2026-08-10-bridge-review-comparison-target-loading/user-requirements.md) →
  [`specification.md`](../2026-08-10-bridge-review-comparison-target-loading/specification.md) →
  [`program-design.md`](../2026-08-10-bridge-review-comparison-target-loading/program-design.md)

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

## Comparison-selector loading boundary

Review initialization does not load branch candidates. Activating Branch mode
requests one recent, bounded catalog through the existing command/content path
and filters that finite response locally.

- Do not share, persist, prefetch, or subscribe to the catalog.
- Do not introduce a watcher, cache service, or new transport.
- Keep searchable commit history separate; PR0 accepts an exact commit OID.

The earlier folders are deprecated source material only:

- `../2026-08-03-worktree-annotations/`
- `../2026-07-30-review-comments/`

Nothing in those folders is current requirements, Specification, Program
Design, acceptance authority, or implementation authority. Useful evidence or
ideas must be re-derived against current owner decisions and current source
before entering this folder.
