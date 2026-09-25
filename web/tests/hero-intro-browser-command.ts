import { defineBrowserCommand } from "@vitest/browser-playwright";

export interface HeroLayoutObservation {
  readonly viewport: string;
  readonly rowsInsideWindow: boolean;
  readonly installBottom: number;
  readonly windowLeft: number;
  readonly windowRight: number;
  readonly windowTop: number;
  readonly windowBottom: number;
  readonly headlineBottom: number;
  readonly columnTop: number;
  readonly rootTop: number;
  readonly appLeft: number;
  readonly appRight: number;
  readonly cursorCount: number;
  readonly documentWidth: number;
  readonly viewportWidth: number;
  readonly codexVisible: boolean;
  readonly canvasColor: string;
  readonly visibleBashRows: number;
  readonly earlierExchangeVisible: boolean;
  readonly overflowElements: readonly string[];
}

export const verifyHeroIntroLayout = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    viewports: readonly { readonly width: number; readonly height: number }[],
  ): Promise<HeroLayoutObservation[]> => {
    const observations: HeroLayoutObservation[] = [];
    for (const viewport of viewports) {
      const applicationPage = await context.newPage();
      try {
        await applicationPage.emulateMedia({ reducedMotion: "reduce" });
        await applicationPage.setViewportSize(viewport);
        await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
        observations.push(
          await applicationPage.evaluate(
            async ({ width, height }): Promise<HeroLayoutObservation> => {
              await document.fonts.ready;
              const windowNode = document.querySelector<HTMLElement>("[data-hero-terminal-window]");
              const appFrame = document.querySelector<HTMLElement>("[data-hero-app-frame]");
              const install = document.querySelector<HTMLElement>(
                ".hero [data-install-command-root]",
              );
              const codex = document.querySelector<HTMLElement>(".hero-terminal-pane--codex");
              if (windowNode === null || appFrame === null || install === null || codex === null) {
                throw new Error("Hero intro layout is incomplete");
              }
              const windowRect = windowNode.getBoundingClientRect();
              const appRect = appFrame.getBoundingClientRect();
              const padding = parseFloat(getComputedStyle(windowNode).borderTopWidth);
              const visibleRows = [
                ...windowNode.querySelectorAll<HTMLElement>("[data-transcript-tier]"),
              ].filter((row) => row.getClientRects().length > 0);
              return {
                viewport: `${width}x${height}`,
                rowsInsideWindow: visibleRows.every((row) => {
                  const rect = row.getBoundingClientRect();
                  return (
                    rect.top >= windowRect.top + padding - 1 &&
                    rect.bottom <= windowRect.bottom - padding + 1
                  );
                }),
                installBottom: install.getBoundingClientRect().bottom,
                windowLeft: windowRect.left,
                windowRight: windowRect.right,
                windowTop: windowRect.top,
                windowBottom: windowRect.bottom,
                headlineBottom:
                  document.querySelector("#hero-title")?.getBoundingClientRect().bottom ?? NaN,
                columnTop:
                  document.querySelector(".hero-intro-column")?.getBoundingClientRect().top ?? NaN,
                rootTop:
                  document.querySelector(".hero-intro-root")?.getBoundingClientRect().top ?? NaN,
                appLeft: appRect.left,
                appRight: appRect.right,
                cursorCount: document.querySelectorAll("[data-hero-cursor]").length,
                documentWidth: document.documentElement.scrollWidth,
                viewportWidth: document.documentElement.clientWidth,
                codexVisible: getComputedStyle(codex).display !== "none",
                canvasColor: getComputedStyle(document.body).backgroundColor,
                visibleBashRows: visibleRows.filter((row) => row.textContent?.includes("Bash("))
                  .length,
                earlierExchangeVisible: visibleRows.some((row) =>
                  row.textContent?.includes("sidebar filter ordering"),
                ),
                overflowElements: [...document.querySelectorAll<HTMLElement>("body *")]
                  .filter((element) => element.getBoundingClientRect().right > width + 1)
                  .slice(0, 10)
                  .map(
                    (element) =>
                      `${element.tagName}.${element.className} ${Math.round(element.getBoundingClientRect().right)}`,
                  ),
              };
            },
            viewport,
          ),
        );
      } finally {
        await applicationPage.close();
      }
    }
    return observations;
  },
);
