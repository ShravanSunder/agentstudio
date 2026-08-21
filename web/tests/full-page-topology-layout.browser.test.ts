import { afterEach, describe, expect, it } from "vitest";

import { layoutFullPageTopology } from "../src/topology-lab/full-page-topology-layout";

const fixtures: HTMLDivElement[] = [];

function createArtwork(width: number, height: number): SVGSVGElement {
  const host = document.createElement("div");
  host.innerHTML = `
    <svg
      data-design-final-row="52"
      style="display: block; width: ${width}px; height: ${height}px"
      viewBox="0 0 1 1"
    >
      <path data-mainline></path>
      <path
        data-route
        data-source-lane="0"
        data-lane="8"
        data-fork-row="0"
        data-arrival-row="4"
        data-open-end-row="52"
      ></path>
      <path
        data-route
        data-source-lane="0"
        data-lane="4"
        data-fork-row="10"
        data-arrival-row="14"
        data-merge-approach-row="48"
        data-merge-row="52"
      ></path>
      <circle data-node data-lane="8" data-row="52" r="4"></circle>
    </svg>
  `;
  document.body.append(host);
  fixtures.push(host);

  const artwork = host.querySelector<SVGSVGElement>("svg");
  if (artwork === null) {
    throw new Error("Full-page topology fixture is missing its artwork");
  }
  return artwork;
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
});

describe("full-page topology layout", () => {
  it("uses measured grid slots and single-bend fork curves", () => {
    const artwork = createArtwork(960, 2120);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.dataset["columnCount"]).toBe("9");
    expect(artwork.dataset["rowCount"]).toBe("21");
    expect(artwork.dataset["finalRow"]).toBe("20");

    const route = artwork.querySelector<SVGPathElement>("[data-route]");
    const finalNode = artwork.querySelector<SVGCircleElement>("[data-node]");
    if (route === null || finalNode === null) {
      throw new Error("Full-page topology fixture geometry is incomplete");
    }

    const routePath = route.getAttribute("d") ?? "";
    expect(routePath).toMatch(/^M .+ C .+ L .+$/);
    const routeCoordinates = routePath.match(/-?\d+(?:\.\d+)?/g)?.map(Number);
    expect(routeCoordinates).toHaveLength(10);
    const expectedCoordinates = [878.4, 96, 187.2, 111.36, 110.4, 115.2, 110.4, 288, 110.4, 2016];
    for (const [index, expectedCoordinate] of expectedCoordinates.entries()) {
      expect(routeCoordinates?.[index]).toBeCloseTo(expectedCoordinate, 6);
    }
    expect(Number(finalNode.getAttribute("cx"))).toBeCloseTo(110.4, 6);
    expect(Number(finalNode.getAttribute("cy"))).toBe(2016);

    const mergingRoute = artwork.querySelector<SVGPathElement>('[data-merge-row="52"]');
    if (mergingRoute === null) {
      throw new Error("Full-page topology fixture merging route is missing");
    }
    const mergePath = mergingRoute.getAttribute("d") ?? "";
    const mergeCoordinates = mergePath.match(/-?\d+(?:\.\d+)?/g)?.map(Number);
    const expectedMergeCoordinates = [
      878.4, 480, 532.8, 487.68, 494.4, 489.6, 494.4, 576, 494.4, 1824, 494.4, 1996.8, 532.8,
      2000.64, 878.4, 2016,
    ];
    expect(mergeCoordinates).toHaveLength(expectedMergeCoordinates.length);
    for (const [index, expectedCoordinate] of expectedMergeCoordinates.entries()) {
      expect(mergeCoordinates?.[index]).toBeCloseTo(expectedCoordinate, 6);
    }
  });

  it("recomputes available slots without stretching fixed column and row units", () => {
    const artwork = createArtwork(672, 1352);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.dataset["columnCount"]).toBe("6");
    expect(artwork.dataset["rowCount"]).toBe("13");
    expect(artwork.dataset["finalRow"]).toBe("12");

    const finalNode = artwork.querySelector<SVGCircleElement>("[data-node]");
    if (finalNode === null) {
      throw new Error("Full-page topology fixture final node is missing");
    }
    expect(Number(finalNode.getAttribute("cx"))).toBe(128);
    expect(Number(finalNode.getAttribute("cy"))).toBe(1248);
  });
});
