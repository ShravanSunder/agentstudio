// DOM hooks the kit renders for scene modules. Scenes select elements through
// these names only, so markup and timelines cannot drift apart silently.

/** `data-scene-part="<name>"`: a named element a scene timeline animates. */
export const scenePartAttribute = "data-scene-part";

/** `data-kit-typed`: the span a typing tween reveals character by character. */
export const kitTypedAttribute = "data-kit-typed";

/** `data-kit-presence="collapsed"`: an element hidden in the settled frame. */
export const kitPresenceAttribute = "data-kit-presence";

/** `data-kit-phone="hidden"`: an element the phone focused crop leaves out. */
export const kitPhoneAttribute = "data-kit-phone";

/** `data-line="<index>"`: one terminal line, in document order. */
export const kitLineAttribute = "data-line";

export function scenePartAttributes(
  scenePart: string | undefined,
): Readonly<Record<string, string>> {
  return scenePart === undefined ? {} : { [scenePartAttribute]: scenePart };
}

export function scenePartSelector(scenePart: string): string {
  return `[${scenePartAttribute}="${scenePart}"]`;
}
