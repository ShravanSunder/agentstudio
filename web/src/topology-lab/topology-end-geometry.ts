import type { TopologyPageMeasurement, TopologyRect } from "./full-page-topology-composition";
import { topologyRowUnit } from "./full-page-topology-model";

export function topologyRectBottom(rect: TopologyRect): number {
  return rect.top + rect.height;
}

export function topologyRectCenterY(rect: TopologyRect): number {
  return rect.top + rect.height / 2;
}

/**
 * The mainline ends halfway between the bottom of the last chapter glass and
 * the top of the CTA icon. Without both measurements, it falls back to one
 * row above the CTA section or page end.
 */
export function topologyEndY(page: TopologyPageMeasurement): number {
  const end = page.end;
  const lastGlassBottom = page.anchors.reduce<number | undefined>((currentBottom, anchor) => {
    if (anchor.surface === undefined) {
      return currentBottom;
    }
    const glassBottom = topologyRectBottom(anchor.surface);
    return currentBottom === undefined ? glassBottom : Math.max(currentBottom, glassBottom);
  }, undefined);
  if (end?.mark !== undefined && lastGlassBottom !== undefined) {
    return (lastGlassBottom + end.mark.top) / 2;
  }
  if (end !== undefined) {
    return end.section.top - topologyRowUnit;
  }
  return page.height - topologyRowUnit;
}
