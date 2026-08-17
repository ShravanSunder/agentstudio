Follow-up round (you have full history of this session — the contract, your validation table, the item 9 FAIL).

Resolve contract item 9 ONLY: the PR chip "⑂N" must be shown whenever a repo has N>0 open PRs and must never disappear. Your validation failed for lack of a positive PR-count fact in the fixture environment.

Do:
1. First check for existing automated proof: a test that renders the worktree/repo row with a positive PR count and asserts the chip. If missing, add one (focused suite, green).
2. Produce live visual evidence: launch the debug app (mise run run-debug-observability -- --detach, background, no focus stealing) with a repo that has real open PRs — the main agent-studio checkout at /Users/shravansunder/Documents/dev/project-dev/agent-studio has several open PRs — or inject the PR-count fact through the established enrichment path if app registration of that repo is not feasible in the debug identity. Capture the rendered "⑂N" chip in By Repo AND in the pane-row chip line (items 6/9), save to tmp-screenshots/contract-final/16-pr-chip-live.png (and one per surface). TERM the app after.
3. Update the validation table in tmp-RESULT.md: item 9 with the new evidence. Commit + push (draft PR #296).

Final output: the updated item-9 row only.
