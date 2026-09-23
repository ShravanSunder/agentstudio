import { playbackStageAttribute } from "../chapters/chapter-dom-contract";
import { createSurfaceScenePlayback } from "./scene-playback";
import { createScrollAutoplayVideoController } from "./scroll-autoplay-video-controller";
import { combineSurfacePlaybacks } from "./surface-playback";

const viewportEdgeInsetRatio = 0.2;
const phoneMediaQuery = "(max-width: 620px)";

let disposeActiveController: (() => void) | undefined;

function clampProgress(progress: number): number {
  return Math.min(1, Math.max(0, progress));
}

function easeProgress(progress: number): number {
  return progress * progress * (3 - 2 * progress);
}

function applySurfaceProgress(surface: HTMLElement, progress: number, shouldLift: boolean): void {
  const phoneLayout = window.matchMedia(phoneMediaQuery).matches;
  const liftDistance = phoneLayout ? 12 : 24;
  surface.style.setProperty("--scroll-material-progress", progress.toFixed(3));
  surface.style.setProperty(
    "--scroll-material-lift",
    `${shouldLift ? (-liftDistance * progress).toFixed(2) : "0"}px`,
  );
  surface.style.setProperty(
    "--scroll-material-border-color",
    `rgb(137 180 250 / ${(0.38 * progress).toFixed(3)})`,
  );
  surface.style.setProperty("--scroll-material-primary-alpha", (0.11 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-cyan-alpha", (0.06 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-ground-alpha", (0.88 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-shadow-alpha", (0.28 * progress).toFixed(3));
  surface.style.setProperty(
    "--scroll-material-secondary-shadow-alpha",
    (0.18 * progress).toFixed(3),
  );
  surface.style.setProperty("--scroll-material-highlight-alpha", (0.1 * progress).toFixed(3));
  surface.style.setProperty("--scroll-material-blur", `${(20 * progress).toFixed(2)}px`);
  surface.style.setProperty("--scroll-material-saturation", `${(100 + 20 * progress).toFixed(2)}%`);
  surface.style.setProperty(
    "--scroll-material-radius",
    `${(16 + (phoneLayout ? 2 : 4) * progress).toFixed(2)}px`,
  );
  surface.dataset["visualState"] =
    progress >= 0.98 ? "floating" : progress <= 0.02 ? "resting" : "transitioning";
}

function readSurfaceLift(surface: HTMLElement): number {
  const currentLift = Number.parseFloat(
    getComputedStyle(surface).getPropertyValue("--scroll-material-lift"),
  );
  return Number.isFinite(currentLift) ? currentLift : 0;
}

/**
 * Eased 0..1 progress of an element through the viewport's 20%/80% bookends.
 * The lift is removed so the surface's own float animation cannot feed back
 * into its progress. An element taller than the space between the bookends
 * never reaches 1, which is why playback can measure a smaller media stage.
 */
function readBookendProgress(element: HTMLElement, surfaceLift: number): number {
  const elementBounds = element.getBoundingClientRect();
  const elementTop = elementBounds.top - surfaceLift;
  const elementBottom = elementTop + elementBounds.height;
  const topBookend = window.innerHeight * viewportEdgeInsetRatio;
  const bottomBookend = window.innerHeight * (1 - viewportEdgeInsetRatio);
  const fullyEnteredTop = bottomBookend - elementBounds.height;
  const rawProgress = clampProgress(
    elementTop >= fullyEnteredTop
      ? (bottomBookend - elementTop) / elementBounds.height
      : elementTop >= topBookend
        ? 1
        : (elementBottom - topBookend) / elementBounds.height,
  );
  return easeProgress(rawProgress);
}

export function initializeScrollMaterialSurfaces(): void {
  disposeActiveController?.();

  const surfaces = Array.from(
    document.querySelectorAll<HTMLElement>("[data-scroll-material-surface]"),
  );
  if (surfaces.length === 0) {
    return;
  }

  const surfaceControllers = surfaces.map((surface) => ({
    materialSurface: surface,
    playbackStage: surface.querySelector<HTMLElement>(`[${playbackStageAttribute}]`),
    surfacePlayback: combineSurfacePlaybacks([
      createScrollAutoplayVideoController(surface),
      createSurfaceScenePlayback(surface),
    ]),
  }));
  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let pendingAnimationFrame: number | undefined;
  let isDisposed = false;

  const synchronizeSurfaces = (): void => {
    for (const { materialSurface, playbackStage, surfacePlayback } of surfaceControllers) {
      if (reducedMotionQuery.matches || document.visibilityState === "hidden") {
        applySurfaceProgress(materialSurface, 1, false);
        surfacePlayback.synchronize(1, false);
        continue;
      }
      const surfaceLift = readSurfaceLift(materialSurface);
      const materialProgress = readBookendProgress(materialSurface, surfaceLift);
      const playbackProgress =
        playbackStage === null ? materialProgress : readBookendProgress(playbackStage, surfaceLift);
      applySurfaceProgress(materialSurface, materialProgress, true);
      surfacePlayback.synchronize(playbackProgress, true);
    }
  };

  const scheduleSurfaceUpdate = (): void => {
    if (pendingAnimationFrame !== undefined) {
      return;
    }
    pendingAnimationFrame = window.requestAnimationFrame((): void => {
      pendingAnimationFrame = undefined;
      synchronizeSurfaces();
    });
  };

  const disposeSurfaceUpdates = (): void => {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    if (pendingAnimationFrame !== undefined) {
      window.cancelAnimationFrame(pendingAnimationFrame);
      pendingAnimationFrame = undefined;
    }
    window.removeEventListener("scroll", scheduleSurfaceUpdate);
    window.removeEventListener("resize", scheduleSurfaceUpdate);
    window.removeEventListener("pagehide", handlePageHide);
    document.removeEventListener("visibilitychange", scheduleSurfaceUpdate);
    reducedMotionQuery.removeEventListener("change", scheduleSurfaceUpdate);
    for (const { surfacePlayback } of surfaceControllers) {
      surfacePlayback.dispose();
    }
    if (disposeActiveController === disposeSurfaceUpdates) {
      disposeActiveController = undefined;
    }
  };

  const handlePageHide = (event: PageTransitionEvent): void => {
    if (!event.persisted) {
      disposeSurfaceUpdates();
    }
  };

  disposeActiveController = disposeSurfaceUpdates;
  synchronizeSurfaces();
  window.addEventListener("scroll", scheduleSurfaceUpdate, { passive: true });
  window.addEventListener("resize", scheduleSurfaceUpdate, { passive: true });
  reducedMotionQuery.addEventListener("change", scheduleSurfaceUpdate);
  document.addEventListener("visibilitychange", scheduleSurfaceUpdate);
  window.addEventListener("pagehide", handlePageHide);
}

if (import.meta.hot) {
  import.meta.hot.dispose((): void => {
    disposeActiveController?.();
  });
}
