import { defineBrowserCommand } from "@vitest/browser-playwright";

/** The final branch, lane closures and rendered path extent in page coordinates. */
export interface TopologyEndObservation {
  readonly width: number;
  readonly buttonLeft: number;
  readonly buttonCenterY: number;
  readonly branchEndX: number;
  readonly branchEndY: number;
  readonly branchStartY: number;
  readonly branchViewportMaxFraction: number;
  readonly minimumCopyClearance: number;
  readonly lastGlassBottomY: number;
  readonly laneMergeYs: readonly number[];
  readonly lowestRailY: number;
  readonly laneCount: number;
  readonly terminalNodeCount: number;
  readonly terminalRouteCount: number;
}

export interface TopologyEndPulseObservation {
  readonly eventCount: number;
  readonly pulsed: boolean;
  readonly href: string;
  readonly animationName: string;
  readonly reducedMotionAnimationName: string;
}

export const verifyTopologyEndPulse = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<TopologyEndPulseObservation> => {
    const applicationPage = await context.newPage();
    const reducedMotionPage = await context.newPage();
    const installEventCounter = (): void => {
      (window as Window & { topologyEndEventCount?: number }).topologyEndEventCount = 0;
      document.addEventListener("topology-end-reached", () => {
        const pageWindow = window as Window & { topologyEndEventCount?: number };
        pageWindow.topologyEndEventCount = (pageWindow.topologyEndEventCount ?? 0) + 1;
      });
    };
    try {
      await applicationPage.addInitScript(installEventCounter);
      await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await applicationPage.evaluate(() => window.dispatchEvent(new WheelEvent("wheel")));
      await applicationPage.waitForSelector('[data-hero-intro-state="settled"]');
      await applicationPage.evaluate(() =>
        window.scrollTo(0, document.documentElement.scrollHeight),
      );
      await applicationPage.waitForSelector("[data-final-star-button][data-pulsed]", {
        state: "attached",
      });
      const pulseState = await applicationPage.evaluate(() => ({
        buttonPresent: document.querySelector("[data-final-star-button]") !== null,
        buttonPulsed: document.querySelector("[data-final-star-button][data-pulsed]") !== null,
        eventCount:
          (window as Window & { topologyEndEventCount?: number }).topologyEndEventCount ?? 0,
      }));
      if (!pulseState.buttonPulsed) {
        throw new Error(`Rail end revealed without CTA pulse: ${JSON.stringify(pulseState)}`);
      }
      const normal = await applicationPage.evaluate(() => {
        const button = document.querySelector<HTMLAnchorElement>("[data-final-star-button]");
        if (button === null) throw new Error("Final star button is missing");
        return {
          eventCount:
            (window as Window & { topologyEndEventCount?: number }).topologyEndEventCount ?? 0,
          pulsed: button.hasAttribute("data-pulsed"),
          href: button.href,
          animationName: getComputedStyle(button, "::after").animationName,
        };
      });
      await applicationPage.evaluate(() => window.scrollTo(0, 0));
      await applicationPage.evaluate(() =>
        window.scrollTo(0, document.documentElement.scrollHeight),
      );
      const eventCount = await applicationPage.evaluate(
        () => (window as Window & { topologyEndEventCount?: number }).topologyEndEventCount ?? 0,
      );

      await reducedMotionPage.emulateMedia({ reducedMotion: "reduce" });
      await reducedMotionPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await reducedMotionPage.evaluate(() =>
        window.scrollTo(0, document.documentElement.scrollHeight),
      );
      await reducedMotionPage.waitForSelector("[data-final-star-button][data-pulsed]", {
        state: "attached",
      });
      const reducedMotionAnimationName = await reducedMotionPage
        .locator("[data-final-star-button]")
        .evaluate((button) => getComputedStyle(button, "::after").animationName);
      return { ...normal, eventCount, reducedMotionAnimationName };
    } finally {
      await Promise.all([applicationPage.close(), reducedMotionPage.close()]);
    }
  },
);

function observeEnd(width: number): TopologyEndObservation {
  const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
  const lastGlass = document.querySelector('[data-rail-surface-target="come-back"]');
  const button = document.querySelector<HTMLElement>("[data-final-star-button]");
  const finalRoute = artwork?.querySelector<SVGGElement>("[data-topology-terminal-route]");
  const finalPath = finalRoute?.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  if (
    artwork === null ||
    lastGlass === null ||
    button === null ||
    finalPath === null ||
    finalPath === undefined
  )
    throw new Error("The home page is missing its final glass, button or terminal branch");
  const origin = artwork.getBoundingClientRect();
  const artworkTop = origin.top + window.scrollY;
  const points: number[] = [];
  for (const path of artwork.querySelectorAll<SVGPathElement>("path[d]")) {
    const totalLength = path.getTotalLength();
    for (let step = 0; step <= 200; step += 1) {
      points.push(artworkTop + path.getPointAtLength((totalLength * step) / 200).y);
    }
  }
  for (const circle of artwork.querySelectorAll<SVGCircleElement>("circle")) {
    points.push(artworkTop + circle.cy.baseVal.value);
  }
  const glassBox = lastGlass.getBoundingClientRect();
  const buttonBox = button.getBoundingClientRect();
  const matrix = finalPath.getScreenCTM();
  if (matrix === null) throw new Error("Terminal route has no screen transform");
  const routeLength = finalPath.getTotalLength();
  const start = finalPath.getPointAtLength(0).matrixTransform(matrix);
  const end = finalPath.getPointAtLength(routeLength).matrixTransform(matrix);
  const mergeYs = [...artwork.querySelectorAll<SVGGElement>('[data-node-kind="merge"]')].map(
    (node) => Number(node.querySelector("circle")?.getAttribute("cy")) + artworkTop,
  );
  const ctaCopy = button.closest("section")?.querySelector<HTMLElement>("p.text-marketing-body");
  const copyBox = ctaCopy?.getBoundingClientRect();
  if (copyBox === undefined) throw new Error("Final CTA description missing");
  const minimumCopyClearance = Math.min(
    ...Array.from({ length: 101 }, (_, index) => {
      const point = finalPath.getPointAtLength((routeLength * index) / 100).matrixTransform(matrix);
      const dx = Math.max(copyBox.left - point.x, 0, point.x - copyBox.right);
      const dy = Math.max(copyBox.top - point.y, 0, point.y - copyBox.bottom);
      return Math.hypot(dx, dy);
    }),
  );
  return {
    width,
    buttonLeft: buttonBox.left,
    buttonCenterY: (buttonBox.top + buttonBox.bottom) / 2 + window.scrollY,
    branchEndX: end.x,
    branchEndY: end.y + window.scrollY,
    branchStartY: start.y + window.scrollY,
    branchViewportMaxFraction: Math.max(start.y, end.y) / window.innerHeight,
    minimumCopyClearance,
    lastGlassBottomY: glassBox.bottom + window.scrollY,
    laneMergeYs: mergeYs,
    lowestRailY: Math.max(...points),
    laneCount: Number(artwork.dataset["laneCount"]),
    terminalNodeCount: artwork.querySelectorAll("[data-topology-terminal]").length,
    terminalRouteCount: artwork.querySelectorAll("[data-topology-terminal-route]").length,
  };
}

export const verifyTopologyEnd = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    widths: readonly number[],
  ): Promise<TopologyEndObservation[]> => {
    const applicationPage = await context.newPage();
    const observations: TopologyEndObservation[] = [];
    try {
      for (const width of widths) {
        await applicationPage.setViewportSize({
          width,
          height: width === 390 ? 844 : width === 1280 ? 800 : 1080,
        });
        await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
        await applicationPage.waitForSelector(
          "[data-full-page-topology] [data-topology-terminal-route]",
          { state: "attached" },
        );
        await applicationPage.evaluate(() => {
          const button = document.querySelector<HTMLElement>("[data-final-star-button]");
          if (button === null) throw new Error("Final star button is missing before scroll");
          window.scrollTo({
            top:
              window.scrollY +
              button.getBoundingClientRect().top +
              button.offsetHeight / 2 -
              window.innerHeight * 0.5,
            behavior: "instant",
          });
        });
        await applicationPage.waitForSelector("[data-final-star-button][data-pulsed]", {
          state: "attached",
        });
        observations.push(await applicationPage.evaluate(observeEnd, width));
      }
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);
