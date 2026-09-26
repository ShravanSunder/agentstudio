import type { TopologyPageMeasurement, TopologyRect } from "./full-page-topology-composition";
import { topologyRowUnit } from "./full-page-topology-model";

export function topologyRectBottom(rect: TopologyRect): number {
  return rect.top + rect.height;
}

export function topologyRectCenterY(rect: TopologyRect): number {
  return rect.top + rect.height / 2;
}

/** The mainline ends at the last chapter glass's vertical center. */
export function topologyEndY(page: TopologyPageMeasurement): number {
  const lastGlass = page.anchors
    .toReversed()
    .find((anchor) => anchor.surface !== undefined)?.surface;
  return lastGlass === undefined ? page.height - topologyRowUnit : topologyRectCenterY(lastGlass);
}
