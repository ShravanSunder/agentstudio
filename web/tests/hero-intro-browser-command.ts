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

interface HeroWindowRect {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
}

export interface HeroPlaybackObservation {
  readonly midIntroWasPlaying: boolean;
  readonly midIntroHorizontalOverflow: number;
  readonly resizeSettledEvents: number;
  readonly resizeProgress: number;
  readonly resizeInlineStyles: number;
  readonly resizeInlineStyleElements: readonly string[];
  readonly resizeFourthPlanes: number;
  readonly resizedWindow: HeroWindowRect;
  readonly freshNarrowWindow: HeroWindowRect;
  readonly afterSecondResizeWindow: HeroWindowRect;
  readonly freshWideWindow: HeroWindowRect;
  readonly afterSecondResizeInlineStyles: number;
  readonly reducedMotionCreatedTimeline: boolean;
  readonly keydownSettledEvents: number;
}

export const verifyHeroIntroPlayback = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<HeroPlaybackObservation> => {
    const introPage = await context.newPage();
    const freshNarrowPage = await context.newPage();
    const freshWidePage = await context.newPage();
    const keydownPage = await context.newPage();
    await Promise.all(
      [introPage, freshNarrowPage, freshWidePage, keydownPage].map(async (applicationPage) => {
        await applicationPage.route(/\.(mp4|webm)(\?|$)/u, async (route) => {
          await route.abort();
        });
      }),
    );
    const observe = (): {
      rect: HeroWindowRect;
      inlineStyles: number;
      inlineStyleElements: string[];
      fourthPlanes: number;
      progress: number;
    } => {
      const root = document.querySelector<HTMLElement>("[data-hero-intro-root]");
      const windowNode = root?.querySelector<HTMLElement>("[data-hero-terminal-window]");
      if (root === null || windowNode === null || root === undefined || windowNode === undefined) {
        throw new Error("Hero intro is missing");
      }
      const targets = root.querySelectorAll<HTMLElement>(
        "[data-hero-intro-copy], [data-hero-icon-stack], [data-hero-icon-front], [data-hero-icon-rear], [data-hero-icon-cursor], [data-hero-terminal-window], [data-hero-intro-content], [data-hero-intro-install], [data-hero-intro-description], [data-hero-intro-glow], [data-hero-intro-typed-input], [data-hero-intro-spinner], .hero-transcript-row",
      );
      const rect = windowNode.getBoundingClientRect();
      return {
        rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
        inlineStyles: [...targets].filter((target) => target.hasAttribute("style")).length,
        inlineStyleElements: [...targets]
          .filter((target) => target.hasAttribute("style"))
          .map(
            (target) => `${target.tagName}.${target.className}: ${target.getAttribute("style")}`,
          ),
        fourthPlanes: root.querySelectorAll("[data-hero-intro-fourth-plane]").length,
        progress: Number(root.getAttribute("data-hero-intro-progress")),
      };
    };
    try {
      await introPage.setViewportSize({ width: 1600, height: 1000 });
      await introPage.goto(pageUrl, { waitUntil: "commit" });
      await introPage.waitForSelector('[data-hero-intro-state="playing"]');
      const midIntroWasPlaying = await introPage.evaluate(
        () =>
          document
            .querySelector("[data-hero-intro-root]")
            ?.getAttribute("data-hero-intro-state") === "playing",
      );
      const midIntroHorizontalOverflow = await introPage.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      );
      await introPage.evaluate(() => {
        const root = document.querySelector("[data-hero-intro-root]");
        root?.setAttribute("data-test-settled-events", "0");
        root?.addEventListener("hero-intro-settled", () => {
          root.setAttribute(
            "data-test-settled-events",
            String(Number(root.getAttribute("data-test-settled-events")) + 1),
          );
        });
      });
      await introPage.setViewportSize({ width: 1100, height: 1000 });
      await introPage.waitForSelector('[data-hero-intro-state="settled"]');
      const resized = await introPage.evaluate(observe);
      const resizeSettledEvents = await introPage.evaluate(() =>
        Number(
          document
            .querySelector("[data-hero-intro-root]")
            ?.getAttribute("data-test-settled-events"),
        ),
      );

      await freshNarrowPage.emulateMedia({ reducedMotion: "reduce" });
      await freshNarrowPage.setViewportSize({ width: 1100, height: 1000 });
      await freshNarrowPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      const narrow = await freshNarrowPage.evaluate(observe);
      const reducedMotionCreatedTimeline = await freshNarrowPage.evaluate(
        () =>
          document
            .querySelector("[data-hero-intro-root]")
            ?.hasAttribute("data-hero-intro-timeline-created") ?? false,
      );

      await introPage.setViewportSize({ width: 1600, height: 1000 });
      const afterSecondResize = await introPage.evaluate(observe);
      await freshWidePage.emulateMedia({ reducedMotion: "reduce" });
      await freshWidePage.setViewportSize({ width: 1600, height: 1000 });
      await freshWidePage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      const wide = await freshWidePage.evaluate(observe);

      await keydownPage.setViewportSize({ width: 1600, height: 1000 });
      await keydownPage.goto(pageUrl, { waitUntil: "commit" });
      await keydownPage.waitForSelector('[data-hero-intro-state="playing"]');
      await keydownPage.evaluate(() => {
        const root = document.querySelector("[data-hero-intro-root]");
        root?.setAttribute("data-test-settled-events", "0");
        root?.addEventListener(
          "hero-intro-settled",
          () => {
            root.setAttribute("data-test-settled-events", "1");
          },
          { once: true },
        );
      });
      await keydownPage.keyboard.press("ArrowDown");
      await keydownPage.waitForSelector('[data-hero-intro-state="settled"]');
      const keydownSettledEvents = await keydownPage.evaluate(() =>
        Number(
          document
            .querySelector("[data-hero-intro-root]")
            ?.getAttribute("data-test-settled-events"),
        ),
      );
      return {
        midIntroWasPlaying,
        midIntroHorizontalOverflow,
        resizeSettledEvents,
        resizeProgress: resized.progress,
        resizeInlineStyles: resized.inlineStyles,
        resizeInlineStyleElements: resized.inlineStyleElements,
        resizeFourthPlanes: resized.fourthPlanes,
        resizedWindow: resized.rect,
        freshNarrowWindow: narrow.rect,
        afterSecondResizeWindow: afterSecondResize.rect,
        freshWideWindow: wide.rect,
        afterSecondResizeInlineStyles: afterSecondResize.inlineStyles,
        reducedMotionCreatedTimeline,
        keydownSettledEvents,
      };
    } finally {
      await Promise.all([
        introPage.close(),
        freshNarrowPage.close(),
        freshWidePage.close(),
        keydownPage.close(),
      ]);
    }
  },
);
