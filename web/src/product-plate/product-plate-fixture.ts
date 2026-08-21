import type { ImageMetadata } from "astro";

import commandBarPhoneImage from "@/assets/captures/command-bar-phone.png";
import commandBarImage from "@/assets/captures/command-bar.png";
import gitContextImage from "@/assets/captures/git-pull-request-context.png";
import paneDrawerImage from "@/assets/captures/pane-drawer.png";
import parallelAgentsImage from "@/assets/captures/parallel-agents.png";
import reviewImage from "@/assets/captures/review.png";
import { marketingCopy } from "@/marketing-copy";

import type { ProductPlateStoryId } from "./product-plate-contract";

interface SingleImageStory {
  readonly kind: "single-image";
  readonly id: ProductPlateStoryId;
  readonly label: string;
  readonly description: string;
  readonly phoneDescription: string;
  readonly image: ImageMetadata;
  readonly phoneImage?: ImageMetadata;
  readonly alternativeText: string;
}

export type ProductPlateStory = SingleImageStory;

export const productPlateStories = [
  {
    kind: "single-image",
    id: "parallel-work",
    label: marketingCopy.stories.parallelWork.label,
    description: marketingCopy.stories.parallelWork.description,
    phoneDescription: marketingCopy.stories.parallelWork.phoneDescription,
    image: parallelAgentsImage,
    alternativeText: marketingCopy.stories.parallelWork.imageDescription,
  },
  {
    kind: "single-image",
    id: "pane-drawer",
    label: marketingCopy.stories.paneDrawer.label,
    description: marketingCopy.stories.paneDrawer.description,
    phoneDescription: marketingCopy.stories.paneDrawer.phoneDescription,
    image: paneDrawerImage,
    alternativeText: marketingCopy.stories.paneDrawer.imageDescription,
  },
  {
    kind: "single-image",
    id: "quick-find",
    label: marketingCopy.stories.quickFind.label,
    description: marketingCopy.stories.quickFind.description,
    phoneDescription: marketingCopy.stories.quickFind.phoneDescription,
    image: commandBarImage,
    phoneImage: commandBarPhoneImage,
    alternativeText: marketingCopy.stories.quickFind.imageDescription,
  },
  {
    kind: "single-image",
    id: "review",
    label: marketingCopy.stories.review.label,
    description: marketingCopy.stories.review.description,
    phoneDescription: marketingCopy.stories.review.phoneDescription,
    image: reviewImage,
    alternativeText: marketingCopy.stories.review.imageDescription,
  },
  {
    kind: "single-image",
    id: "git-context",
    label: marketingCopy.stories.gitContext.label,
    description: marketingCopy.stories.gitContext.description,
    phoneDescription: marketingCopy.stories.gitContext.phoneDescription,
    image: gitContextImage,
    alternativeText: marketingCopy.stories.gitContext.imageDescription,
  },
] as const satisfies readonly ProductPlateStory[];
