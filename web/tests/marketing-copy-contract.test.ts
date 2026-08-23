import { describe, expect, it } from "vitest";

import { marketingCopy } from "../src/marketing-copy";

describe("marketing copy", () => {
  it("keeps the approved hero message and headline accent boundary", () => {
    expect(marketingCopy.hero).toMatchObject({
      eyebrow: "Native macOS. Repository-aware. Terminal-first.",
      headline: "Run dozens of agents in one workspace. Stay oriented. Miss nothing.",
      headlineLead: "Run dozens of agents",
      headlineMiddleBeforeAccent: "in one ",
      headlineMiddleAccent: "workspace.",
      headlineTailBeforeAccent: "Stay ",
      headlineTailAccent: "oriented",
      headlineTailAfterAccent: ". Miss nothing.",
      description:
        "Agent Studio is a native macOS terminal workspace for coding agents, with your repositories and worktrees always within reach. Your agents run in Ghostty terminals, with Files, Review, and annotations right beside them.",
    });

    expect(marketingCopy.hero.headlineLead).toBe("Run dozens of agents");
    expect(
      `${marketingCopy.hero.headlineMiddleBeforeAccent}${marketingCopy.hero.headlineMiddleAccent}`,
    ).toBe("in one workspace.");
    expect(
      `${marketingCopy.hero.headlineTailBeforeAccent}${marketingCopy.hero.headlineTailAccent}${marketingCopy.hero.headlineTailAfterAccent}`,
    ).toBe("Stay oriented. Miss nothing.");
  });

  it("uses headline-style punctuation for supporting-feature titles", () => {
    const supportingTitles = marketingCopy.featureDetails.items.map(
      (item) => `${item.title.beforeAccent}${item.title.accent}${item.title.afterAccent}`,
    );

    expect(supportingTitles.every((title) => !title.endsWith("."))).toBe(true);
  });

  it("opens the product slideshow with the concise Watch folders promise", () => {
    expect(marketingCopy.stories.watchFolders).toMatchObject({
      label: "Watch folders",
      description: "Agent Studio watches your repos. Stay oriented across every repo and worktree.",
      phoneDescription:
        "Agent Studio watches your repos. Stay oriented across every repo and worktree.",
    });
  });
});
