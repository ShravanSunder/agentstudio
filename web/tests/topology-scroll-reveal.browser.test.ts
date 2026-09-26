import { afterEach, describe, expect, it, vi } from "vitest";
import { page } from "vitest/browser";

import { railCurrentAttribute } from "../src/chapters/chapter-dom-contract";
import { layoutFullPageTopology } from "../src/topology-lab/full-page-topology-layout";
import {
  initializeTopologyScrollReveal,
  topologyChapterStateAttribute,
  topologyNodeRevealedAttribute,
  topologyReadingLineRatio,
} from "../src/topology-lab/topology-scroll-reveal";
import {
  mountTopologyFixture,
  type TopologyFixture,
  type TopologyFixtureLayout,
} from "./topology-browser-fixture";

interface RevealFixture extends TopologyFixture {
  readonly dispose: () => void;
}

const activeFixtures: RevealFixture[] = [];

const wideRevealLayout: TopologyFixtureLayout = {
  contentLeft: 383,
  anchorTops: [110, 1300, 2060, 2820, 3580],
  height: 6000,
  phone: false,
};

const phoneRevealLayout: TopologyFixtureLayout = {
  contentLeft: 40,
  anchorTops: [96, 1100, 1700, 2300],
  height: 3600,
  phone: true,
};

function mountRevealFixture(layout: TopologyFixtureLayout = wideRevealLayout): RevealFixture {
  const fixture = mountTopologyFixture(layout);
  const revealFixture = {
    ...fixture,
    dispose: initializeTopologyScrollReveal(fixture.artwork, layoutFullPageTopology),
  };
  activeFixtures.push(revealFixture);
  return revealFixture;
}

function revealEdgeY(artwork: SVGSVGElement): number {
  return Number(artwork.dataset["topologyRevealEdgeY"]);
}

function readingLineY(artwork: SVGSVGElement): number {
  return window.innerHeight * topologyReadingLineRatio - artwork.getBoundingClientRect().top;
}

/** The artwork y of a route's start or end. */
function routePointY(group: Element, at: "start" | "end"): number {
  const core = group.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  if (core === null) {
    return Number.NaN;
  }
  return core.getPointAtLength(at === "start" ? 0 : core.getTotalLength()).y;
}

async function scrollAndSettle(artwork: SVGSVGElement, top: number): Promise<number> {
  window.scrollTo(0, top);
  const maximumScroll = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
  const expectedProgress = Math.min(Math.max(window.scrollY / maximumScroll, 0), 1);
  await vi.waitFor(() => {
    expect(Number(artwork.dataset["topologyScrollProgress"])).toBeCloseTo(expectedProgress, 3);
  });
  return revealEdgeY(artwork);
}

function nodeY(node: Element): number {
  return Number(node.querySelector("circle")?.getAttribute("cy"));
}

afterEach(() => {
  for (const fixture of activeFixtures.splice(0)) {
    fixture.dispose();
    fixture.host.remove();
  }
  window.scrollTo(0, 0);
  vi.restoreAllMocks();
});

describe("full-page topology scroll reveal", () => {
  for (const [width, height, layout] of [
    [1600, 1000, wideRevealLayout],
    [390, 844, phoneRevealLayout],
  ] as const) {
    it(`greys at 75 percent and fades the whole rail from 90 to 95 percent at ${width}px`, async () => {
      await page.viewport(width, height);
      const fixture = mountRevealFixture(layout);
      await vi.waitFor(() => expect(Number.isFinite(revealEdgeY(fixture.artwork))).toBe(true));
      const source = fixture.artwork.querySelector("#topology-rail-source");
      const grey = fixture.artwork.querySelector("[data-topology-grey-copy]");
      const colour = fixture.artwork.querySelector("[data-topology-colour-copy]");
      const gradient = fixture.artwork.querySelector("#topology-rail-vibrancy-gradient");
      const opacityGradient = fixture.artwork.querySelector("#topology-rail-opacity-gradient");
      const opacityLayer = fixture.artwork.querySelector("[data-topology-opacity-layer]");
      expect(source).not.toBeNull();
      expect(grey?.getAttribute("href")).toBe("#topology-rail-source");
      expect(colour?.getAttribute("href")).toBe("#topology-rail-source");
      expect(gradient).not.toBeNull();
      expect(opacityGradient).not.toBeNull();
      expect(opacityLayer?.getAttribute("mask")).toBe("url(#topology-rail-opacity-mask)");
      if (gradient === null || opacityGradient === null)
        throw new Error("Rail gradients are missing");
      const artworkTop = fixture.artwork.getBoundingClientRect().top;
      expect(Number(gradient.getAttribute("y1")) + artworkTop).toBeCloseTo(height * 0.73, 0);
      expect(Number(gradient.getAttribute("y2")) + artworkTop).toBeCloseTo(height * 0.75, 0);
      expect(Number(opacityGradient.getAttribute("y1")) + artworkTop).toBeCloseTo(height * 0.9, 0);
      expect(Number(opacityGradient.getAttribute("y2")) + artworkTop).toBeCloseTo(height * 0.95, 0);
    });
  }
  it("draws the rail through the viewport bottom after scrolling to a chapter", async () => {
    await page.viewport(1600, 1000);
    const fixture = mountRevealFixture();
    const chapter = fixture.host.querySelector<HTMLElement>('[data-rail-anchor="chapter-1"]');
    if (chapter === null) throw new Error("First chapter is missing");
    window.scrollTo(0, window.scrollY + chapter.getBoundingClientRect().top - 200);
    await vi.waitFor(() => {
      const solid = fixture.artwork.querySelector("[data-topology-reveal-solid]");
      const viewportBottom = window.innerHeight - fixture.artwork.getBoundingClientRect().top;
      expect(Number(solid?.getAttribute("height"))).toBeGreaterThanOrEqual(viewportBottom - 1);
    });
  });
  for (const [label, width, height, layout] of [
    ["wide", 1920, 1080, wideRevealLayout],
    ["phone", 390, 844, phoneRevealLayout],
  ] as const) {
    it(`reveals the whole first viewport on load (${label})`, async () => {
      // Arrange
      await page.viewport(width, height);

      // Act
      const fixture = mountRevealFixture(layout);

      // Assert
      await vi.waitFor(() => {
        expect(Number.isFinite(revealEdgeY(fixture.artwork))).toBe(true);
      });
      const edge = revealEdgeY(fixture.artwork);
      const viewportBottomY = window.innerHeight - fixture.artwork.getBoundingClientRect().top;
      expect(edge).toBeGreaterThanOrEqual(viewportBottomY - 1);
      const heroAttach = fixture.artwork.querySelector('[data-route-anchor="hero"]');
      expect(heroAttach).not.toBeNull();
      expect(routePointY(heroAttach ?? fixture.artwork, "end")).toBeLessThanOrEqual(edge);
      for (const lane of fixture.artwork.querySelectorAll('[data-route-kind="worktree"]')) {
        expect(routePointY(lane, "start")).toBeLessThanOrEqual(edge);
      }
      const solid = fixture.artwork.querySelector("[data-topology-reveal-solid]");
      expect(Number(solid?.getAttribute("height"))).toBeGreaterThanOrEqual(viewportBottomY - 1);
    });
  }

  it("only ever moves the fog edge down as the page scrolls either way", async () => {
    // Arrange
    await page.viewport(1920, 1080);
    const fixture = mountRevealFixture();
    await vi.waitFor(() => {
      expect(Number.isFinite(revealEdgeY(fixture.artwork))).toBe(true);
    });
    const edges = [revealEdgeY(fixture.artwork)];

    // Act: each scroll must settle before the next.
    edges.push(await scrollAndSettle(fixture.artwork, 1200));
    edges.push(await scrollAndSettle(fixture.artwork, 2600));
    edges.push(await scrollAndSettle(fixture.artwork, 900));
    edges.push(await scrollAndSettle(fixture.artwork, 0));

    // Assert
    for (const [index, edge] of edges.slice(1).entries()) {
      expect(edge).toBeGreaterThanOrEqual(edges[index] ?? 0);
    }
    expect(edges[2]).toBeGreaterThan(edges[0] ?? 0);
    expect(edges.at(-1)).toBe(Math.max(...edges));
  });

  it("fills dots with their lane color as the reveal passes them and keeps the rest hollow in the fog", async () => {
    // Arrange
    await page.viewport(1920, 1080);
    const fixture = mountRevealFixture();
    await vi.waitFor(() => {
      expect(Number.isFinite(revealEdgeY(fixture.artwork))).toBe(true);
    });

    // Act
    window.scrollTo(0, 1800);

    // Assert
    await vi.waitFor(() => {
      expect(revealEdgeY(fixture.artwork)).toBeGreaterThanOrEqual(
        readingLineY(fixture.artwork) - 1,
      );
    });
    const edge = revealEdgeY(fixture.artwork);
    const nodes = [...fixture.artwork.querySelectorAll<SVGGElement>("[data-node]")];
    const above = nodes.filter((node) => nodeY(node) < edge - 1);
    const below = nodes.filter((node) => nodeY(node) > edge + 1);
    expect(above.length).toBeGreaterThan(0);
    expect(below.length).toBeGreaterThan(0);
    expect(above.every((node) => node.hasAttribute(topologyNodeRevealedAttribute))).toBe(true);
    expect(below.some((node) => node.hasAttribute(topologyNodeRevealedAttribute))).toBe(false);
    expect(
      above.every((node) => /accent-(main|peach|cyan)/u.test(node.getAttribute("class") ?? "")),
    ).toBe(true);
    const solid = fixture.artwork.querySelector("[data-topology-reveal-solid]");
    const fade = fixture.artwork.querySelector("[data-topology-reveal-fade]");
    expect(Number(solid?.getAttribute("height"))).toBeCloseTo(edge, 0);
    expect(Number(fade?.getAttribute("y"))).toBeCloseTo(edge, 0);
    expect(Number(fade?.getAttribute("height"))).toBeGreaterThan(0);
  });

  it("marks the chapter at the reading line current and lights its glass", async () => {
    // Arrange
    await page.viewport(1920, 1080);
    const fixture = mountRevealFixture();
    const secondChapter = fixture.host.querySelector<HTMLElement>('[data-rail-anchor="chapter-2"]');
    if (secondChapter === null) {
      throw new Error("Reveal fixture is missing chapter 2");
    }

    // Act: bring chapter 2's eyebrow just above the reading line.
    window.scrollTo(
      0,
      window.scrollY +
        secondChapter.getBoundingClientRect().top -
        window.innerHeight * topologyReadingLineRatio +
        20,
    );

    // Assert
    await vi.waitFor(() => {
      expect(
        fixture.artwork
          .querySelector('[data-topology-chapter-node="chapter-2"]')
          ?.getAttribute(topologyChapterStateAttribute),
      ).toBe("current");
    });
    expect(
      fixture.artwork
        .querySelector('[data-topology-chapter-node="chapter-1"]')
        ?.getAttribute(topologyChapterStateAttribute),
    ).toBe("passed");
    expect(
      fixture.artwork
        .querySelector('[data-route-anchor="chapter-2"]')
        ?.hasAttribute("data-topology-current-branch"),
    ).toBe(true);
    expect(
      fixture.artwork
        .querySelector('[data-route-anchor="chapter-1"]')
        ?.hasAttribute("data-topology-current-branch"),
    ).toBe(false);
    expect(
      [...document.querySelectorAll(`[${railCurrentAttribute}]`)].map((element) =>
        element.getAttribute("data-rail-surface-target"),
      ),
    ).toEqual(["chapter-2"]);
  });

  it("renders attach branches without port dots or draw-in state", async () => {
    await page.viewport(1920, 1080);
    const fixture = mountRevealFixture();
    await vi.waitFor(() => {
      expect(fixture.artwork.querySelectorAll('[data-route-kind="attach"]').length).toBeGreaterThan(
        0,
      );
    });
    const branches = [...fixture.artwork.querySelectorAll('[data-route-kind="attach"]')];
    expect(
      branches.every((branch) => branch.querySelector("[data-topology-port-node]") === null),
    ).toBe(true);
    expect(branches.every((branch) => !branch.hasAttribute("data-port-drawn"))).toBe(true);
  });

  it("shows the complete topology without pulse state for reduced motion", async () => {
    // Arrange
    vi.spyOn(window, "matchMedia").mockImplementation(
      (query): MediaQueryList =>
        ({
          addEventListener: vi.fn(),
          addListener: vi.fn(),
          dispatchEvent: vi.fn(() => true),
          matches: query === "(prefers-reduced-motion: reduce)",
          media: query,
          onchange: null,
          removeEventListener: vi.fn(),
          removeListener: vi.fn(),
        }) satisfies MediaQueryList,
    );
    await page.viewport(1920, 1080);

    // Act
    const fixture = mountRevealFixture();

    // Assert
    await vi.waitFor(() => {
      expect(Number.isFinite(revealEdgeY(fixture.artwork))).toBe(true);
      expect(Number(fixture.artwork.dataset["topologyRevealEdgeY"])).toBe(
        Number(fixture.artwork.dataset["topologyEndY"]),
      );
    });
    const nodes = [...fixture.artwork.querySelectorAll("[data-node]")];
    expect(nodes.every((node) => node.hasAttribute(topologyNodeRevealedAttribute))).toBe(true);
    expect(fixture.artwork.querySelectorAll("[data-topology-current-node]")).toHaveLength(0);
    const greyCopy = fixture.artwork.querySelector("[data-topology-grey-copy]");
    if (greyCopy === null) throw new Error("Grey rail copy is missing");
    expect(getComputedStyle(greyCopy).display).toBe("none");
    expect(
      fixture.artwork.querySelector("[data-topology-colour-layer]")?.hasAttribute("mask"),
    ).toBe(false);
    expect(
      Number(fixture.artwork.querySelector("[data-topology-reveal-fade]")?.getAttribute("height")),
    ).toBe(0);
    expect(
      fixture.artwork.querySelectorAll("[data-topology-port-node], [data-port-drawn]"),
    ).toHaveLength(0);
  });

  it("coalesces scroll changes into the existing single animation frame", async () => {
    await page.viewport(1600, 1000);
    const scheduled: FrameRequestCallback[] = [];
    vi.spyOn(window, "requestAnimationFrame").mockImplementation((callback) => {
      scheduled.push(callback);
      return scheduled.length;
    });
    const fixture = mountRevealFixture();
    window.dispatchEvent(new Event("scroll"));
    window.dispatchEvent(new Event("scroll"));
    expect(scheduled).toHaveLength(1);
    fixture.dispose();
  });
});
