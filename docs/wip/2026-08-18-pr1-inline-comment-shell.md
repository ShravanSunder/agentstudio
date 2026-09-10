# PR1 Inline Comment Shell — Superseded Experiment

Status: superseded; not an implementation contract
Current inventory: [`2026-08-18-pr1-inline-comments-ui-remediation.md`](./2026-08-18-pr1-inline-comments-ui-remediation.md)

This file records the disposition of the earlier inline-`Collapsible`
experiment so its checked tasks cannot be mistaken for current completion
evidence.

The experiment assumed:

- focus or compact-body click expanded chronology;
- earlier messages expanded inline between M-summary and M-last;
- the thread overlay host should be removed.

The current PR1 Requirements, Specification, and Program Design supersede all
three assumptions:

```text
compact focus or body click
  └─ activate the comment and paint its Pierre range only

explicit Expand / Edit / Reply
  └─ open an anchored floating complete-thread overlay
       ├─ M1 ... Mn exactly once
       ├─ reply/edit authoring
       ├─ bounded internal scrolling
       └─ no Pierre row-height or scroll-anchor change
```

Current proof must come from the parent remediation inventory and current
focused/browser tests. Screenshots or passing checks from the superseded inline
disclosure experiment are historical evidence only.
