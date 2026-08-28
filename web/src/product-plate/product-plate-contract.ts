export const productPlateStoryIds = [
  "watch-folder",
  "parallel-work",
  "quick-find",
  "files",
  "review",
] as const;

export type ProductPlateStoryId = (typeof productPlateStoryIds)[number];

export function isProductPlateStoryId(candidate: string): candidate is ProductPlateStoryId {
  return productPlateStoryIds.some((storyId) => storyId === candidate);
}
