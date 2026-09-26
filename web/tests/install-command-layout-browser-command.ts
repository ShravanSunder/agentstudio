import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface InstallBoxObservation {
  readonly width: number;
  readonly boxes: readonly {
    readonly codeOverflow: number;
    readonly copyWidth: number;
    readonly commandRowHeights: readonly number[];
    readonly lineHeight: number;
    readonly compact: boolean;
    readonly copied: string;
  }[];
}

export const verifyInstallCommandLayout = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<InstallBoxObservation[]> => {
    const page = await context.newPage();
    await page.addInitScript((): void => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          writeText: (value: string): Promise<void> => {
            (window as Window & { __copiedInstall?: string }).__copiedInstall = value;
            return Promise.resolve();
          },
        },
      });
    });
    try {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.setViewportSize({ width: 320, height: 844 });
      const response = await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
      if (response === null || !response.ok()) throw new Error("Install page failed to load");
      await page.locator("[data-install-command-root]").first().waitFor();
      const observations: InstallBoxObservation[] = [];
      for (const width of [320, 360, 390, 430, 620, 820, 1024]) {
        await page.setViewportSize({ width, height: 844 });
        const measurements = await page.evaluate(async () => {
          await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
          const roots = [...document.querySelectorAll<HTMLElement>("[data-install-command-root]")];
          if (roots.length !== 2) throw new Error("Expected hero and CTA install boxes");
          return roots.map((root) => {
            const code = root.querySelector<HTMLElement>("code");
            const button = root.querySelector<HTMLButtonElement>("[data-install-copy]");
            if (code === null || button === null) throw new Error("Install box markup incomplete");
            button.click();
            return {
              codeOverflow: code.scrollWidth - code.clientWidth,
              copyWidth: button.getBoundingClientRect().width,
              commandRowHeights: [
                ...code.querySelectorAll<HTMLElement>(".install-command__line"),
              ].map((line) => line.getBoundingClientRect().height),
              lineHeight: Number.parseFloat(getComputedStyle(code).lineHeight),
              compact: root.hasAttribute("data-compact-copy"),
              copied: (window as Window & { __copiedInstall?: string }).__copiedInstall ?? "",
            };
          });
        });
        observations.push({ width, boxes: measurements });
      }
      return observations;
    } finally {
      await page.close();
    }
  },
);
