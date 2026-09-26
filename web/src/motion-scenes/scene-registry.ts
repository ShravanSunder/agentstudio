import type { SceneId, SceneModule } from "./scene-contract";
import { chapterComeBackScene } from "./scenes/chapter-come-back/chapter-come-back-scene";
import { chapterContextWithTaskScene } from "./scenes/chapter-context-with-task/chapter-context-with-task-scene";
import { chapterFindAndFocusScene } from "./scenes/chapter-find-and-focus/chapter-find-and-focus-scene";
import { chapterManyAgentsScene } from "./scenes/chapter-many-agents/chapter-many-agents-scene";
import { chapterReviewScene } from "./scenes/chapter-review/chapter-review-scene";

// Filled by the recreation-kit lane as each scene module lands. An id with no
// registered module resolves to undefined, and hosts keep the settled markup.
const sceneModulesById: ReadonlyMap<SceneId, SceneModule> = new Map<SceneId, SceneModule>([
  [chapterManyAgentsScene.sceneId, chapterManyAgentsScene],
  [chapterContextWithTaskScene.sceneId, chapterContextWithTaskScene],
  [chapterFindAndFocusScene.sceneId, chapterFindAndFocusScene],
  [chapterReviewScene.sceneId, chapterReviewScene],
  [chapterComeBackScene.sceneId, chapterComeBackScene],
]);

export function resolveSceneModule(sceneId: SceneId): SceneModule | undefined {
  return sceneModulesById.get(sceneId);
}
