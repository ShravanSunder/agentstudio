SEAM READY — the item-5 lastOutputLine implementation is complete, tested (69/69 focused + full swift lane green, lint 0), and committed on local branch feat/item5-last-output-line (e37bf41f0; worktrees share refs, you can merge it directly).

Do now, before the master gate:
1. When your working tree is clean (commit current slice first), run: git merge feat/item5-last-output-line — expect clean or trivial (it branched from this branch's HEAD 7188d484e). Resolve any conflict preserving both sides' intent.
2. Re-run focused suites touching the seam: mise run test:swift -- --filter "TerminalActivityProjectorTests|InboxPromoterTests|TerminalLastOutputLineContractTests" plus your sidebar suites; mise run lint.
3. Create the marker file tmp-brief-seam-merged.md with the merge commit hash — this releases your master-gate hold.
4. The master gate's item C (real L2 content) is now provable: in the live sweep, run a real command in a real pane (e.g. `ls -la` or a short build) and capture L2 showing the actual output line in All Panes AND By Tab. That completes the seam's deferred live proof.
