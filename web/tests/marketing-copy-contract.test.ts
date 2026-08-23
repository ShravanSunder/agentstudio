import { describe, expect, it } from "vitest";

import { marketingCopy } from "../src/marketing-copy";

describe("marketing copy", () => {
  it("keeps the approved hero message and product-name accent boundary", () => {
    expect(marketingCopy.hero).toMatchObject({
      eyebrow: "Native macOS. Repository-aware. Terminal-first.",
      headline: "Run a dozen agents. Know where each one is working.",
      headlineLead: "Run a dozen agents.",
      headlineTail: "Know where each one is working.",
      description:
        "Agent Studio is an opinionated native macOS terminal workspace for coding agents. It watches your code folders, discovers their repositories and worktrees, and keeps each agent's repo, branch, and directory visible. Your agents run in Ghostty terminals, with Files, Review, and annotations right beside them.",
    });

    expect(`${marketingCopy.productName}${marketingCopy.hero.descriptionAfterProductName}`).toBe(
      marketingCopy.hero.description,
    );
  });

  it("uses headline-style punctuation for supporting-feature titles", () => {
    const supportingTitles = marketingCopy.featureDetails.items.map(
      (item) => `${item.title.beforeAccent}${item.title.accent}${item.title.afterAccent}`,
    );

    expect(supportingTitles.every((title) => !title.endsWith("."))).toBe(true);
  });
});
