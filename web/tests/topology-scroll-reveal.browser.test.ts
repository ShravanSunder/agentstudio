import { afterEach, describe, expect, it, vi } from "vitest";

import { initializeTopologyScrollReveal } from "../src/topology-lab/topology-scroll-reveal";

interface TopologyFixture {
  readonly artwork: SVGSVGElement;
  readonly corePath: SVGPathElement;
  readonly dispose: () => void;
  readonly finalNode: SVGGElement;
  readonly host: HTMLDivElement;
  readonly leadingBand: SVGPathElement;
  readonly mergeNode: SVGGElement;
  readonly middleNode: SVGGElement;
  readonly startNode: SVGGElement;
}

const activeFixtures: TopologyFixture[] = [];

function readNodeTranslation(node: SVGGElement): { readonly x: number; readonly y: number } {
  const transform = node.getAttribute("transform") ?? "";
  const match = /^translate\(([^ ]+) ([^)]+)\)$/.exec(transform);
  if (match === null) {
    throw new Error(`Unexpected node transform: ${transform}`);
  }
  return { x: Number(match[1]), y: Number(match[2]) };
}

function createTopologyFixture(): TopologyFixture {
  const host = document.createElement("div");
  host.style.height = "4000px";
  host.innerHTML = `
    <svg
      data-topology-artwork
      preserveAspectRatio="none"
      viewBox="0 0 100 100"
      style="display: block; width: 180px; height: 1200px"
    >
      <path
        data-topology-path-role="leading-band"
        data-topology-path-start="0"
        data-topology-path-end="1"
        data-topology-lead-start="0"
        data-topology-lead-end="1"
        d="M 50 0 L 50 100"
      ></path>
      <path
        data-topology-path-role="core"
        data-topology-path-start="0"
        data-topology-path-end="1"
        d="M 50 0 L 50 100"
      ></path>
      <g data-topology-node-kind="terminal" data-topology-node-lane="0" data-topology-node-progress="0" data-topology-node-row="0" transform="translate(50 5)">
        <g data-topology-node-shape>
          <circle class="node-terminal-halo" r="7"></circle>
          <circle class="node-terminal" r="7"></circle>
        </g>
      </g>
      <g data-topology-node-kind="regular" data-topology-node-lane="2" data-topology-node-progress="0.5" data-topology-node-row="13" transform="translate(50 50)">
        <g data-topology-node-shape><circle r="4"></circle></g>
      </g>
      <g data-topology-node-kind="merge" data-topology-node-lane="0" data-topology-node-progress="0.75" data-topology-node-row="20" transform="translate(50 75)">
        <g data-topology-node-shape>
          <circle r="8"></circle>
          <path d="M -3 -1 L 0 2 L 3 -1"></path>
        </g>
      </g>
      <g data-topology-node-kind="terminal" data-topology-node-lane="0" data-topology-node-progress="1" data-topology-node-row="26" transform="translate(50 95)">
        <g data-topology-node-shape>
          <circle class="node-terminal-halo" r="7"></circle>
          <circle class="node-terminal" r="7"></circle>
        </g>
      </g>
    </svg>
  `;
  document.body.append(host);

  const artwork = host.querySelector<SVGSVGElement>("[data-topology-artwork]");
  const corePath = host.querySelector<SVGPathElement>('[data-topology-path-role="core"]');
  const finalNode = host.querySelector<SVGGElement>('[data-topology-node-progress="1"]');
  const leadingBand = host.querySelector<SVGPathElement>(
    '[data-topology-path-role="leading-band"]',
  );
  const mergeNode = host.querySelector<SVGGElement>('[data-topology-node-kind="merge"]');
  const middleNode = host.querySelector<SVGGElement>('[data-topology-node-progress="0.5"]');
  const startNode = host.querySelector<SVGGElement>('[data-topology-node-progress="0"]');
  if (
    artwork === null ||
    corePath === null ||
    finalNode === null ||
    leadingBand === null ||
    mergeNode === null ||
    middleNode === null ||
    startNode === null
  ) {
    throw new Error("Topology fixture is incomplete");
  }

  const fixture = {
    artwork,
    corePath,
    dispose: initializeTopologyScrollReveal(artwork),
    finalNode,
    host,
    leadingBand,
    mergeNode,
    middleNode,
    startNode,
  } satisfies TopologyFixture;
  activeFixtures.push(fixture);
  return fixture;
}

async function waitForRevealRender(): Promise<void> {
  await new Promise<void>((resolve) => {
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => resolve());
    });
  });
}

async function scrollToProgress(progress: number): Promise<void> {
  const maximumScroll = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, maximumScroll * progress);
  await waitForRevealRender();
}

afterEach(() => {
  for (const fixture of activeFixtures.splice(0)) {
    fixture.dispose();
    fixture.host.remove();
  }
  window.scrollTo(0, 0);
  vi.restoreAllMocks();
});

describe("topology scroll reveal", () => {
  it("reveals and retracts paths and nodes with document scroll progress", async () => {
    const fixture = createTopologyFixture();

    await scrollToProgress(0);

    expect(fixture.artwork.hasAttribute("data-topology-at-start")).toBe(true);
    expect(fixture.startNode.style.opacity).toBe("1");
    expect(fixture.middleNode.style.opacity).toBe("0");
    expect(fixture.finalNode.style.opacity).toBe("0");
    expect(fixture.corePath.style.visibility).toBe("hidden");
    expect(fixture.leadingBand.style.visibility).toBe("hidden");

    await scrollToProgress(0.5);

    expect(Number(fixture.corePath.style.strokeDasharray.split(/[ ,]+/)[0])).toBeCloseTo(
      fixture.corePath.getTotalLength() * 0.5,
      2,
    );
    expect(fixture.corePath.style.strokeDashoffset).toBe("0");
    expect(fixture.middleNode.style.opacity).toBe("1");
    expect(fixture.finalNode.style.opacity).toBe("0");
    expect(fixture.leadingBand.style.visibility).toBe("visible");

    await scrollToProgress(1);

    expect(fixture.artwork.hasAttribute("data-topology-at-end")).toBe(true);
    expect(Number(fixture.corePath.style.strokeDasharray.split(/[ ,]+/)[0])).toBeCloseTo(
      fixture.corePath.getTotalLength(),
      3,
    );
    expect(fixture.finalNode.style.opacity).toBe("1");
    expect(fixture.leadingBand.style.visibility).toBe("hidden");

    await scrollToProgress(0);

    expect(fixture.artwork.hasAttribute("data-topology-at-end")).toBe(false);
    expect(fixture.finalNode.style.opacity).toBe("0");
    expect(fixture.corePath.style.visibility).toBe("hidden");
  });

  it("recomputes circular node glyphs through non-uniform viewport resizes", async () => {
    const fixture = createTopologyFixture();

    await waitForRevealRender();

    const representativeNodes = [fixture.startNode, fixture.middleNode, fixture.mergeNode];
    const assertCircularNodeShapes = (): void => {
      for (const node of representativeNodes) {
        const nodeShape = node.querySelector<SVGGElement>("[data-topology-node-shape]");
        if (nodeShape === null) {
          throw new Error("Topology fixture is missing a representative node shape");
        }
        const bounds = nodeShape.getBoundingClientRect();
        expect(bounds.width).toBeGreaterThan(0);
        expect(bounds.width).toBeCloseTo(bounds.height, 3);
        expect(nodeShape.getAttribute("transform")).toBeNull();
      }
    };
    const expectNodeTranslation = (node: SVGGElement, x: number, y: number): void => {
      const translation = readNodeTranslation(node);
      expect(translation.x).toBeCloseTo(x, 6);
      expect(translation.y).toBeCloseTo(y, 6);
    };

    assertCircularNodeShapes();
    expectNodeTranslation(fixture.startNode, 80, 50.335_570_469_798_654);
    expectNodeTranslation(fixture.middleNode, 120, 600);

    fixture.artwork.style.width = "320px";
    fixture.artwork.style.height = "600px";
    await waitForRevealRender();
    assertCircularNodeShapes();
    expectNodeTranslation(fixture.startNode, 142.222_222_222_222_2, 25.167_785_234_899_327);
    expectNodeTranslation(fixture.middleNode, 213.333_333_333_333_31, 300);

    fixture.artwork.style.width = "140px";
    fixture.artwork.style.height = "1000px";
    await waitForRevealRender();
    assertCircularNodeShapes();
    expectNodeTranslation(fixture.startNode, 62.222_222_222_222_22, 41.946_308_724_832_214);
    expectNodeTranslation(fixture.middleNode, 93.333_333_333_333_33, 500);
  });

  it("ignores scroll-era height noise but admits meaningful growth and window resize", async () => {
    const fixture = createTopologyFixture();

    await waitForRevealRender();
    expect(fixture.artwork.viewBox.baseVal.height).toBe(1200);

    fixture.artwork.style.height = "1208px";
    await waitForRevealRender();
    expect(fixture.artwork.viewBox.baseVal.height).toBe(1200);

    fixture.artwork.style.height = "1209px";
    await waitForRevealRender();
    expect(fixture.artwork.viewBox.baseVal.height).toBe(1209);

    fixture.artwork.style.height = "1215px";
    await waitForRevealRender();
    expect(fixture.artwork.viewBox.baseVal.height).toBe(1209);

    window.dispatchEvent(new Event("resize"));
    await waitForRevealRender();
    expect(fixture.artwork.viewBox.baseVal.height).toBe(1215);
  });

  it("renders a complete static topology when reduced motion is active", async () => {
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
    const fixture = createTopologyFixture();

    await scrollToProgress(0);

    const nodes = [
      ...fixture.artwork.querySelectorAll<SVGGraphicsElement>("[data-topology-node-progress]"),
    ];
    expect(nodes.every((node) => node.style.opacity === "1")).toBe(true);
    expect(Number(fixture.corePath.style.strokeDasharray.split(/[ ,]+/)[0])).toBeCloseTo(
      fixture.corePath.getTotalLength(),
      3,
    );
    expect(fixture.leadingBand.style.visibility).toBe("hidden");
    expect(fixture.artwork.hasAttribute("data-topology-at-start")).toBe(false);
    expect(fixture.artwork.hasAttribute("data-topology-at-end")).toBe(false);
  });
});
