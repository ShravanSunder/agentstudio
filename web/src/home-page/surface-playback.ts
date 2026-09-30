/**
 * The playback slot a glass surface drives. The scroll-material controller owns
 * progress, reduced motion, document visibility, and lifecycle; each medium
 * (video, scene) only decides what to do with that progress.
 */
export interface SurfacePlayback {
  readonly dispose: () => void;
  readonly synchronize: (progress: number, autoplayEnabled: boolean) => void;
  readonly restart?: () => void;
  readonly deactivate?: () => void;
}

export function combineSurfacePlaybacks(playbacks: readonly SurfacePlayback[]): SurfacePlayback {
  return {
    dispose: (): void => {
      for (const playback of playbacks) {
        playback.dispose();
      }
    },
    synchronize: (progress: number, autoplayEnabled: boolean): void => {
      for (const playback of playbacks) {
        playback.synchronize(progress, autoplayEnabled);
      }
    },
    restart: (): void => {
      for (const playback of playbacks) playback.restart?.();
    },
    deactivate: (): void => {
      for (const playback of playbacks) playback.deactivate?.();
    },
  };
}
