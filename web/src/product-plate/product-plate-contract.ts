export const productPlateStoryIds = [
  "parallel-work",
  "pane-drawer",
  "quick-find",
  "review",
  "git-context",
] as const;

export type ProductPlateStoryId = (typeof productPlateStoryIds)[number];

export function isProductPlateStoryId(candidate: string): candidate is ProductPlateStoryId {
  return productPlateStoryIds.some((storyId) => storyId === candidate);
}
