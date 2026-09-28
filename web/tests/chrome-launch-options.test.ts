import { expect, it } from "vitest";

import { selectChromeLaunchOptions } from "../vitest.config";

it("uses CHROME_BIN for a CI browser and keeps the local Chrome channel by default", () => {
  expect(selectChromeLaunchOptions("/opt/google/chrome/chrome")).toEqual({
    executablePath: "/opt/google/chrome/chrome",
  });
  expect(selectChromeLaunchOptions(undefined)).toEqual({ channel: "chrome" });
});
