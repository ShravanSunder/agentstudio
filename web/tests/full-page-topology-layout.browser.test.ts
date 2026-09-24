import { afterEach, describe, expect, it } from "vitest";
import { page } from "vitest/browser";

import { layoutFullPageTopology } from "../src/topology-lab/full-page-topology-layout";
import { mountTopologyFixture, type TopologyFixture } from "./topology-browser-fixture";

const fixtures: TopologyFixture[] = [];

function mount(layout: Parameters<typeof mountTopologyFixture>[0]): TopologyFixture {
  const fixture = mountTopologyFixture(layout);
  fixtures.push(fixture);
  return fixture;
}

function required(parent: ParentNode, selector: string): Element {
  const element = parent.querySelector(selector);
  if (element === null) {
    throw new Error(`Topology fixture is missing ${selector}`);
  }
  return element;
}

function requiredPath(parent: ParentNode, selector: string): SVGPathElement {
  const element = required(parent, selector);
  if (!(element instanceof SVGPathElement)) {
    throw new Error(`Topology fixture ${selector} is not a path`);
  }
  return element;
}

/** A path's end point in viewport coordinates. */
function pathEnd(artwork: SVGSVGElement, path: SVGPathElement): DOMPoint {
  const end = path.getPointAtLength(path.getTotalLength());
  const origin = artwork.getBoundingClientRect();
  return new DOMPoint(origin.left + end.x, origin.top + end.y);
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.host.remove();
  }
});

describe("full-page topology layout", () => {
  it("hides the artwork when the page has no chapter anchors", async () => {
    // Arrange
    await page.viewport(1280, 800);
    const fixture = mount({ contentLeft: 116, anchorTops: [], height: 2000, phone: false });
    for (const hook of fixture.host.querySelectorAll("[data-rail-anchor]")) {
      hook.removeAttribute("data-rail-anchor");
    }

    // Act
    layoutFullPageTopology(fixture.artwork);

    // Assert
    expect(fixture.artwork.style.visibility).toBe("hidden");
    expect(fixture.artwork.dataset["topologyHiddenReason"]).toBe("no-rail-anchors");
  });

  it("draws the mainline from the page top with one dot per row and chapter dots level with their titles' first lines", async () => {
    // Arrange
    await page.viewport(1920, 1080);
    const fixture = mount({
      contentLeft: 383,
      anchorTops: [110, 1300, 2060, 2820],
      height: 4400,
      phone: false,
    });

    // Act
    expect(layoutFullPageTopology(fixture.artwork)).toBe(true);

    // Assert
    const mainline = requiredPath(fixture.artwork, "[data-mainline]");
    expect(mainline.getPointAtLength(0).y).toBe(0);
    const nodes = [...fixture.artwork.querySelectorAll<SVGGElement>("[data-node]")];
    expect(nodes).toHaveLength(Number(fixture.artwork.dataset["rowCount"]));
    const nodeYs = nodes.map((node) => node.querySelector("circle")?.getAttribute("cy"));
    expect(new Set(nodeYs).size).toBe(nodes.length);
    for (const anchor of fixture.host.querySelectorAll<HTMLElement>("[data-rail-anchor]")) {
      const id = anchor.dataset["railAnchor"];
      const node = required(fixture.artwork, `[data-topology-chapter-node="${id}"]`);
      const nodeBounds = node.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(anchor);
      const [firstLine] = range.getClientRects();
      if (firstLine === undefined) {
        throw new Error(`Anchor ${id ?? ""} has no line box`);
      }
      expect(
        Math.abs(nodeBounds.top + nodeBounds.height / 2 - (firstLine.top + firstLine.height / 2)),
      ).toBeLessThanOrEqual(1);
    }
    // Chapter titles wrap, so the first line sits above the title's centre.
    const title = required(fixture.host, '[data-rail-anchor="chapter-1"]');
    expect(title.getClientRects()[0]?.height).toBeGreaterThan(40);
    expect(Number(fixture.artwork.dataset["laneCount"])).toBeGreaterThan(0);
  });

  it("attaches each chapter glass with a one-column branch into its left edge", async () => {
    // Arrange
    await page.viewport(1920, 1080);
    const fixture = mount({
      contentLeft: 383,
      anchorTops: [110, 1300, 2060, 2820],
      height: 4400,
      phone: false,
    });

    // Act
    layoutFullPageTopology(fixture.artwork);

    // Assert
    const unit = Number(fixture.artwork.dataset["columnUnit"]);
    for (const group of fixture.artwork.querySelectorAll<SVGGElement>(
      '[data-route-kind="attach"]',
    )) {
      const anchorId = group.dataset["routeAnchor"];
      const glass = required(fixture.host, `[data-rail-surface-target="${anchorId}"]`);
      const core = requiredPath(group, '[data-topology-path-role="core"]');
      const start = core.getPointAtLength(0);
      const end = pathEnd(fixture.artwork, core);
      const glassBounds = glass.getBoundingClientRect();
      expect(Math.abs(end.x - glassBounds.left)).toBeLessThanOrEqual(1);
      expect(end.y).toBeGreaterThan(glassBounds.top);
      expect(end.y).toBeLessThan(glassBounds.bottom);
      expect(end.x - (fixture.artwork.getBoundingClientRect().left + start.x)).toBeCloseTo(unit, 0);
      // The port is primary blue and ends in a node exactly on the glass edge.
      expect(group.classList.contains("accent-port")).toBe(true);
      const port = required(group, "[data-topology-port-node]").getBoundingClientRect();
      expect(Math.abs(port.left + port.width / 2 - glassBounds.left)).toBeLessThanOrEqual(1);
      expect(Math.abs(port.top + port.height / 2 - end.y)).toBeLessThanOrEqual(1);
    }
  });

  it("draws a single mainline on a phone and drops each branch into its glass's top edge", async () => {
    // Arrange
    await page.viewport(390, 844);
    const fixture = mount({
      contentLeft: 40,
      anchorTops: [96, 1100, 1700],
      height: 2600,
      phone: true,
    });

    // Act
    layoutFullPageTopology(fixture.artwork);

    // Assert
    expect(fixture.artwork.dataset["laneCount"]).toBe("0");
    expect(fixture.artwork.querySelectorAll('[data-route-kind="worktree"]')).toHaveLength(0);
    for (const group of fixture.artwork.querySelectorAll<SVGGElement>(
      '[data-route-kind="attach"]',
    )) {
      const anchorId = group.dataset["routeAnchor"];
      const glass = required(fixture.host, `[data-rail-surface-target="${anchorId}"]`);
      const end = pathEnd(fixture.artwork, requiredPath(group, '[data-topology-path-role="core"]'));
      const glassBounds = glass.getBoundingClientRect();
      expect(Math.abs(end.y - glassBounds.top)).toBeLessThanOrEqual(1);
      expect(end.x - glassBounds.left).toBeGreaterThanOrEqual(16 + 8);
    }
  });
});
