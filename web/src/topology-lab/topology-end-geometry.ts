import type { TopologyPageMeasurement, TopologyRect } from "./full-page-topology-composition";
import { topologyRowUnit } from "./full-page-topology-model";

export function topologyRectBottom(rect: TopologyRect): number {
  return rect.top + rect.height;
}

export function topologyRectCenterY(rect: TopologyRect): number {
  return rect.top + rect.height / 2;
}

/** The rail's reveal ends at the DOM-declared terminal target's center. */
export function topologyEndY(page: TopologyPageMeasurement): number {
  const target = page.anchors.find((anchor) => anchor.terminalTarget)?.surface;
  return target === undefined ? page.height - topologyRowUnit : topologyRectCenterY(target);
}
