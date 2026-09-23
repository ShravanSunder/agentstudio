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
import { mountTopologyFixture, type TopologyFixture } from "./topology-browser-fixture";

interface RevealFixture extends TopologyFixture {
  readonly dispose: () => void;
}

const activeFixtures: RevealFixture[] = [];

function mountRevealFixture(): RevealFixture {
  const fixture = mountTopologyFixture({
    contentLeft: 383,
    anchorTops: [110, 1300, 2060, 2820, 3580],
    height: 6000,
    phone: false,
  });
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
      [...document.querySelectorAll(`[${railCurrentAttribute}]`)].map((element) =>
        element.getAttribute("data-rail-surface-target"),
      ),
    ).toEqual(["chapter-2"]);
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
      expect(Number(fixture.artwork.dataset["topologyRevealEdgeY"])).toBe(
        Number(fixture.artwork.dataset["topologyEndY"]),
      );
    });
    const nodes = [...fixture.artwork.querySelectorAll("[data-node]")];
    expect(nodes.every((node) => node.hasAttribute(topologyNodeRevealedAttribute))).toBe(true);
    expect(fixture.artwork.querySelectorAll("[data-topology-current-node]")).toHaveLength(0);
    expect(
      Number(fixture.artwork.querySelector("[data-topology-reveal-fade]")?.getAttribute("height")),
    ).toBe(0);
  });
});
