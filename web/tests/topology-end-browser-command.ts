import { defineBrowserCommand } from "@vitest/browser-playwright";

/** The served rail's final node and rendered path extent in page coordinates. */
export interface TopologyEndObservation {
  readonly width: number;
  readonly endNodeY: number;
  readonly lastGlassCenterY: number;
  readonly lowestRailY: number;
  readonly endKind: string;
  readonly laneCount: number;
  readonly mergeRing: boolean;
  readonly mergeCore: boolean;
  readonly terminalHalo: boolean;
  readonly haloAnimationCount: string;
  readonly ctaEndMarkers: number;
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
      await applicationPage.waitForSelector(
        "[data-topology-terminal][data-topology-node-revealed]",
        { state: "attached" },
      );
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
      await reducedMotionPage.waitForSelector(
        "[data-topology-terminal][data-topology-node-revealed]",
        { state: "attached" },
      );
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
  const endNode = artwork?.querySelector<SVGGElement>("[data-topology-terminal]");
  const endCircle = endNode?.querySelector<SVGCircleElement>("circle");
  if (
    artwork === null ||
    lastGlass === null ||
    endNode === null ||
    endNode === undefined ||
    endCircle === null ||
    endCircle === undefined
  ) {
    throw new Error("The home page is missing its final glass or terminal rail node");
  }
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
  const halo = endNode.querySelector<SVGCircleElement>(".node-terminal-halo");
  return {
    width,
    endNodeY: artworkTop + Number(endCircle.getAttribute("cy")),
    lastGlassCenterY: (glassBox.top + glassBox.bottom) / 2 + window.scrollY,
    lowestRailY: Math.max(...points),
    endKind: endNode.dataset["nodeKind"] ?? "",
    laneCount: Number(artwork.dataset["laneCount"]),
    mergeRing: endNode.querySelector(".node-merge-ring") !== null,
    mergeCore: endNode.querySelector(".node-merge-core") !== null,
    terminalHalo: halo !== null,
    haloAnimationCount: halo === null ? "" : getComputedStyle(halo).animationIterationCount,
    ctaEndMarkers: document.querySelectorAll("[data-rail-end-section], [data-rail-end-mark]")
      .length,
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
          "[data-full-page-topology] [data-topology-terminal]",
          { state: "attached" },
        );
        await applicationPage.evaluate(() => {
          const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
          const circle = artwork?.querySelector<SVGCircleElement>(
            "[data-topology-terminal] circle",
          );
          if (artwork === null || circle === null || circle === undefined)
            throw new Error("Terminal node is missing before scroll");
          window.scrollTo({
            top:
              window.scrollY +
              artwork.getBoundingClientRect().top +
              circle.cy.baseVal.value -
              window.innerHeight * 0.55,
            behavior: "instant",
          });
        });
        await applicationPage.waitForSelector(
          "[data-topology-terminal][data-topology-node-revealed]",
          { state: "attached" },
        );
        await applicationPage.evaluate(async () => {
          const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
          const glass = document.querySelector<HTMLElement>(
            '[data-rail-surface-target="come-back"]',
          );
          const liftGroup = glass?.closest<HTMLElement>("[data-scroll-material-lift-target]");
          if (artwork === null || glass === null || liftGroup === null || liftGroup === undefined)
            throw new Error("Rail end lift target is missing");
          const hasLift = (): boolean =>
            Number.parseFloat(
              getComputedStyle(liftGroup).getPropertyValue("--scroll-material-lift"),
            ) < 0;
          const aligned = (): boolean => {
            const circle = artwork.querySelector<SVGCircleElement>(
              "[data-topology-terminal] circle",
            );
            if (circle === null) return false;
            const box = glass.getBoundingClientRect();
            return (
              Math.abs(
                artwork.getBoundingClientRect().top +
                  circle.cy.baseVal.value -
                  (box.top + box.bottom) / 2,
              ) <= 1
            );
          };
          const until = async (condition: () => boolean): Promise<void> => {
            if (condition()) return;
            await new Promise<void>((resolve) => {
              const observer = new MutationObserver(() => {
                if (!condition()) return;
                observer.disconnect();
                resolve();
              });
              observer.observe(liftGroup, { attributes: true, attributeFilter: ["style"] });
              observer.observe(artwork, {
                attributes: true,
                attributeFilter: ["cy"],
                subtree: true,
              });
            });
          };
          await until(hasLift);
          await until(aligned);
        });
        observations.push(await applicationPage.evaluate(observeEnd, width));
      }
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);
