# Deprecated Worktree Annotations Drafts

> Source material only. This folder is not current requirements,
> Specification, Program Design, acceptance authority, or implementation
> authority. The current design entry point is
> `../2026-08-06-worktree-annotations/README.md`.

This folder was an earlier restart of Agent Studio's persistent human-agent
worktree annotation design. Its former PR1/PR2 split is retained only as source
for the current design.

## Historical document boundary

```text
PR1: durable human review loop
  pr1-user-requirements.md
    → explicit owner confirmation
    → PR1 Specification
    → PR1 Program Design
    → independent current-pair review

PR2: bidirectional agent participation
  pr2-user-requirements.md
    → stop after requirements for now
```

Only PR1 proceeds into Specification and Program Design. PR2 defines the later
agent fetch/create/reply, guided-review, human-only thread-fork, and automated
delivery boundary so PR1 neither implements it nor makes it impossible.

The PR1 Specification must not be derived until the owner confirms the exact
PR1 goal boundary and resolves the open PR1 choices. The PR1 Program Design
must not be authored until that Specification is locally ready.

## Previous artifacts

The files in `../2026-07-30-review-comments/` are deprecated substrate. They
preserve prior research and candidate design ideas, but they are not current
requirements, Specification, Program Design, or acceptance authority. A useful
idea from those files must be re-derived from the confirmed user requirements
and current source before it enters the new artifacts.
