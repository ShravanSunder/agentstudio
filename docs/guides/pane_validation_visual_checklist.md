# Pane Validation Visual Checklist

Use this checklist when validating pane drag/drop behavior in management mode.

## Required Scenarios

1. Drawer open + management mode on: background panes do not show hover affordances.
2. First outside click dismisses drawer; background interactions resume only after dismiss.
3. Drawer same-parent drag: preview marker shows and commit reorders drawer panes.
4. Drawer cross-parent drag: no preview marker and no commit.
5. Layout pane over tab bar: insertion marker only appears when planner-eligible.
6. Drawer pane over tab bar: insertion marker never appears and drop is rejected.

## Peekaboo Runbook (PID-Targeted Debug Build)

```bash
pkill -9 -f "AgentStudio"
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo app switch --to "PID:$PID"
peekaboo see --app "PID:$PID" --json
```

## Evidence Capture

For each scenario above, capture:

1. A screenshot or `peekaboo see --json` output.
2. A one-line pass/fail note with the scenario number.
3. If failed, the exact interaction path and observed mismatch.
