import type { ImageMetadata } from "astro";

import gitContextImage from "@/assets/captures/git-pull-request-context.png";
import paneDrawerImage from "@/assets/captures/pane-drawer.png";
import parallelWorkImage from "@/assets/captures/parallel-work.png";
import quickFindImage from "@/assets/captures/quick-find.png";
import reviewImage from "@/assets/captures/review.png";
import { marketingCopy } from "@/marketing-copy";

import type { ProductPlateStoryId } from "./product-plate-contract";

interface SingleImageStory {
  readonly kind: "single-image";
  readonly id: ProductPlateStoryId;
  readonly label: string;
  readonly description: string;
  readonly image: ImageMetadata;
  readonly alternativeText: string;
}

export type ProductPlateStory = SingleImageStory;

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
    kind: "single-image",
    id: "git-context",
    label: marketingCopy.stories.gitContext.label,
    description: marketingCopy.stories.gitContext.description,
    image: gitContextImage,
    alternativeText: marketingCopy.stories.gitContext.imageDescription,
  },
] as const satisfies readonly ProductPlateStory[];
