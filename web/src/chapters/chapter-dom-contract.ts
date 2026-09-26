// The DOM attributes shared by the chapter rail, chapter surfaces, playback,
// and scene markup. Every lane reads these constants; none writes the
// attribute names as string literals.

/** `data-rail-anchor="<hero|chapterId>"`: the rail dot aligns vertically to this element. */
export const railAnchorAttribute = "data-rail-anchor";

/** `data-rail-surface-target="<id>"`: wide and laptop branches join this element's left edge. */
export const railSurfaceTargetAttribute = "data-rail-surface-target";

/** `data-rail-target-edge="top|left"`: a surface's preferred wide-layout branch entry. */
export const railTargetEdgeAttribute = "data-rail-target-edge";

/** `data-rail-media-target="<id>"`: phone branches drop into this element's top edge. */
export const railMediaTargetAttribute = "data-rail-media-target";

/** `data-rail-step-pill-target="<chapterId>"`: multi-step branches enter its left center. */
export const railStepPillTargetAttribute = "data-rail-step-pill-target";

/** `data-rail-current`: set by the rail on the current chapter's target so its hairline lights. */
export const railCurrentAttribute = "data-rail-current";

/** `data-scroll-playback-stage`: autoplay progress is measured from this element. */
export const playbackStageAttribute = "data-scroll-playback-stage";

/** `data-scene-root="<sceneId>"`: ScenePlayback mounts the scene module here. */
export const sceneRootAttribute = "data-scene-root";

/** `data-scene-step="<stepId>"`: optional step-scoped elements inside a scene. */
export const sceneStepTargetAttribute = "data-scene-step";

/** `data-scene-proof="<sceneId>"`: the real-capture layer shown after the scene completes. */
export const sceneProofAttribute = "data-scene-proof";

/** `data-scene-proof-state="hidden|shown"`: set by ScenePlayback on the proof layer. */
export const sceneProofStateAttribute = "data-scene-proof-state";

/** `data-scene-proof-transition="fade|instant"`: how the latest proof change should render. */
export const sceneProofTransitionAttribute = "data-scene-proof-transition";
