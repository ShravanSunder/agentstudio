import { afterEach, describe, expect, it, vi } from "vitest";

import { initializeTopologyScrollReveal } from "../src/topology-lab/topology-scroll-reveal";

interface TopologyRevealFixture {
  readonly artwork: SVGSVGElement;
  readonly corePath: SVGPathElement;
  readonly dispose: () => void;
  readonly finalNode: SVGGElement;
  readonly host: HTMLDivElement;
  readonly middleNode: SVGGElement;
  readonly startNode: SVGGElement;
}

const activeFixtures: TopologyRevealFixture[] = [];

function createTopologyRevealFixture(): TopologyRevealFixture {
  const host = document.createElement("div");
  host.style.height = "20000px";
  host.innerHTML = `
    <svg data-full-page-topology style="display:block;width:180px;height:1200px">
      <rect data-topology-reveal-solid height="0"></rect>
      <rect data-topology-reveal-fade height="0"></rect>
      <path data-topology-path-role="core" data-topology-path-start="0" data-topology-path-end="1" d="M 50 5 L 50 1195"></path>
      <g data-node-owner="main" data-topology-node-progress="0" transform="translate(50 5)"></g>
      <g data-node-owner="main" data-topology-node-progress="0.5" transform="translate(50 600)"></g>
      <g data-node-owner="main" data-topology-node-progress="1" transform="translate(50 1195)"></g>
    </svg>
  `;
  document.body.append(host);

  const artwork = host.querySelector<SVGSVGElement>("[data-full-page-topology]");
  const corePath = host.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  const finalNode = host.querySelector<SVGGElement>('[data-topology-node-progress="1"]');
  const middleNode = host.querySelector<SVGGElement>('[data-topology-node-progress="0.5"]');
  const startNode = host.querySelector<SVGGElement>('[data-topology-node-progress="0"]');
  if (
    artwork === null ||
    corePath === null ||
    finalNode === null ||
    middleNode === null ||
    startNode === null
  ) {
    throw new Error("Topology reveal fixture is incomplete");
  }

  const fixture = {
    artwork,
    corePath,
    dispose: initializeTopologyScrollReveal(artwork, (svg): boolean => {
      svg.dataset["topologyStartY"] = "5";
      svg.dataset["topologyEndY"] = "1195";
      return true;
    }),
    finalNode,
    host,
    middleNode,
    startNode,
  } satisfies TopologyRevealFixture;
  activeFixtures.push(fixture);
  return fixture;
}

async function waitForRenderedProgress(artwork: SVGSVGElement, expected: number): Promise<void> {
  await vi.waitFor(() => {
    expect(Number(artwork.dataset["topologyScrollProgress"])).toBeCloseTo(expected, 2);
  });
}

async function scrollToProgress(artwork: SVGSVGElement, progress: number): Promise<void> {
  const maximumScroll = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, maximumScroll * progress);
  await waitForRenderedProgress(artwork, progress);
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
  it("shows only the start node before scroll begins", async () => {
    const fixture = createTopologyRevealFixture();

    await waitForRenderedProgress(fixture.artwork, 0);

    expect(fixture.artwork.hasAttribute("data-topology-at-start")).toBe(true);
    expect(fixture.corePath.style.visibility).toBe("hidden");
    expect(fixture.startNode.style.opacity).toBe("1");
    expect(fixture.middleNode.style.opacity).toBe("0");
    expect(fixture.finalNode.style.opacity).toBe("0");
  });

  it("tracks document scroll with one current node per active tree", async () => {
    const fixture = createTopologyRevealFixture();

    await scrollToProgress(fixture.artwork, 0.5);

    const revealFade = fixture.artwork.querySelector<SVGRectElement>("[data-topology-reveal-fade]");
    expect(fixture.corePath.style.visibility).toBe("visible");
    expect(Number(revealFade?.getAttribute("height"))).toBeGreaterThan(0);
    expect(fixture.middleNode.hasAttribute("data-topology-current-node")).toBe(true);
    expect(fixture.startNode.hasAttribute("data-topology-current-node")).toBe(false);

    await scrollToProgress(fixture.artwork, 1);

    expect(fixture.artwork.hasAttribute("data-topology-at-end")).toBe(true);
    expect(Number(revealFade?.getAttribute("height"))).toBe(0);
    expect(fixture.finalNode.hasAttribute("data-topology-current-node")).toBe(true);

    await scrollToProgress(fixture.artwork, 0);

    expect(fixture.artwork.hasAttribute("data-topology-at-start")).toBe(true);
    expect(fixture.corePath.style.visibility).toBe("hidden");
    expect(fixture.middleNode.hasAttribute("data-topology-current-node")).toBe(false);
  });

  it("renders the complete topology without pulse state for reduced motion", async () => {
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
    const fixture = createTopologyRevealFixture();

    await waitForRenderedProgress(fixture.artwork, 0);

    const nodes = [fixture.startNode, fixture.middleNode, fixture.finalNode];
    expect(nodes.every((node) => node.style.opacity === "1")).toBe(true);
    expect(nodes.some((node) => node.hasAttribute("data-topology-current-node"))).toBe(false);
    expect(fixture.artwork.hasAttribute("data-topology-at-start")).toBe(false);
    expect(fixture.artwork.hasAttribute("data-topology-at-end")).toBe(false);
  });
});
