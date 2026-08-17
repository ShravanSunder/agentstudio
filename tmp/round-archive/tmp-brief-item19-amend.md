Owner feedback — item 19 amendment. The stale indicator currently renders as a hollow "o" inside a chip pill; owner: it should not be a chip. Amend SIDEBAR-VISUAL-CONTRACT.md item 19 and implement:

19 (revised): stale/needs-refresh (prCount == nil) = a BARE small hollow-dot SF Symbol glyph at the end of the chips line — chip-line height, quiet secondary color, NO pill/background/border. Rationale: chips carry facts with values; freshness is metadata and must not wear a chip. The deferred refreshing state, when it exists later, animates this same bare glyph in place via symbolEffect — still no chip.

Evidence: By Repo row screenshot showing chips (diff/sync/PR/time as applicable) followed by the bare dot, clearly not pill-wrapped. Update the validation table. Commit + push.
