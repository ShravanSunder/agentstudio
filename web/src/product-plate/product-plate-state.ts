import {
  isProductPlateStoryId,
  productPlateStoryIds,
  type ProductPlateStoryId,
} from "./product-plate-contract";

export type ProductPlateState =
  | { readonly kind: "static"; readonly selectedStoryId: "watch-folder" }
  | { readonly kind: "active"; readonly selectedStoryId: ProductPlateStoryId };

export type ProductPlateEvent =
  | { readonly kind: "activate" }
  | { readonly kind: "select"; readonly storyId: ProductPlateStoryId }
  | { readonly kind: "move"; readonly direction: "first" | "last" | "next" | "previous" }
  | { readonly kind: "rollback" };

export const initialProductPlateState: ProductPlateState = {
  kind: "static",
  selectedStoryId: "watch-folder",
};

function unexpectedProductPlateEvent(event: never): never {
  throw new Error(`Unexpected product plate event: ${JSON.stringify(event)}`);
}

function adjacentStoryId(
  selectedStoryId: ProductPlateStoryId,
  direction: "next" | "previous",
): ProductPlateStoryId {
  const selectedIndex = productPlateStoryIds.indexOf(selectedStoryId);
  const offset = direction === "next" ? 1 : -1;
  const nextIndex =
    (selectedIndex + offset + productPlateStoryIds.length) % productPlateStoryIds.length;
  const nextStoryId = productPlateStoryIds[nextIndex];

  if (nextStoryId === undefined) {
    throw new Error("Product plate story index resolved outside the closed story set.");
  }

  return nextStoryId;
}

export function reduceProductPlateState(
  state: ProductPlateState,
  event: ProductPlateEvent,
): ProductPlateState {
  switch (event.kind) {
    case "activate":
      return { kind: "active", selectedStoryId: state.selectedStoryId };
    case "rollback":
      return initialProductPlateState;
    case "select":
      return state.kind === "active" ? { kind: "active", selectedStoryId: event.storyId } : state;
    case "move": {
      if (state.kind === "static") {
        return state;
      }

      if (event.direction === "first") {
        return { kind: "active", selectedStoryId: "watch-folder" };
      }
      if (event.direction === "last") {
        return { kind: "active", selectedStoryId: "review" };
      }

      return {
        kind: "active",
        selectedStoryId: adjacentStoryId(state.selectedStoryId, event.direction),
      };
    }
    default:
      return unexpectedProductPlateEvent(event);
  }
}

export function parseProductPlateStoryId(candidate: string): ProductPlateStoryId | null {
  return isProductPlateStoryId(candidate) ? candidate : null;
}
