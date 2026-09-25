import { describe, expect, it } from "vitest";

import { claudeTranscript, codexTranscript } from "../src/hero-intro/hero-terminal-transcripts";

describe("hero terminal transcripts", () => {
  const rows = [...claudeTranscript, ...codexTranscript];

  it("assigns every row to a visible tier", () => {
    expect(rows.length).toBeGreaterThan(0);
    expect(rows.every((row) => row.tiers.length > 0)).toBe(true);
  });

  it("keeps the Bash call and ready result on phone", () => {
    const phone = claudeTranscript.filter((row) => row.tiers.includes("phone"));
    expect(phone.some((row) => row.kind === "tool-call" && row.text.includes("Bash("))).toBe(true);
    expect(phone.some((row) => row.kind === "tool-result" && row.text.includes("Ready."))).toBe(
      true,
    );
  });

  it("drops the earlier exchange in compact mode", () => {
    const compact = claudeTranscript.filter((row) => row.tiers.includes("compact"));
    expect(compact.some((row) => row.text.includes("sidebar filter ordering"))).toBe(false);
    expect(compact.some((row) => row.text.includes("set up Agent Studio"))).toBe(true);
  });

  it("has exactly one cursor row", () => {
    expect(rows.filter((row) => row.kind === "cursor")).toHaveLength(1);
  });
});
