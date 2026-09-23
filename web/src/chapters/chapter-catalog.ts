import type { ImageMetadata } from "astro";

// Relative imports (not the "@/" alias) keep this catalog loadable by the
// Vitest unit project, which has no alias configuration.
import commandBarImage from "../assets/captures/command-bar.png";
import parallelAgentsImage from "../assets/captures/parallel-agents.png";
import reviewPhoneImage from "../assets/captures/review-phone.png";
import reviewImage from "../assets/captures/review.png";
import taskDrawerToolsImage from "../assets/captures/task-drawer-tools.png";
import sessionRestorePoster from "../assets/media/session-restore-poster.jpg";
import sessionRestoreVideoUrl from "../assets/media/session-restore.mp4?url";
import { marketingCopy } from "../marketing-copy";
import type { SceneId } from "../motion-scenes/scene-contract";
import type { ChapterId, ChapterStepId } from "./chapter-ids";

export {
  chapterIds,
  chapterStepIds,
  isChapterStepId,
  type ChapterId,
  type ChapterStepId,
} from "./chapter-ids";

export type ChapterStage =
  | {
      readonly kind: "scene";
      readonly sceneId: SceneId;
      readonly proofImage: ImageMetadata;
      readonly proofAlt: string;
    }
  | {
      readonly kind: "still";
      readonly image: ImageMetadata;
      readonly phoneImage: ImageMetadata;
      readonly alt: string;
    }
  | {
      readonly kind: "video";
      readonly source: string;
      readonly poster: ImageMetadata;
      readonly label: string;
    };

export interface ChapterStep {
  readonly id: ChapterStepId;
  readonly label: string;
  readonly description: string;
  readonly phoneDescription: string;
}

export interface ChapterTitle {
  readonly beforeAccent: string;
  readonly accent: string;
  readonly afterAccent: string;
}

export interface Chapter {
  readonly id: ChapterId;
  readonly eyebrow: string;
  readonly title: ChapterTitle;
  readonly steps: readonly ChapterStep[];
  readonly stage: ChapterStage;
}

type FeatureDetailItem = (typeof marketingCopy.featureDetails.items)[number];

function readFeatureDetail<TFeatureDetailId extends FeatureDetailItem["id"]>(
  featureDetailId: TFeatureDetailId,
): Extract<FeatureDetailItem, { readonly id: TFeatureDetailId }> {
  const featureDetail = marketingCopy.featureDetails.items.find(
    (candidate): candidate is Extract<FeatureDetailItem, { readonly id: TFeatureDetailId }> =>
      candidate.id === featureDetailId,
  );
  if (featureDetail === undefined) {
    throw new Error(`Missing marketing feature detail "${featureDetailId}".`);
  }
  return featureDetail;
}

const navigationDetail = readFeatureDetail("navigation");
const taskToolsDetail = readFeatureDetail("task-tools");
const arrangementsDetail = readFeatureDetail("arrangements");
const { stories, chapters } = marketingCopy;

// Step copy reuses approved story and feature-detail strings. Feature details
// carry no phone-length variant, so those steps repeat their description.
export const chapterCatalog: readonly Chapter[] = [
  {
    id: "many-agents",
    eyebrow: chapters.manyAgents.eyebrow,
    title: chapters.manyAgents.title,
    steps: [
      {
        id: "parallel-agents",
        label: stories.parallelWork.label,
        description: stories.parallelWork.description,
        phoneDescription: stories.parallelWork.phoneDescription,
      },
      {
        id: "watch-folders",
        label: stories.watchFolders.label,
        description: stories.watchFolders.description,
        phoneDescription: stories.watchFolders.phoneDescription,
      },
      {
        id: "navigation",
        label: `${navigationDetail.title.beforeAccent}${navigationDetail.title.accent}${navigationDetail.title.afterAccent}`,
        description: navigationDetail.summary,
        phoneDescription: navigationDetail.summary,
      },
    ],
    stage: {
      kind: "scene",
      sceneId: "chapter-many-agents",
      proofImage: parallelAgentsImage,
      proofAlt: stories.parallelWork.imageDescription,
    },
  },
  {
    id: "context-with-task",
    eyebrow: chapters.contextWithTask.eyebrow,
    title: chapters.contextWithTask.title,
    steps: [
      {
        id: "task-drawers",
        label: stories.paneDrawer.label,
        description: stories.paneDrawer.description,
        phoneDescription: stories.paneDrawer.phoneDescription,
      },
      {
        id: "git-context",
        label: stories.gitContext.label,
        description: stories.gitContext.description,
        phoneDescription: stories.gitContext.phoneDescription,
      },
      {
        id: "files",
        label: stories.files.label,
        description: stories.files.description,
        phoneDescription: stories.files.phoneDescription,
      },
    ],
    stage: {
      kind: "scene",
      sceneId: "chapter-context-with-task",
      proofImage: taskDrawerToolsImage,
      proofAlt: taskToolsDetail.imageDescription,
    },
  },
  {
    id: "find-and-focus",
    eyebrow: chapters.findAndFocus.eyebrow,
    title: chapters.findAndFocus.title,
    steps: [
      {
        id: "quick-find",
        label: stories.quickFind.label,
        description: stories.quickFind.description,
        phoneDescription: stories.quickFind.phoneDescription,
      },
      {
        id: "pane-zoom",
        label: arrangementsDetail.paneZoomLabel,
        description: arrangementsDetail.detail,
        phoneDescription: arrangementsDetail.detail,
      },
    ],
    stage: {
      kind: "scene",
      sceneId: "chapter-find-and-focus",
      proofImage: commandBarImage,
      proofAlt: stories.quickFind.imageDescription,
    },
  },
  {
    id: "review",
    eyebrow: chapters.review.eyebrow,
    title: chapters.review.title,
    steps: [
      {
        id: "review-diff",
        label: stories.review.label,
        description: stories.review.description,
        phoneDescription: stories.review.phoneDescription,
      },
    ],
    stage: {
      kind: "still",
      image: reviewImage,
      phoneImage: reviewPhoneImage,
      alt: stories.review.imageDescription,
    },
  },
  {
    id: "come-back",
    eyebrow: chapters.comeBack.eyebrow,
    title: chapters.comeBack.title,
    steps: [
      {
        id: "persistence",
        label: stories.persistence.label,
        description: stories.persistence.description,
        phoneDescription: stories.persistence.description,
      },
    ],
    stage: {
      kind: "video",
      source: sessionRestoreVideoUrl,
      poster: sessionRestorePoster,
      label: chapters.comeBack.sessionRestoreVideoLabel,
    },
  },
];
