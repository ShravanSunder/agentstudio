export type TranscriptTier = "full" | "compact" | "phone";

type TranscriptRowKind =
  | "blank"
  | "user-band"
  | "assistant-text"
  | "tool-call"
  | "tool-result"
  | "diff-removed"
  | "diff-added"
  | "codex-action"
  | "codex-detail"
  | "codex-prose"
  | "cursor";

export type TranscriptRow = {
  readonly kind: TranscriptRowKind;
  readonly text: string;
  readonly tiers: readonly TranscriptTier[];
};

const allTiers = ["full", "compact", "phone"] as const;
const desktopTiers = ["full", "compact"] as const;

export const claudeTranscript: readonly TranscriptRow[] = [
  { kind: "blank", text: "", tiers: ["full"] },
  { kind: "user-band", text: "› fix the sidebar filter ordering", tiers: ["full"] },
  { kind: "tool-call", text: "● Update(src/sidebar/filter.ts)", tiers: ["full"] },
  { kind: "tool-result", text: "  ⎿ Added 8 lines, removed 3 lines", tiers: ["full"] },
  { kind: "diff-removed", text: "45 - if (!query) return rows;", tiers: ["full"] },
  {
    kind: "diff-added",
    text: "45 + if (!query) return pinnedFirst(rows);",
    tiers: ["full"],
  },
  { kind: "blank", text: "", tiers: ["full"] },
  { kind: "user-band", text: "› set up Agent Studio for me", tiers: allTiers },
  { kind: "assistant-text", text: "● I'll install it with Homebrew.", tiers: allTiers },
  {
    kind: "tool-call",
    text: "● Bash(brew tap ShravanSunder/agentstudio && brew install --cask agent-studio)",
    tiers: desktopTiers,
  },
  { kind: "tool-call", text: "● Bash(brew install --cask agent-studio)", tiers: ["phone"] },
  { kind: "tool-result", text: "  ⎿ ✓ Ready. Copy it below ↓", tiers: allTiers },
  { kind: "cursor", text: "▌", tiers: allTiers },
];

export const codexTranscript: readonly TranscriptRow[] = [
  { kind: "blank", text: "", tiers: desktopTiers },
  { kind: "user-band", text: "› route leases through the controller", tiers: desktopTiers },
  { kind: "blank", text: "", tiers: ["full"] },
  { kind: "codex-action", text: "• Explored", tiers: ["full"] },
  { kind: "codex-detail", text: "  └ Read src/lease.ts", tiers: ["full"] },
  { kind: "blank", text: "", tiers: ["full"] },
  { kind: "codex-action", text: "• Ran", tiers: desktopTiers },
  { kind: "codex-detail", text: "  └ pnpm test lease", tiers: desktopTiers },
  { kind: "codex-detail", text: "  └ 14 passed · 0 failed · 3.1s", tiers: desktopTiers },
  { kind: "blank", text: "", tiers: desktopTiers },
  {
    kind: "codex-prose",
    text: "• Leases now route through the controller client.",
    tiers: desktopTiers,
  },
];
