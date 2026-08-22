import { spawn, spawnSync, type ChildProcess } from "node:child_process";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const previewPort = 20_000 + (process.pid % 10_000);
const previewOrigin = `http://127.0.0.1:${previewPort}`;
let previewProcess: ChildProcess | undefined;

const waitForPreview = async (deadline = Date.now() + 10_000): Promise<void> => {
  try {
    const response = await fetch(previewOrigin);
    if (response.ok) {
      return;
    }
  } catch {
    // The preview server is still starting.
  }

  if (Date.now() >= deadline) {
    throw new Error("Production artifact server did not become ready within 10 seconds");
  }

  await new Promise<void>((resolve) => {
    setTimeout(resolve, 25);
  });
  await waitForPreview(deadline);
};

describe("favicon metadata", () => {
  beforeAll(async (): Promise<void> => {
    const buildResult = spawnSync("pnpm", ["run", "build"], {
      cwd: process.cwd(),
      encoding: "utf8",
    });

    if (buildResult.status !== 0) {
      throw new Error(`Website build failed:\n${buildResult.stdout}\n${buildResult.stderr}`);
    }

    previewProcess = spawn(
      "python3",
      ["-m", "http.server", String(previewPort), "--bind", "127.0.0.1", "--directory", "dist"],
      {
        cwd: process.cwd(),
        stdio: "ignore",
      },
    );
    await waitForPreview();
  }, 30_000);

  afterAll((): void => {
    if (previewProcess?.pid !== undefined) {
      previewProcess.kill("SIGTERM");
    }
  });

  it("advertises a fetchable image favicon from the home page", async (): Promise<void> => {
    const homePageResponse = await fetch(previewOrigin);
    expect(homePageResponse.status).toBe(200);

    const homePageHtml = await homePageResponse.text();
    const faviconHref = homePageHtml.match(
      /<link\b[^>]*\brel=["'](?:shortcut )?icon["'][^>]*\bhref=["']([^"']+)["'][^>]*>/i,
    )?.[1];
    expect(faviconHref).toBeDefined();
    if (faviconHref === undefined) {
      throw new Error("The built home page did not advertise a favicon");
    }

    const faviconResponse = await fetch(new URL(faviconHref, previewOrigin));
    expect(faviconResponse.status).toBe(200);
    expect(faviconResponse.headers.get("content-type")).toMatch(/^image\//);
  });
});
