import type { SceneId, SceneModule } from "./scene-contract";

// Filled by the recreation-kit lane as each scene module lands. An id with no
// registered module resolves to undefined, and hosts keep the settled markup.
const sceneModulesById: ReadonlyMap<SceneId, SceneModule> = new Map<SceneId, SceneModule>();

export function resolveSceneModule(sceneId: SceneId): SceneModule | undefined {
  return sceneModulesById.get(sceneId);
}
