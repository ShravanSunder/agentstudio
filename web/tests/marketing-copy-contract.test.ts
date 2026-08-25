import { describe, expect, it } from "vitest";

import { marketingCopy } from "../src/marketing-copy";

describe("marketing copy", () => {
  it("keeps the approved hero message and headline accent boundary", () => {
    expect(marketingCopy.hero).toMatchObject({
      eyebrow: "Native macOS. Repo-aware. Terminal-first.",
      headline: "Run dozens of agents in one workspace. Stay oriented. Miss nothing.",
      headlineSetupFirst: "Run dozens of agents",
      headlineSetupSecondBeforeAccent: "in one ",
      headlineSetupSecondAccent: "workspace.",
      headlinePayoff: "Stay oriented. Miss nothing.",
      description:
        "Agent Studio is a native macOS workspace for coding agents, with your repositories and worktrees within reach. Your agents run in Ghostty terminals with files and diffs right beside them.",
    });

    expect(marketingCopy.hero.headlineSetupFirst).toBe("Run dozens of agents");
    expect(
      `${marketingCopy.hero.headlineSetupSecondBeforeAccent}${marketingCopy.hero.headlineSetupSecondAccent}`,
    ).toBe("in one workspace.");
    expect(marketingCopy.hero.headlinePayoff).toBe("Stay oriented. Miss nothing.");
    expect("headlinePayoffAccent" in marketingCopy.hero).toBe(false);
  });

  it("uses headline-style punctuation for supporting-feature titles", () => {
    const supportingTitles = marketingCopy.featureDetails.items.map(
      (item) => `${item.title.beforeAccent}${item.title.accent}${item.title.afterAccent}`,
    );

    expect(supportingTitles.every((title) => !title.endsWith("."))).toBe(true);
  });

  it("opens the product slideshow with the concise repository-watching promise", () => {
    expect(marketingCopy.stories.watchFolders).toMatchObject({
      label: "Watch your repos",
      description: "Agent Studio watches your repos. Stay oriented across every repo and worktree.",
      phoneDescription:
        "Agent Studio watches your repos. You can easily create or view terminals in all your repos.",
    });
  });
});
