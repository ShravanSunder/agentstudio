import type { ImageMetadata } from "astro";

export interface HeroLoopMedia {
  /** The silent 16:10 product loop, imported with `?url`. */
  readonly source: string;
  /** First frame of the loop; shown before play, under reduced motion, and on failure. */
  readonly poster: ImageMetadata;
  /** Accessible name for the video, describing what the loop shows. */
  readonly accessibilityLabel: string;
}

/**
 * The hero's real-app loop (K1). Until it is approved the hero shows the
 * parallel-agents still. To ship it, add the MP4 and its poster under
 * `src/assets/media/`, import them here, and return them from this constant;
 * `Hero.astro` then renders `HeroLoopVideo` in place of the still.
 */
export const heroLoopMedia: HeroLoopMedia | undefined = undefined;
