import type { FullPageTopologyVariant, WorktreeEndKind } from "./full-page-topology-model";

export type TopologyRouteAccent = "cyan" | "peach";
export type TopologyRoutePlacement = "cross-glass-left" | "local-right";

interface TopologyRouteBase {
  readonly accent: TopologyRouteAccent;
  readonly endKind: WorktreeEndKind;
  readonly id: string;
  readonly variants: readonly FullPageTopologyVariant[];
}

type PageEndAnchor =
  | { readonly endPageOffset: number; readonly endPageRow?: never }
  | { readonly endPageOffset?: never; readonly endPageRow: number };

export type TopologyRouteContract =
  | (TopologyRouteBase &
      PageEndAnchor & {
        readonly endGlassIndex?: never;
        readonly forkGlassIndex?: never;
        readonly forkPageRow: number;
        readonly placement: "local-right";
      })
  | (TopologyRouteBase & {
      readonly endGlassIndex: number;
      readonly endKind: "merge";
      readonly endPageOffset?: never;
      readonly endPageRow?: never;
      readonly forkGlassIndex: number;
      readonly forkPageRow?: never;
      readonly placement: "cross-glass-left";
    })
  | (TopologyRouteBase &
      PageEndAnchor & {
        readonly endGlassIndex?: never;
        readonly endKind: "open";
        readonly forkGlassIndex: number;
        readonly forkPageRow?: never;
        readonly placement: "cross-glass-left";
      });

export const authoredTopologyRoutes: readonly TopologyRouteContract[] = [
  {
    accent: "peach",
    endKind: "merge",
    endPageRow: 15,
    forkPageRow: 2,
    id: "worktree-a",
    placement: "local-right",
    variants: ["compact", "standard", "expanded"],
  },
  {
    accent: "cyan",
    endKind: "merge",
    endPageRow: 16,
    forkPageRow: 4,
    id: "worktree-b",
    placement: "local-right",
    variants: ["standard", "expanded"],
  },
  {
    accent: "peach",
    endGlassIndex: 3,
    endKind: "merge",
    forkGlassIndex: 0,
    id: "worktree-c",
    placement: "cross-glass-left",
    variants: ["compact", "standard", "expanded"],
  },
  {
    accent: "cyan",
    endKind: "open",
    endPageOffset: 4,
    forkGlassIndex: 1,
    id: "worktree-d",
    placement: "cross-glass-left",
    variants: ["compact", "standard", "expanded"],
  },
  {
    accent: "peach",
    endKind: "merge",
    endPageOffset: 3,
    forkPageRow: 17,
    id: "worktree-e",
    placement: "local-right",
    variants: ["compact", "standard", "expanded"],
  },
  {
    accent: "cyan",
    endKind: "open",
    endPageOffset: 2,
    forkPageRow: 18,
    id: "worktree-f",
    placement: "local-right",
    variants: ["standard", "expanded"],
  },
  {
    accent: "peach",
    endKind: "open",
    endPageOffset: 1,
    forkGlassIndex: 2,
    id: "worktree-g",
    placement: "cross-glass-left",
    variants: ["standard", "expanded"],
  },
] as const;

function requiredDatasetNumber(element: SVGElement, key: string): number {
  const value = element.dataset[key];
  const numberValue = Number(value);
  if (value === undefined || value === "" || !Number.isFinite(numberValue)) {
    throw new Error(`Invalid topology data attribute: ${key}`);
  }
  return numberValue;
}

function optionalDatasetNumber(element: SVGElement, key: string): number | undefined {
  return element.dataset[key] === undefined ? undefined : requiredDatasetNumber(element, key);
}

function isTopologyVariant(value: string): value is FullPageTopologyVariant {
  return value === "compact" || value === "standard" || value === "expanded";
}

export function readTopologyRouteContract(group: SVGGElement): TopologyRouteContract {
  const accent = group.dataset["routeAccent"];
  const endKind = group.dataset["endKind"];
  const id = group.dataset["routeId"];
  const placement = group.dataset["routePlacement"];
  const variants = (group.dataset["topologyVariants"] ?? "").split(" ").filter(isTopologyVariant);
  if (
    (accent !== "cyan" && accent !== "peach") ||
    (endKind !== "merge" && endKind !== "open") ||
    !id ||
    (placement !== "local-right" && placement !== "cross-glass-left") ||
    variants.length === 0
  ) {
    throw new Error("Invalid authored topology route");
  }

  const endGlassIndex = optionalDatasetNumber(group, "endGlassIndex");
  const endPageOffset = optionalDatasetNumber(group, "endPageOffset");
  const endPageRow = optionalDatasetNumber(group, "endPageRow");
  const forkGlassIndex = optionalDatasetNumber(group, "forkGlassIndex");
  const forkPageRow = optionalDatasetNumber(group, "forkPageRow");
  const base = { accent, endKind, id, variants } satisfies TopologyRouteBase;

  if (placement === "local-right") {
    if (
      forkPageRow === undefined ||
      forkGlassIndex !== undefined ||
      endGlassIndex !== undefined ||
      (endPageOffset === undefined) === (endPageRow === undefined)
    ) {
      throw new Error("Invalid authored topology placement");
    }
    return endPageOffset === undefined
      ? { ...base, endPageRow: requiredDatasetNumber(group, "endPageRow"), forkPageRow, placement }
      : { ...base, endPageOffset, forkPageRow, placement };
  }

  if (forkGlassIndex === undefined || forkPageRow !== undefined) {
    throw new Error("Invalid authored topology placement");
  }
  if (endKind === "merge") {
    if (endGlassIndex === undefined || endPageOffset !== undefined || endPageRow !== undefined) {
      throw new Error("Invalid authored topology placement");
    }
    return { ...base, endGlassIndex, endKind, forkGlassIndex, placement };
  }
  if (endGlassIndex !== undefined || (endPageOffset === undefined) === (endPageRow === undefined)) {
    throw new Error("Invalid authored topology placement");
  }
  return endPageOffset === undefined
    ? {
        ...base,
        endKind,
        endPageRow: requiredDatasetNumber(group, "endPageRow"),
        forkGlassIndex,
        placement,
      }
    : { ...base, endKind, endPageOffset, forkGlassIndex, placement };
}
