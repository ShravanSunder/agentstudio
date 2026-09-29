import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { HeroWorkspaceObservation } from "./hero-workspace-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyHeroWorkspace(pageUrl: string): Promise<HeroWorkspaceObservation>;
  }
}

it("runs the hero Codex pane in the Agent Studio workspace", async () => {
  const observation = await commands.verifyHeroWorkspace(inject("siteHeaderBrowserTestUrl"));
  expect(observation.text).not.toMatch(/tool-portal|fix\/lease-client/u);
  expect(observation.header).toContain("directory: ~/agent-studio");
  expect(observation.footer).toContain("main");
  expect(observation.worktreeRows).toEqual([
    "└ ~/agent-studio  main",
    "└ ~/agent-studio.drawer  drawer-improvements",
    "└ ~/agent-studio.review  review-comments",
  ]);
});
