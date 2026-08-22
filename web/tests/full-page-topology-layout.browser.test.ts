import { afterEach, describe, expect, it } from "vitest";

import { layoutFullPageTopology } from "../src/topology-lab/full-page-topology-layout";

const fixtures: HTMLDivElement[] = [];

function createArtwork(frameLeft: number, frameRight: number): SVGSVGElement {
  const host = document.createElement("div");
  host.style.cssText = "position:relative;width:2000px;height:5200px";
  host.innerHTML = `
    <div data-anchor style="position:absolute;top:89px;left:1900px;width:14px;height:14px"></div>
    <div data-frame style="position:absolute;top:0;left:${frameLeft}px;width:${frameRight - frameLeft}px;height:5200px"></div>
    <div data-glass style="position:absolute;top:480px;left:${frameLeft}px;width:${frameRight - frameLeft}px;height:192px"></div>
    <div data-glass style="position:absolute;top:1728px;left:${frameLeft}px;width:${frameRight - frameLeft}px;height:192px"></div>
    <div data-glass style="position:absolute;top:2496px;left:${frameLeft}px;width:${frameRight - frameLeft}px;height:192px"></div>
    <div data-glass style="position:absolute;top:2592px;left:${frameLeft}px;width:${frameRight - frameLeft}px;height:192px"></div>
    <svg
      data-full-page-topology
      data-mainline-anchor-selector="[data-anchor]"
      data-portal-frame-selector="[data-frame]"
      data-portal-surface-selector="[data-glass]"
      style="display:block;width:2000px;height:5200px"
    >
      <path data-mainline data-topology-path-role="core"></path>
      <g
        data-topology-route-group
        data-route-id="a"
        data-route-accent="peach"
        data-minimum-columns="2"
        data-fork-slot="2"
        data-end-slot="18"
        data-end-kind="open"
      >
        <path data-route data-topology-path-role="core"></path>
        <circle data-node data-node-position="fork" r="4"></circle>
        <circle data-node data-node-position="target" data-node-slot="3" r="4"></circle>
        <circle data-node data-node-position="end" r="4"></circle>
      </g>
      <g data-node data-mainline-node="start"></g>
      <g data-node data-mainline-node="end"></g>
    </svg>
  `;
  document.body.append(host);
  fixtures.push(host);

  const artwork = host.querySelector<SVGSVGElement>("svg");
  if (artwork === null) {
    throw new Error("Full-page topology fixture is missing its artwork");
  }
  for (let fillIndex = 0; fillIndex < 64; fillIndex += 1) {
    const fillNode = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    fillNode.dataset["node"] = "";
    fillNode.dataset["mainlineFillIndex"] = String(fillIndex);
    artwork.append(fillNode);
  }
  return artwork;
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
});

describe("full-page topology layout", () => {
  it("preserves distinct absolute bottom rows instead of quantizing them through glass slots", () => {
    const artwork = createArtwork(576, 1424);
    const firstRoute = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (firstRoute === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    firstRoute.querySelector('[data-node-position="target"]')?.remove();
    firstRoute.dataset["forkPageRow"] = "2";
    firstRoute.dataset["endPageOffset"] = "3";

    const secondRoute = firstRoute.cloneNode(true);
    if (!(secondRoute instanceof SVGGElement)) {
      throw new Error("Cloned topology route is not an SVG group");
    }
    secondRoute.dataset["routeId"] = "d";
    secondRoute.dataset["forkPageRow"] = "4";
    secondRoute.dataset["forkSlot"] = "4";
    secondRoute.dataset["endPageOffset"] = "4";
    secondRoute.dataset["endSlot"] = "17";
    artwork.append(secondRoute);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("visible");
    expect(artwork.dataset["topologyHiddenReason"]).toBeUndefined();
    expect(
      [...artwork.querySelectorAll<SVGGraphicsElement>('[data-node-position="end"]')].map((node) =>
        Number(node.dataset["resolvedRow"]),
      ),
    ).toEqual([49, 48]);
  });

  it("projects a main-based worktree into the nearest free gutter column", () => {
    const artwork = createArtwork(576, 1424);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.dataset["columnCount"]).toBe("5");
    expect(artwork.dataset["topologyVariant"]).toBe("expanded");
    expect(artwork.dataset["firstGlassRow"]).toBe("5");
    expect(artwork.dataset["lastGlassRow"]).toBe("27");
    expect(artwork.dataset["worktreeCount"]).toBe("1");

    const route = artwork.querySelector<SVGPathElement>(
      '[data-route][data-topology-path-role="core"]',
    );
    if (route === null) {
      throw new Error("Full-page topology route is missing");
    }
    expect(route.getAttribute("d")).toBe(
      "M 1856 768 C 1769.6 775.68 1760 777.6 1760 864 L 1760 2496",
    );

    const resolvedRows = [...artwork.querySelectorAll<SVGGraphicsElement>("[data-node]")]
      .filter((node) => getComputedStyle(node).display !== "none")
      .map((node) => Number(node.dataset["resolvedRow"]))
      .toSorted((left, right) => left - right);
    expect(resolvedRows).toEqual(Array.from({ length: 53 }, (_, row) => row));
    expect(new Set(resolvedRows).size).toBe(resolvedRows.length);
  });

  it("hides the complete composition when either gutter has fewer than two usable columns", () => {
    const artwork = createArtwork(287, 1713);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("insufficient-gutter-capacity");
    expect(artwork.dataset["topologyVariant"]).toBeUndefined();
  });
});
