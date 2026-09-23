import {
  sceneProofAttribute,
  sceneProofStateAttribute,
  sceneProofTransitionAttribute,
  sceneRootAttribute,
} from "../chapters/chapter-dom-contract";

/** `fade` crossfades (200ms in CSS); `instant` swaps with no transition. */
export type SceneProofTransition = "fade" | "instant";

/**
 * The stage's real-capture layer ("show, then prove"). It owns only the DOM
 * writes that swap which layer is visible and which one assistive technology
 * reads; ScenePlayback decides when. Exactly one of the recreation and the
 * proof is exposed at a time.
 */
export interface SceneProofLayer {
  render(visible: boolean, transition: SceneProofTransition): void;
}

const absentProofLayer: SceneProofLayer = { render: (): void => undefined };

export function findSceneProofLayer(surface: HTMLElement, sceneRoot: HTMLElement): SceneProofLayer {
  const sceneId = sceneRoot.getAttribute(sceneRootAttribute) ?? "";
  const proof = Array.from(surface.querySelectorAll<HTMLElement>(`[${sceneProofAttribute}]`)).find(
    (candidate) => candidate.getAttribute(sceneProofAttribute) === sceneId,
  );
  if (proof === undefined) {
    return absentProofLayer;
  }

  let visibleNow = proof.getAttribute(sceneProofStateAttribute) === "shown";

  return {
    render: (visible: boolean, transition: SceneProofTransition): void => {
      if (visible === visibleNow) {
        return;
      }
      visibleNow = visible;
      proof.setAttribute(sceneProofTransitionAttribute, transition);
      proof.setAttribute(sceneProofStateAttribute, visible ? "shown" : "hidden");
      if (visible) {
        proof.removeAttribute("aria-hidden");
        sceneRoot.setAttribute("aria-hidden", "true");
      } else {
        proof.setAttribute("aria-hidden", "true");
        sceneRoot.removeAttribute("aria-hidden");
      }
    },
  };
}
