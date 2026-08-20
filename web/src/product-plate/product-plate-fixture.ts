import type { ImageMetadata } from "astro";

import gitContextPhoneImage from "@/assets/captures/git-pull-request-context-phone.png";
import gitContextImage from "@/assets/captures/git-pull-request-context.png";
import paneDrawerPhoneImage from "@/assets/captures/pane-drawer-phone.png";
import paneDrawerImage from "@/assets/captures/pane-drawer.png";
import parallelWorkPhoneImage from "@/assets/captures/parallel-work-phone.png";
import parallelWorkImage from "@/assets/captures/parallel-work.png";
import quickFindPhoneImage from "@/assets/captures/quick-find-phone.png";
import quickFindImage from "@/assets/captures/quick-find.png";
import reviewPhoneImage from "@/assets/captures/review-phone.png";
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
  readonly phoneImage: ImageMetadata;
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
    image: parallelWorkImage,
    phoneImage: parallelWorkPhoneImage,
    alternativeText: marketingCopy.stories.parallelWork.imageDescription,
  },
  {
    kind: "single-image",
    id: "pane-drawer",
    label: marketingCopy.stories.paneDrawer.label,
    description: marketingCopy.stories.paneDrawer.description,
    phoneDescription: marketingCopy.stories.paneDrawer.phoneDescription,
    image: paneDrawerImage,
    phoneImage: paneDrawerPhoneImage,
    alternativeText: marketingCopy.stories.paneDrawer.imageDescription,
  },
  {
    kind: "single-image",
    id: "quick-find",
    label: marketingCopy.stories.quickFind.label,
    description: marketingCopy.stories.quickFind.description,
    phoneDescription: marketingCopy.stories.quickFind.phoneDescription,
    image: quickFindImage,
    phoneImage: quickFindPhoneImage,
    alternativeText: marketingCopy.stories.quickFind.imageDescription,
  },
  {
    kind: "single-image",
    id: "review",
    label: marketingCopy.stories.review.label,
    description: marketingCopy.stories.review.description,
    phoneDescription: marketingCopy.stories.review.phoneDescription,
    image: reviewImage,
    phoneImage: reviewPhoneImage,
    alternativeText: marketingCopy.stories.review.imageDescription,
  },
  {
    kind: "single-image",
    id: "git-context",
    label: marketingCopy.stories.gitContext.label,
    description: marketingCopy.stories.gitContext.description,
    phoneDescription: marketingCopy.stories.gitContext.phoneDescription,
    image: gitContextImage,
    phoneImage: gitContextPhoneImage,
    alternativeText: marketingCopy.stories.gitContext.imageDescription,
  },
] as const satisfies readonly ProductPlateStory[];
