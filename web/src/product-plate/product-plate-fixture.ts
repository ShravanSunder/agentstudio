import type { ImageMetadata } from "astro";

import commandBarPhoneImage from "@/assets/captures/command-bar-phone.png";
import commandBarImage from "@/assets/captures/command-bar.png";
import filesPhoneImage from "@/assets/captures/files-phone.png";
import filesImage from "@/assets/captures/files.png";
import parallelAgentsImage from "@/assets/captures/parallel-agents.png";
import parallelWorkPhoneImage from "@/assets/captures/parallel-work-phone.png";
import reviewPhoneImage from "@/assets/captures/review-phone.png";
import reviewImage from "@/assets/captures/review.png";
import watchFolderPhoneImage from "@/assets/captures/watch-folder-phone.png";
import watchFolderImage from "@/assets/captures/watch-folder.png";
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
    id: "watch-folder",
    label: marketingCopy.stories.watchFolders.label,
    description: marketingCopy.stories.watchFolders.description,
    phoneDescription: marketingCopy.stories.watchFolders.phoneDescription,
    image: watchFolderImage,
    phoneImage: watchFolderPhoneImage,
    alternativeText: marketingCopy.stories.watchFolders.imageDescription,
  },
  {
    kind: "single-image",
    id: "parallel-work",
    label: marketingCopy.stories.parallelWork.label,
    description: marketingCopy.stories.parallelWork.description,
    phoneDescription: marketingCopy.stories.parallelWork.phoneDescription,
    image: parallelAgentsImage,
    phoneImage: parallelWorkPhoneImage,
    alternativeText: marketingCopy.stories.parallelWork.imageDescription,
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
    id: "files",
    label: marketingCopy.stories.files.label,
    description: marketingCopy.stories.files.description,
    phoneDescription: marketingCopy.stories.files.phoneDescription,
    image: filesImage,
    phoneImage: filesPhoneImage,
    alternativeText: marketingCopy.stories.files.imageDescription,
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
] as const satisfies readonly ProductPlateStory[];
