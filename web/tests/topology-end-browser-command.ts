import { defineBrowserCommand } from "@vitest/browser-playwright";

/** The final branch, lane closures and rendered path extent in page coordinates. */
export interface TopologyEndObservation {
  readonly width: number;
  readonly pillLeft: number;
  readonly pillCenterY: number;
  readonly branchEndX: number;
  readonly branchEndY: number;
  readonly nodeRightX: number;
  readonly ringRadius: number;
  readonly coreRadius: number;
  readonly haloRadius: number;
  readonly ringStroke: string;
  readonly coreFill: string;
  readonly branchStroke: string;
  readonly branchStartY: number;
  readonly branchViewportMaxFraction: number;
  readonly minimumTitleClearance: number;
  readonly lastGlassBottomY: number;
  readonly laneMergeYs: readonly number[];
  readonly lowestRailY: number;
  readonly laneCount: number;
  readonly terminalNodeCount: number;
  readonly terminalRouteCount: number;
}

export interface FinaleBookendObservation {
  readonly eventCount: number;
  readonly href: string;
  readonly finalState: string | undefined;
  readonly logoOpacity: string;
  readonly traceOpacity: string;
  readonly starFillOpacity: string;
  readonly railStartFraction: number;
  readonly railArrivalFraction: number;
  readonly nodeStartOpacity: string;
  readonly nodeArrivalOpacity: string;
  readonly sectionHeightDelta: number;
  readonly footerTopDelta: number;
  readonly oldInstallBoxCount: number;
  readonly ctaParagraphCount: number;
  readonly splitPillCount: number;
  readonly starText: string;
  readonly copyText: string;
  readonly copiedText: string;
  readonly copiedLabel: string;
  readonly phoneOneRow: boolean;
  readonly phoneShortLabels: boolean;
  readonly phoneOverflow: number;
  readonly reducedMotionState: string | undefined;
  readonly reducedMotionTimelineCreated: boolean;
  readonly reducedMotionLogoOpacity: string;
  readonly pointerSkipState: string | undefined;
  readonly resizeSettleState: string | undefined;
}

export const verifyFinaleBookend = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<FinaleBookendObservation> => {
    const applicationPage = await context.newPage();
    const reducedMotionPage = await context.newPage();
    const skipPage = await context.newPage();
    const installEventCounter = (): void => {
      const proofWindow = window as Window & {
        topologyEndEventCount?: number;
        finaleControl?: { pause(): void; seek(seconds: number): void };
        copiedInstall?: string;
      };
      proofWindow.topologyEndEventCount = 0;
      document.addEventListener("topology-end-reached", () => {
        const pageWindow = window as Window & { topologyEndEventCount?: number };
        pageWindow.topologyEndEventCount = (pageWindow.topologyEndEventCount ?? 0) + 1;
      });
      document.addEventListener("finale-bookend-ready", (event) => {
        if (!(event instanceof CustomEvent)) return;
        proofWindow.finaleControl = event.detail as { pause(): void; seek(seconds: number): void };
        proofWindow.finaleControl.pause();
      });
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          writeText: (value: string): Promise<void> => {
            proofWindow.copiedInstall = value;
            return Promise.resolve();
          },
        },
      });
    };
    try {
      await applicationPage.setViewportSize({ width: 1600, height: 1000 });
      await applicationPage.addInitScript(installEventCounter);
      await applicationPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await applicationPage.evaluate(() => window.dispatchEvent(new WheelEvent("wheel")));
      await applicationPage.waitForSelector('[data-hero-intro-state="settled"]');
      await applicationPage.waitForSelector("[data-finale-timeline-created]");
      await applicationPage.evaluate(() =>
        window.scrollTo(0, document.documentElement.scrollHeight),
      );
      await applicationPage.waitForSelector("[data-topology-end-reached]");
      const normal = await applicationPage.evaluate(async () => {
        const proofWindow = window as Window & {
          topologyEndEventCount?: number;
          finaleControl?: { pause(): void; seek(seconds: number): void };
          copiedInstall?: string;
        };
        const root = document.querySelector<HTMLElement>("[data-finale-root]");
        const button = document.querySelector<HTMLAnchorElement>("[data-final-star-button]");
        const copy = document.querySelector<HTMLButtonElement>(
          "[data-finale-split-pill] [data-install-copy]",
        );
        const footer = document.querySelector<HTMLElement>("footer");
        const logo = root?.querySelector<HTMLElement>("[data-finale-logo]");
        const trace = root?.querySelector<SVGPathElement>("[data-finale-border-trace]");
        const fill = root?.querySelector<SVGPathElement>("[data-finale-star-fill]");
        const terminalRoute = document.querySelector<SVGGElement>("[data-topology-terminal-route]");
        const railPath = terminalRoute?.querySelector<SVGPathElement>(
          '[data-topology-path-role="core"]',
        );
        const endNode = terminalRoute?.querySelector<SVGGElement>("[data-topology-terminal-node]");
        if (
          root === null ||
          button === null ||
          copy === null ||
          footer === null ||
          logo === null ||
          logo === undefined ||
          trace === null ||
          trace === undefined ||
          fill === null ||
          fill === undefined ||
          railPath === null ||
          railPath === undefined ||
          endNode === null ||
          endNode === undefined ||
          proofWindow.finaleControl === undefined
        )
          throw new Error("Finale proof markup or control is missing");
        proofWindow.finaleControl.seek(0);
        const railStartFraction =
          Number.parseFloat(railPath.style.strokeDashoffset) / railPath.getTotalLength();
        const nodeStartOpacity = getComputedStyle(endNode).opacity;
        const initialHeight = root.getBoundingClientRect().height;
        const initialFooterTop = footer.getBoundingClientRect().top + scrollY;
        const sampleShift = (): number =>
          Math.max(
            Math.abs(root.getBoundingClientRect().height - initialHeight),
            Math.abs(footer.getBoundingClientRect().top + scrollY - initialFooterTop),
          );
        const starText = button.textContent?.trim() ?? "";
        const copyText = copy.textContent?.trim() ?? "";
        proofWindow.finaleControl.seek(0.35);
        const railArrivalFraction =
          Number.parseFloat(railPath.style.strokeDashoffset) / railPath.getTotalLength();
        const nodeArrivalOpacity = getComputedStyle(endNode).opacity;
        proofWindow.finaleControl.seek(0.8);
        const midTraceShift = sampleShift();
        proofWindow.finaleControl.seek(1.8);
        const midFoldShift = sampleShift();
        proofWindow.finaleControl.seek(2.4);
        const finalShift = sampleShift();
        copy.click();
        await Promise.resolve();
        return {
          eventCount: proofWindow.topologyEndEventCount ?? 0,
          href: button.href,
          finalState: root.dataset["finaleState"],
          logoOpacity: getComputedStyle(logo).opacity,
          traceOpacity: getComputedStyle(trace.closest("svg") ?? trace).opacity,
          starFillOpacity: getComputedStyle(fill).opacity,
          railStartFraction,
          railArrivalFraction,
          nodeStartOpacity,
          nodeArrivalOpacity,
          sectionHeightDelta: Math.max(midTraceShift, midFoldShift, finalShift),
          footerTopDelta: footer.getBoundingClientRect().top + scrollY - initialFooterTop,
          oldInstallBoxCount: root.querySelectorAll(".install-command").length,
          ctaParagraphCount: root.querySelectorAll("p").length,
          splitPillCount: root.querySelectorAll("[data-finale-split-pill]").length,
          starText,
          copyText,
          copiedText: proofWindow.copiedInstall ?? "",
          copiedLabel:
            [...copy.querySelectorAll<HTMLElement>("[data-install-copy-feedback]")].find(
              (label) => getComputedStyle(label).display !== "none",
            )?.textContent ?? "",
        };
      });

      await reducedMotionPage.emulateMedia({ reducedMotion: "reduce" });
      await reducedMotionPage.setViewportSize({ width: 390, height: 844 });
      await reducedMotionPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await reducedMotionPage.evaluate(() =>
        window.scrollTo(0, document.documentElement.scrollHeight),
      );
      await reducedMotionPage.waitForSelector("[data-topology-end-reached]");
      const reduced = await reducedMotionPage.evaluate(() => {
        const root = document.querySelector<HTMLElement>("[data-finale-root]");
        const pill = root?.querySelector<HTMLElement>("[data-finale-split-pill]");
        const star = root?.querySelector<HTMLElement>("[data-final-star-button]");
        const copy = root?.querySelector<HTMLElement>("[data-install-copy]");
        const logo = root?.querySelector<HTMLElement>("[data-finale-logo]");
        if (
          root === null ||
          pill === null ||
          pill === undefined ||
          star === null ||
          star === undefined ||
          copy === null ||
          copy === undefined ||
          logo === null ||
          logo === undefined
        )
          throw new Error("Reduced-motion finale markup is missing");
        return {
          phoneOneRow:
            Math.abs(star.getBoundingClientRect().top - copy.getBoundingClientRect().top) <= 0.5,
          phoneShortLabels: root.hasAttribute("data-short-labels"),
          phoneOverflow: pill.scrollWidth - pill.clientWidth,
          reducedMotionState: root.dataset["finaleState"],
          reducedMotionTimelineCreated: root.hasAttribute("data-finale-timeline-created"),
          reducedMotionLogoOpacity: getComputedStyle(logo).opacity,
        };
      });
      await skipPage.setViewportSize({ width: 390, height: 844 });
      await skipPage.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await skipPage.waitForSelector("[data-finale-timeline-created]");
      await skipPage.evaluate(() => {
        document
          .querySelector<HTMLElement>("[data-finale-root]")
          ?.dispatchEvent(new Event("pointerdown", { bubbles: true }));
      });
      const pointerSkipState =
        (await skipPage.locator("[data-finale-root]").getAttribute("data-finale-state")) ??
        undefined;
      await skipPage.reload({ waitUntil: "domcontentloaded" });
      await skipPage.waitForSelector("[data-finale-timeline-created]");
      await skipPage.setViewportSize({ width: 430, height: 844 });
      const resizeSettleState =
        (await skipPage.locator("[data-finale-root]").getAttribute("data-finale-state")) ??
        undefined;
      return { ...normal, ...reduced, pointerSkipState, resizeSettleState };
    } finally {
      await Promise.all([applicationPage.close(), reducedMotionPage.close(), skipPage.close()]);
    }
  },
);

function observeEnd(width: number): TopologyEndObservation {
  const artwork = document.querySelector<SVGSVGElement>("[data-full-page-topology]");
  const lastGlass = document.querySelector('[data-rail-surface-target="come-back"]');
  const button = document.querySelector<HTMLElement>("[data-final-star-button]");
  const pill = button?.closest<HTMLElement>("[data-finale-split-pill]");
  const finalRoute = artwork?.querySelector<SVGGElement>("[data-topology-terminal-route]");
  const finalPath = finalRoute?.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  const terminalNode = finalRoute?.querySelector<SVGGElement>("[data-topology-terminal-node]");
  const ring = terminalNode?.querySelector<SVGCircleElement>(".node-merge-ring");
  const core = terminalNode?.querySelector<SVGCircleElement>(".node-merge-core");
  const halo = terminalNode?.querySelector<SVGCircleElement>(".node-terminal-halo");
  if (
    artwork === null ||
    lastGlass === null ||
    button === null ||
    pill === null ||
    pill === undefined ||
    finalPath === null ||
    finalPath === undefined ||
    ring === null ||
    ring === undefined ||
    core === null ||
    core === undefined ||
    halo === null ||
    halo === undefined
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
  const buttonBox = pill.getBoundingClientRect();
  const matrix = finalPath.getScreenCTM();
  if (matrix === null) throw new Error("Terminal route has no screen transform");
  const routeLength = finalPath.getTotalLength();
  const start = finalPath.getPointAtLength(0).matrixTransform(matrix);
  const end = finalPath.getPointAtLength(routeLength).matrixTransform(matrix);
  const mergeYs = [...artwork.querySelectorAll<SVGGElement>('[data-node-kind="merge"]')]
    .filter((node) => !node.hasAttribute("data-topology-terminal-node"))
    .map((node) => Number(node.querySelector("circle")?.getAttribute("cy")) + artworkTop);
  const ctaTitle = button.closest("section")?.querySelector<HTMLElement>("#final-cta-title");
  const titleBox = ctaTitle?.getBoundingClientRect();
  if (titleBox === undefined) throw new Error("Final CTA title missing");
  const minimumTitleClearance = Math.min(
    ...Array.from({ length: 101 }, (_, index) => {
      const point = finalPath.getPointAtLength((routeLength * index) / 100).matrixTransform(matrix);
      const dx = Math.max(titleBox.left - point.x, 0, point.x - titleBox.right);
      const dy = Math.max(titleBox.top - point.y, 0, point.y - titleBox.bottom);
      return Math.hypot(dx, dy);
    }),
  );
  return {
    width,
    pillLeft: buttonBox.left,
    pillCenterY: (buttonBox.top + buttonBox.bottom) / 2 + window.scrollY,
    branchEndX: end.x,
    branchEndY: end.y + window.scrollY,
    nodeRightX: end.x + Number(ring.getAttribute("r")),
    ringRadius: Number(ring.getAttribute("r")),
    coreRadius: Number(core.getAttribute("r")),
    haloRadius: Number(halo.getAttribute("r")),
    ringStroke: getComputedStyle(ring).stroke,
    coreFill: getComputedStyle(core).fill,
    branchStroke: getComputedStyle(finalPath).stroke,
    branchStartY: start.y + window.scrollY,
    branchViewportMaxFraction: Math.max(start.y, end.y) / window.innerHeight,
    minimumTitleClearance,
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
        await applicationPage.waitForSelector(
          "[data-topology-terminal-node][data-topology-node-revealed]",
          {
            state: "attached",
          },
        );
        await applicationPage.evaluate(async () => {
          const node = document.querySelector("[data-topology-terminal-node]");
          if (node === null) throw new Error("Terminal node is missing after reveal");
          const ring = node.querySelector(".node-merge-ring");
          const core = node.querySelector(".node-merge-core");
          await Promise.all(
            [ring, core].flatMap(
              (part) => part?.getAnimations().map((animation) => animation.finished) ?? [],
            ),
          );
        });
        observations.push(await applicationPage.evaluate(observeEnd, width));
      }
      return observations;
    } finally {
      await applicationPage.close();
    }
  },
);
