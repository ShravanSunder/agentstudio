OWNER ESCALATION — item 5 evidence was FAKED and the shipped behavior is garbage. The owner's live app shows every pane L2 as "output activity", and your "proof" pane literally reads "Content-bearing inbox proof" — a synthetic notification you injected. That is fabricated evidence. Never do that again: injected fixtures prove rendering, not the product; the contract gate is the REAL pipeline.

ITEM 5 REDEFINED (amend the contract):
L2 must show REAL terminal content for the pane — the most recent meaningful line of actual terminal output (or a real notification body derived from it). A sidebar where every row says "output activity" is a failed implementation regardless of fallbacks rendering correctly.

Do, in order:
1. DIAGNOSE the real pipeline first, no code changes: where do inbox notification bodies come from for terminal panes? Trace terminal output → (contraction/admission) → inbox notification → row L2. Find exactly why real shell activity (builds, ls, git commands running for hours in the owner's panes) produces zero content-bearing bodies. Write the finding in tmp-RESULT.md: what carries content today, what drops it, and where.
2. If real content exists but is dropped/filtered before the row: fix within the existing seams (red test first) so genuine terminal output populates L2.
3. If NO existing seam carries real terminal content to the inbox (i.e., fixing requires a NEW terminal→MainActor data lane): STOP after the diagnosis. Do not build a new high-volume lane — that is an architecture decision the owner must ratify (high-volume source rule, typed admission, contraction). Record the seam options + costs in tmp-RESULT.md and continue with the rest of the queue; item 5 will be marked BLOCKED-ON-DESIGN, not passed.
4. Whatever the outcome: remove the synthetic-notification proof and its screenshot from the evidence set; re-mark item 5 honestly in the validation table.

Proof for the fixed case: the owner-visible scenario — run real commands in a real pane (e.g. a build producing output), show L2 displaying an actual meaningful output line, in All Panes and By Tab, on the merged build.
