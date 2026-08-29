import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const renderedHomepagePath = fileURLToPath(new URL("../dist/index.html", import.meta.url));
const renderedHomepage = await readFile(renderedHomepagePath, "utf8");
const sessionVideoTags = renderedHomepage.match(
  /<video\b[^>]*\bdata-session-restore-video(?:=(?:"[^"]*"|'[^']*'|[^\s>]+))?[^>]*>/gu,
);

if (sessionVideoTags?.length !== 1) {
  throw new Error(
    `Expected one rendered session-restore video, found ${sessionVideoTags?.length ?? 0}.`,
  );
}

const [sessionVideoTag] = sessionVideoTags;
const requiredAttributes = [
  "controls",
  "playsinline",
  'preload="metadata"',
  'aria-label="Agent Studio persistent session restore demonstration"',
  "data-scroll-autoplay-video",
  'data-scroll-autoplay-start-progress="0.95"',
  'data-scroll-autoplay-stop-progress="0.9"',
  'data-scroll-autoplay-replay-delay-ms="3000"',
] as const;

for (const requiredAttribute of requiredAttributes) {
  if (!sessionVideoTag.includes(requiredAttribute)) {
    throw new Error(`Rendered session-restore video is missing ${requiredAttribute}.`);
  }
}

if (/\sautoplay(?:\s|=|>)/u.test(sessionVideoTag)) {
  throw new Error("Rendered session-restore video must not use native autoplay.");
}

console.log("Verified the rendered session-restore player contract.");
