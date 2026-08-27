import { defineBrowserCommand } from "@vitest/browser-playwright";

import type {
  SiteHeaderScrollStabilityResult,
  SiteHeaderStableState,
} from "./site-header-browser-contract.ts";

export const verifySiteHeaderScrollStability = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<SiteHeaderScrollStabilityResult> => {
    const applicationPage = await context.newPage();
    try {
      await applicationPage.setViewportSize({ height: 844, width: 390 });
      const response = await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
      if (response === null || !response.ok()) {
        throw new Error(
          `Header browser-test page failed to load: ${applicationPage.url()} (${String(response?.status())})`,
        );
      }
      await applicationPage.waitForSelector("[data-site-header-anchor]", { state: "attached" });
      return await applicationPage.evaluate(async (): Promise<SiteHeaderScrollStabilityResult> => {
        const pageDocument = document;
        const pageWindow = window;

        interface HeaderElements {
          readonly anchor: HTMLElement;
          readonly frost: HTMLElement;
          readonly header: HTMLElement;
        }

        const requiredHeaderElements = (): HeaderElements => {
          const anchor = pageDocument.querySelector<HTMLElement>("[data-site-header-anchor]");
          const frost = pageDocument.querySelector<HTMLElement>(".site-header-frost");
          const header = pageDocument.querySelector<HTMLElement>("[data-site-header]");
          if (anchor === null || frost === null || header === null) {
            throw new Error("Rendered page is missing the site-header stability fixture");
          }
          return { anchor, frost, header };
        };

        const readStableState = (elements: HeaderElements): SiteHeaderStableState => {
          const anchorBounds = elements.anchor.getBoundingClientRect();
          const headerBounds = elements.header.getBoundingClientRect();
          const visualState = elements.header.dataset["visualState"];
          if (visualState !== "floating" && visualState !== "resting") {
            throw new Error(`Unexpected site-header visual state: ${String(visualState)}`);
          }
          return {
            anchorHeight: anchorBounds.height,
            headerHeight: headerBounds.height,
            headerTop: headerBounds.top,
            headerWidth: headerBounds.width,
            scrollY: pageWindow.scrollY,
            visualState,
          };
        };

        const elements = requiredHeaderElements();
        pageDocument.documentElement.style.scrollBehavior = "auto";
        const anchorHeight = elements.anchor.getBoundingClientRect().height;
        let stateChangeCount = 0;
        const stateObserver = new MutationObserver((records): void => {
          stateChangeCount += records.filter(
            (record): boolean => record.attributeName === "data-visual-state",
          ).length;
        });
        stateObserver.observe(elements.header, {
          attributeFilter: ["data-visual-state"],
          attributes: true,
        });

        pageWindow.scrollTo(0, 33);
        await new Promise<void>((resolve, reject): void => {
          const timeout = pageWindow.setTimeout(
            (): void => reject(new Error("Floating header did not reach a stable state")),
            2_000,
          );
          const inspect = (): void => {
            const state = readStableState(elements);
            if (
              state.visualState === "floating" &&
              state.scrollY === 33 &&
              state.anchorHeight === anchorHeight &&
              elements.header
                .getAnimations()
                .every((animation): boolean => ["finished", "idle"].includes(animation.playState))
            ) {
              pageWindow.clearTimeout(timeout);
              resolve();
              return;
            }
            pageWindow.requestAnimationFrame(inspect);
          };
          inspect();
        });
        const floating = readStableState(elements);

        pageWindow.scrollTo(0, 0);
        await new Promise<void>((resolve, reject): void => {
          const timeout = pageWindow.setTimeout(
            (): void => reject(new Error("Resting header did not reach a stable state")),
            2_000,
          );
          const inspect = (): void => {
            const state = readStableState(elements);
            if (
              state.visualState === "resting" &&
              state.scrollY === 0 &&
              state.anchorHeight === anchorHeight &&
              elements.header
                .getAnimations()
                .every((animation): boolean => ["finished", "idle"].includes(animation.playState))
            ) {
              pageWindow.clearTimeout(timeout);
              resolve();
              return;
            }
            pageWindow.requestAnimationFrame(inspect);
          };
          inspect();
        });
        const resting = readStableState(elements);
        stateObserver.disconnect();

        return {
          floating,
          frostZIndex: Number(getComputedStyle(elements.frost).zIndex),
          headerZIndex: Number(getComputedStyle(elements.header).zIndex),
          resting,
          stateChangeCount,
          viewport: { height: pageWindow.innerHeight, width: pageWindow.innerWidth },
        };
      });
    } finally {
      await applicationPage.close();
    }
  },
);
