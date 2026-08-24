import { afterEach, describe, expect, it } from "vitest";

import { layoutFullPageTopology } from "../src/topology-lab/full-page-topology-layout";
import { maximumRenderedTopologyRowCount } from "../src/topology-lab/full-page-topology-model";

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
        data-route-placement="local-right"
        data-topology-variants="compact standard expanded"
        data-fork-page-row="2"
        data-end-page-offset="4"
        data-end-kind="open"
      >
        <path data-route data-topology-path-role="core"></path>
        <circle data-node data-node-position="fork" r="4"></circle>
        <circle data-node data-node-position="end" r="4"></circle>
      </g>
      <g data-node data-mainline-node="start"></g>
      <g data-node data-mainline-node="end"></g>
      <g data-mainline-fill-nodes></g>
    </svg>
  `;
  document.body.append(host);
  fixtures.push(host);

  const artwork = host.querySelector<SVGSVGElement>("svg");
  if (artwork === null) {
    throw new Error("Full-page topology fixture is missing its artwork");
  }
  const fillContainer = artwork.querySelector<SVGGElement>("[data-mainline-fill-nodes]");
  if (fillContainer === null) {
    throw new Error("Full-page topology fixture is missing its fill-node container");
  }
  for (let fillIndex = 0; fillIndex < maximumRenderedTopologyRowCount; fillIndex += 1) {
    const fillNode = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    fillNode.dataset["node"] = "";
    fillNode.dataset["mainlineFillIndex"] = String(fillIndex);
    fillContainer.append(fillNode);
  }
  return artwork;
}

afterEach(() => {
  for (const fixture of fixtures.splice(0)) {
    fixture.remove();
  }
});

describe("full-page topology layout", () => {
  it("fails closed when a cross-glass route also authors a page-row fork", () => {
    const artwork = createArtwork(576, 1424);
    const route = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (route === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    route.dataset["routePlacement"] = "cross-glass-left";
    route.dataset["forkGlassIndex"] = "0";
    route.dataset["forkPageRow"] = "2";

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("invalid-authored-route");
  });

  it("fails closed when duplicate route IDs appear across placements", () => {
    const artwork = createArtwork(576, 1424);
    const firstRoute = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (firstRoute === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    const duplicateRoute = firstRoute.cloneNode(true);
    if (!(duplicateRoute instanceof SVGGElement)) {
      throw new Error("Cloned topology route is not an SVG group");
    }
    duplicateRoute.dataset["routePlacement"] = "cross-glass-left";
    duplicateRoute.dataset["topologyVariants"] = "expanded";
    duplicateRoute.dataset["forkGlassIndex"] = "0";
    duplicateRoute.removeAttribute("data-fork-page-row");
    artwork.append(duplicateRoute);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("invalid-authored-route");
  });

  it("fails closed when a wider variant would move a shared route to another side slot", () => {
    const artwork = createArtwork(576, 1424);
    const sharedRoute = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (sharedRoute === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    const expandedRoute = sharedRoute.cloneNode(true);
    if (!(expandedRoute instanceof SVGGElement)) {
      throw new Error("Cloned topology route is not an SVG group");
    }
    expandedRoute.dataset["routeId"] = "expanded-earlier";
    expandedRoute.dataset["topologyVariants"] = "expanded";
    expandedRoute.dataset["forkPageRow"] = "1";
    expandedRoute.dataset["endPageOffset"] = "5";
    artwork.append(expandedRoute);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("invalid-variant-identity");
  });

  it("fails closed when authored placement conflicts with route geometry", () => {
    const artwork = createArtwork(576, 1424);
    const route = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (route === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    route.dataset["routePlacement"] = "cross-glass-left";

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("invalid-authored-route");
  });

  it("preserves distinct absolute bottom rows instead of quantizing them through glass slots", () => {
    const artwork = createArtwork(576, 1424);
    const firstRoute = artwork.querySelector<SVGGElement>("[data-topology-route-group]");
    if (firstRoute === null) {
      throw new Error("Full-page topology fixture route is missing");
    }
    firstRoute.dataset["forkPageRow"] = "2";
    firstRoute.dataset["endPageOffset"] = "3";

    const secondRoute = firstRoute.cloneNode(true);
    if (!(secondRoute instanceof SVGGElement)) {
      throw new Error("Cloned topology route is not an SVG group");
    }
    secondRoute.dataset["routeId"] = "d";
    secondRoute.dataset["forkPageRow"] = "4";
    secondRoute.dataset["endPageOffset"] = "4";
    secondRoute.dataset["topologyVariants"] = "expanded";
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
    expect(artwork.dataset["columnCount"]).toBe("4");
    expect(artwork.dataset["leftColumnCount"]).toBe("0");
    expect(artwork.dataset["rightColumnCount"]).toBe("2");
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
    const routeGroup = route.closest<SVGGElement>("[data-topology-route-group]");
    if (routeGroup === null) {
      throw new Error("Full-page topology route group is missing");
    }
    const routeStart = route.getPointAtLength(0);
    const routeEnd = route.getPointAtLength(route.getTotalLength());
    expect(routeStart.x).toBe(Number(routeGroup.dataset["resolvedSourceX"]));
    expect(routeEnd.x).toBe(Number(routeGroup.dataset["resolvedTargetX"]));
    expect(routeStart.y).toBeLessThan(routeEnd.y);

    const resolvedRows = [...artwork.querySelectorAll<SVGGraphicsElement>("[data-node]")]
      .filter((node) => getComputedStyle(node).display !== "none")
      .map((node) => Number(node.dataset["resolvedRow"]))
      .toSorted((left, right) => left - right);
    expect(resolvedRows).toEqual(Array.from({ length: 53 }, (_, row) => row));
    expect(new Set(resolvedRows).size).toBe(resolvedRows.length);
  });

  it("hides the complete composition when either gutter has fewer than two usable columns", () => {
    const artwork = createArtwork(191, 1809);

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("insufficient-gutter-capacity");
    expect(artwork.dataset["topologyVariant"]).toBeUndefined();
  });

  it("fails closed when the page exceeds the statically styled row capacity", () => {
    const artwork = createArtwork(576, 1424);
    artwork.style.height = `${(maximumRenderedTopologyRowCount + 10) * 96}px`;

    expect(layoutFullPageTopology(artwork)).toBe(true);
    expect(artwork.style.visibility).toBe("hidden");
    expect(artwork.dataset["topologyHiddenReason"]).toBe("insufficient-mainline-fill-nodes");
  });
});
