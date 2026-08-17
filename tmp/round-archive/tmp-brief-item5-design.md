ITEM 5 — DESIGN RATIFIED BY OWNER-SIDE INVESTIGATION. Supersedes the "stop if new lane needed" clause: this is NOT a new lane, it is a bounded field on the existing settled-activity event. Implement exactly this seam:

FINDING (verified): TerminalSettledActivity carries only counts (latestRows: Int); InboxPromoter hardcodes body: nil. No text flows anywhere today — that is why every row says "output activity".

THE SEAM:
1. At settle-emission time in the Terminal-side projector (the existing debounced burst-settle point, NOT per-event), read the last viewport lines via libghostty: `ghostty_surface_read_text(surface, ghostty_selection_s{viewport-relative points for the last ~5 rows}, &result)` then `ghostty_surface_free_text`. This is the same API the upstream macOS host uses for accessibility caching. One call per settled burst only — never per output event, never on a timer.
2. Contract at source: from the read text take the LAST non-empty trimmed line; strip control/escape residue; bound to ≤120 UTF-8 chars; drop if it equals the shell prompt alone. Suppress if unchanged from the previous settle for that pane.
3. Extend TerminalSettledActivity with `lastOutputLine: String?` (bounded, contracted, Sendable). Same event, same cadence — this complies with the high-volume source rule (Terminal-local contraction before MainActor/EventBus publication).
4. InboxPromoter.promoteSettledActivity: body = activity.lastOutputLine (nil-safe; keep existing bounded-text policy via InboxNotificationTextPolicy).
5. Row L2 logic unchanged — it already prefers a content-bearing body; with real bodies flowing, "output activity" becomes the rare genuine fallback.
6. Respect surface-call isolation: ghostty surface calls are MainActor-bound in this app; the settle point must hop appropriately if it isn't already there. Follow C-callback bridging rules (no pointer deref across async hops).
7. OTLP scrub rule: lastOutputLine is payload text — it must NOT be exported over OTLP. Keep it out of trace attributes entirely (counts only, as today).

Tests red-first: (a) settled activity with lastOutputLine → notification body populated and L2 shows it; (b) prompt-only/empty read → body nil → fallback; (c) bound enforcement (long line truncated); (d) unchanged-line suppression. Then live proof on the merged build: run a real command producing output in a real pane; screenshot L2 showing that actual line in All Panes AND By Tab. No synthetic notifications.

This closes item 5. It must be in the final sweep with every other item.
