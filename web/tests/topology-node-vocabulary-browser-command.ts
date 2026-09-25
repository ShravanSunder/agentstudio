import { defineBrowserCommand } from "@vitest/browser-playwright";

/** One rendered glyph, read from the served home page with its real styles. */
export interface TopologyGlyphObservation {
  readonly kind: string;
  readonly chapterState: string | undefined;
  readonly revealed: boolean;
  /** The lane color the node sits on (the group's `color`). */
  readonly laneColor: string;
  /** The primary glyph: the dot, the chapter ring, or the merge ring. */
  readonly glyph: {
    readonly radius: number;
    readonly fill: string;
    readonly stroke: string;
    readonly strokeWidth: string;
    readonly display: string;
    /** The glyph's own `color`: the incoming lane for a merge ring. */
    readonly color: string;
  };
  /** Merge nodes only: the inner dot. */
  readonly core:
    | { readonly radius: number; readonly fill: string; readonly opacity: string }
    | undefined;
  readonly terminalDisplay: string | undefined;
}

/** One port's line, read with its real styles. */
export interface TopologyPortObservation {
  readonly source: string;
  readonly strokeWidth: string;
  readonly laneStrokeWidth: string;
  /** The computed `stroke`: a `url(#…)` gradient reference when the port leaves a worktree lane. */
  readonly stroke: string;
  readonly firstStopColor: string | undefined;
  /** The computed stroke of the lane the port leaves. */
  readonly sourceLaneStroke: string | undefined;
  readonly nodeRadius: number;
}

export interface TopologyNodeVocabularyResult {
  readonly canvasColor: string;
  readonly primaryColor: string;
  readonly beforeReveal: readonly TopologyGlyphObservation[];
  readonly afterReveal: readonly TopologyGlyphObservation[];
  readonly ports: readonly TopologyPortObservation[];
}

function readPorts(): TopologyPortObservation[] {
  const artwork = document.querySelector("[data-full-page-topology]");
  if (artwork === null) {
    throw new Error("The home page has no topology artwork");
  }
  const laneCore = (accent: string): SVGPathElement | null =>
    artwork.querySelector<SVGPathElement>(
      `[data-route-kind="worktree"].accent-${accent} > [data-topology-path-role="core"]`,
    );
  const anyLane =
    artwork.querySelector<SVGPathElement>(
      '[data-route-kind="worktree"] > [data-topology-path-role="core"]',
    ) ?? artwork.querySelector<SVGPathElement>("[data-mainline]");
  return [...artwork.querySelectorAll<SVGGElement>('[data-route-kind="attach"]')].map((group) => {
    const core = group.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
    const node = group.querySelector<SVGCircleElement>("[data-topology-port-node]");
    if (core === null || node === null || anyLane === null) {
      throw new Error("A port is missing its line or node");
    }
    const source = group.dataset["routeSource"] ?? "";
    const firstStop = group.querySelector("[data-topology-port-gradient] stop");
    const sourceLane = laneCore(source);
    return {
      source,
      strokeWidth: getComputedStyle(core).strokeWidth,
      laneStrokeWidth: getComputedStyle(anyLane).strokeWidth,
      stroke: getComputedStyle(core).stroke,
      firstStopColor: firstStop === null ? undefined : getComputedStyle(firstStop).stopColor,
      sourceLaneStroke: sourceLane === null ? undefined : getComputedStyle(sourceLane).stroke,
      nodeRadius: node.r.baseVal.value,
    };
  });
}

function readGlyphs(): TopologyGlyphObservation[] {
  const artwork = document.querySelector("[data-full-page-topology]");
  if (artwork === null) {
    throw new Error("The home page has no topology artwork");
  }
  return [...artwork.querySelectorAll<SVGGElement>("[data-node]")].map((node) => {
    const glyph = node.querySelector<SVGCircleElement>(
      ".node-commit, .node-chapter, .node-merge-ring",
    );
    if (glyph === null) {
      throw new Error("A topology node has no glyph");
    }
    const glyphStyle = getComputedStyle(glyph);
    const core = node.querySelector<SVGCircleElement>(".node-merge-core");
    const terminal = node.querySelector<SVGCircleElement>(".node-terminal");
    return {
      kind: node.dataset["nodeKind"] ?? "",
      chapterState: node.dataset["chapterState"],
      revealed: node.hasAttribute("data-topology-node-revealed"),
      laneColor: getComputedStyle(node).color,
      glyph: {
        radius: glyph.r.baseVal.value,
        fill: glyphStyle.fill,
        stroke: glyphStyle.stroke,
        strokeWidth: glyphStyle.strokeWidth,
        display: glyphStyle.display,
        color: glyphStyle.color,
      },
      core:
        core === null
          ? undefined
          : {
              radius: core.r.baseVal.value,
              fill: getComputedStyle(core).fill,
              opacity: getComputedStyle(core).opacity,
            },
      terminalDisplay: terminal === null ? undefined : getComputedStyle(terminal).display,
    };
  });
}

/**
 * Loads the served home page at 1920×1080 and reads every topology glyph's
 * computed style twice: at first paint (nodes below the fog are unrevealed)
 * and after scrolling to the end (everything revealed, transitions settled).
 */
export const verifyTopologyNodeVocabulary = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<TopologyNodeVocabularyResult> => {
    const applicationPage = await context.newPage();
    try {
      await applicationPage.setViewportSize({ width: 1920, height: 1080 });
      await applicationPage.goto(pageUrl, { waitUntil: "networkidle" });
      await applicationPage.waitForSelector(
        "[data-full-page-topology][data-topology-reveal-edge-y]",
        {
          state: "attached",
        },
      );
      const beforeReveal = await applicationPage.evaluate(readGlyphs);
      await applicationPage.evaluate(() => {
        window.scrollTo(0, document.documentElement.scrollHeight);
      });
      await applicationPage.waitForFunction(() =>
        [...document.querySelectorAll("[data-full-page-topology] [data-node]")].every((node) =>
          node.hasAttribute("data-topology-node-revealed"),
        ),
      );
      await applicationPage.evaluate(async () => {
        await Promise.all(
          document
            .getAnimations()
            .filter((animation) => animation.effect?.getComputedTiming().iterations !== Infinity)
            .map((animation) => animation.finished),
        );
      });
      const afterReveal = await applicationPage.evaluate(readGlyphs);
      const { canvasColor, primaryColor } = await applicationPage.evaluate(() => {
        const port = document.querySelector("[data-topology-port-node]");
        return {
          canvasColor: getComputedStyle(document.body).backgroundColor,
          primaryColor: port === null ? "" : getComputedStyle(port).fill,
        };
      });
      const ports = await applicationPage.evaluate(readPorts);
      return { canvasColor, primaryColor, beforeReveal, afterReveal, ports };
    } finally {
      await applicationPage.close();
    }
  },
);
