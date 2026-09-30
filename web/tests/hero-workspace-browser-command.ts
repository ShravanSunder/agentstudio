import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface HeroWorkspaceObservation {
  readonly text: string;
  readonly header: string;
  readonly footer: string;
  readonly worktreeRows: readonly string[];
}

export const verifyHeroWorkspace = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<HeroWorkspaceObservation> => {
    const page = await context.newPage();
    try {
      await page.setViewportSize({ width: 1600, height: 1000 });
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
      return await page.evaluate((): HeroWorkspaceObservation => {
        const root = document.querySelector<HTMLElement>("[data-hero-intro-root]");
        if (root === null) throw new Error("Hero workspace is missing");
        return {
          text: root.textContent ?? "",
          header: root.querySelector(".hero-codex-startup")?.textContent ?? "",
          footer: root.querySelector(".hero-codex-status")?.textContent ?? "",
          worktreeRows: [
            ...root.querySelectorAll<HTMLElement>(
              ".hero-terminal-pane--codex [data-hero-worktree-row]",
            ),
          ].map((row) => row.textContent?.trim() ?? ""),
        };
      });
    } finally {
      await page.close();
    }
  },
);
