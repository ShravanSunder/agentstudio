import type { ImageMetadata } from "astro";

import paneDrawerImage from "@/assets/captures/pane-drawer.png";
import parallelWorkImage from "@/assets/captures/parallel-work.png";
import persistentBeforeImage from "@/assets/captures/persistent-before.png";
import persistentRestoredImage from "@/assets/captures/persistent-restored.png";
import quickFindImage from "@/assets/captures/quick-find.png";
import reviewImage from "@/assets/captures/review.png";
import { marketingCopy } from "@/marketing-copy";

import type { ProductPlateStoryId } from "./product-plate-contract";

interface SingleImageStory {
  readonly kind: "single-image";
  readonly id: Exclude<ProductPlateStoryId, "persistent-workspace">;
  readonly label: string;
  readonly description: string;
  readonly image: ImageMetadata;
  readonly alternativeText: string;
}

interface PersistenceComparisonStory {
  readonly kind: "persistence-comparison";
  readonly id: "persistent-workspace";
  readonly label: string;
  readonly description: string;
  readonly beforeImage: ImageMetadata;
  readonly restoredImage: ImageMetadata;
}

export type ProductPlateStory = SingleImageStory | PersistenceComparisonStory;

export const productPlateStories = [
  {
    kind: "single-image",
    id: "parallel-work",
    label: marketingCopy.stories.parallelWork.label,
    description: marketingCopy.stories.parallelWork.description,
    image: parallelWorkImage,
    alternativeText: marketingCopy.stories.parallelWork.imageDescription,
  },
  {
    kind: "single-image",
    id: "pane-drawer",
    label: marketingCopy.stories.paneDrawer.label,
    description: marketingCopy.stories.paneDrawer.description,
    image: paneDrawerImage,
    alternativeText: marketingCopy.stories.paneDrawer.imageDescription,
  },
  {
    kind: "single-image",
    id: "quick-find",
    label: marketingCopy.stories.quickFind.label,
    description: marketingCopy.stories.quickFind.description,
    image: quickFindImage,
    alternativeText: marketingCopy.stories.quickFind.imageDescription,
  },
  {
    kind: "single-image",
    id: "review",
    label: marketingCopy.stories.review.label,
    description: marketingCopy.stories.review.description,
    image: reviewImage,
    alternativeText: marketingCopy.stories.review.imageDescription,
  },
  {
    kind: "persistence-comparison",
    id: "persistent-workspace",
    label: marketingCopy.stories.persistence.label,
    description: marketingCopy.stories.persistence.description,
    beforeImage: persistentBeforeImage,
    restoredImage: persistentRestoredImage,
  },
] as const satisfies readonly ProductPlateStory[];
