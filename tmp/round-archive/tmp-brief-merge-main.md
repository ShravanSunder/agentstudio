Final step of this round (owner-directed): bring in origin/main — it has styling changes (design tokens, dark appearance) that this feature should sit on.

1. git fetch origin && git merge origin/main (merge, not rebase — this branch is a shared draft PR). Resolve conflicts preserving BOTH the contract behaviors and main's new styling/tokens; where main introduced new style tokens that overlap AppStyles values you used, adopt main's tokens.
2. Rebuild, re-run focused suites + mise run lint; fix fallout.
3. Re-capture the final contract evidence set on the MERGED build (the full 19-item screenshot sweep in one app launch — this becomes the canonical evidence, superseding earlier partial shots).
4. Update the validation table against the merged build. Commit + push (#296).

Do this only AFTER items 18 and 19 (already queued) are complete.
