import { describe, expect, it } from "vitest";

import {
  claudeFinaleTranscript,
  claudePreludeTranscript,
  codexTranscript,
} from "../src/hero-intro/hero-terminal-transcripts";

describe("hero terminal transcripts", () => {
  const rows = [...claudePreludeTranscript, ...claudeFinaleTranscript, ...codexTranscript];

  it("assigns every row to a visible tier", () => {
    expect(rows.length).toBeGreaterThan(0);
    expect(rows.every((row) => row.tiers.length > 0)).toBe(true);
  });

  it("keeps the Bash call and ready result on phone", () => {
    const phone = claudeFinaleTranscript.filter((row) => row.tiers.includes("phone"));
    expect(phone.some((row) => row.kind === "tool-call" && row.text.includes("Bash("))).toBe(true);
    expect(phone.some((row) => row.kind === "tool-result" && row.text.includes("Ready."))).toBe(
      true,
    );
  });

  it("gives every tier exactly one Bash tool call", () => {
    for (const tier of ["full", "compact", "phone"] as const) {
      const bashRows = claudeFinaleTranscript.filter(
        (row) => row.tiers.includes(tier) && row.kind === "tool-call" && row.text.includes("Bash("),
      );
      expect(bashRows, tier).toHaveLength(1);
    }
  });

  it("drops the earlier exchange in compact mode", () => {
    const compact = claudeFinaleTranscript.filter((row) => row.tiers.includes("compact"));
    expect(compact.some((row) => row.text.includes("sidebar filter ordering"))).toBe(false);
    expect(compact.some((row) => row.text.includes("set up Agent Studio"))).toBe(true);
  });

  it("keeps the finished phone flow in order", () => {
    const phone = claudeFinaleTranscript.filter((row) => row.tiers.includes("phone"));
    const text = phone.map((row) => row.text).join("\n");
    const sequence = [
      "set up Agent Studio",
      "Bash(",
      "Installing agent-studio",
      "Ready.",
      "map the worktrees",
      "git worktree list",
      "3 worktrees",
    ];
    let priorIndex = -1;
    for (const fragment of sequence) {
      const index = text.indexOf(fragment);
      expect(index, fragment).toBeGreaterThan(priorIndex);
      priorIndex = index;
    }
  });
});
