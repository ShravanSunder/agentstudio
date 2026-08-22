export const productPlateStoryIds = [
  "parallel-work",
  "watch-folder",
  "quick-find",
  "files",
  "review",
] as const;

export type ProductPlateStoryId = (typeof productPlateStoryIds)[number];

export function isProductPlateStoryId(candidate: string): candidate is ProductPlateStoryId {
  return productPlateStoryIds.some((storyId) => storyId === candidate);
}
