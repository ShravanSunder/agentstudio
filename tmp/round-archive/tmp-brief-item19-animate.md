OWNER DECISION — item 19 amended again (supersedes the static-only deferral). The bare hollow-dot glyph for prCount == nil communicates nothing as a static circle. It represents a PENDING fact ("PR facts not yet fetched"), and pending is honestly communicated with a quiet loading animation. Amend SIDEBAR-VISUAL-CONTRACT.md item 19 and implement:

19 (final): when prCount == nil, render the bare glyph (still NO chip/pill) with a SUBTLE render-server animation via SF Symbol effects — use `.symbolEffect(.variableColor.iterative)` on a dotted-circle-style symbol (e.g. `circle.dotted` or similar) OR `.pulse` on the hollow dot, whichever reads as gentle "loading" at that tiny size. Requirements:
- Render-server only (symbolEffect). ZERO per-frame MainActor work. The rotationEffect+repeatForever ban stands — symbolEffect is the sanctioned mechanism.
- Subtle and non-disturbing: slow cadence, secondary color, small. It should be noticeable only when you look at it, never pull the eye from across the sidebar.
- Disappears entirely once prCount becomes known (chip logic unchanged: ⑂N if >0, nothing if 0).
- This is honest because nil == pending; do NOT invent an "actively refreshing" distinction — that part stays deferred.

Evidence: 3-4 frame burst at ~0.5s spacing showing the animation phases differ across frames (proves it animates), plus one shot after facts arrive showing the glyph gone. Pick the symbol/effect combo that looks best at row scale — you decide between variableColor and pulse per what reads better; note the choice in the validation table.
