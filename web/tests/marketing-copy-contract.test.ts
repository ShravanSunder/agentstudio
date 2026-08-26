import { describe, expect, it } from "vitest";

import { marketingCopy } from "../src/marketing-copy";

describe("marketing copy", () => {
  it("keeps the approved hero message and two-line headline", () => {
    expect(marketingCopy.hero).toMatchObject({
      eyebrow: "Native macOS. Repo-aware. Terminal-first.",
      headline: "Run dozens of agents. Know where each one is working.",
      headlineSetup: "Run dozens of agents.",
      headlinePayoff: "Know where each one is working.",
      description:
        "Agent Studio is a native macOS IDE for parallel coding agents. It keeps each agent's terminal, files, and diffs with its repo and worktree.",
    });

    expect(marketingCopy.hero.headlineSetup).toBe("Run dozens of agents.");
    expect(marketingCopy.hero.headlinePayoff).toBe("Know where each one is working.");
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

  it("closes with the approved native macOS positioning", () => {
    expect(marketingCopy.finalCallToAction).toEqual({
      description: "Keep every agent tied to the repo and worktree it belongs to.",
      traits: "Native macOS. Repo-aware. Terminal-first.",
      technologyCredit: "👻 Built on Ghostty. ",
      creatorPrefix: "🛠️ Made by ",
      creatorName: "Shravan Sunder",
    });
  });
});
