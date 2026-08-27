import { spawn } from "node:child_process";
import { access, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import sharp from "sharp";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, "..");
const templatePath = resolve(scriptDirectory, "social-card-template.html");
const sourceLogoPath = resolve(projectDirectory, "src/assets/brand/app-logo-transparent.svg");
const outputPath = resolve(projectDirectory, "public/agent-studio-social-card.png");
const screenshotWidth = 1_200;
const screenshotHeight = 630;

const chromeCandidates = [
  process.env["CHROME_BIN"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
].filter((candidate): candidate is string => candidate !== undefined);

async function resolveChromeExecutable(): Promise<string> {
  const resolvedCandidates = await Promise.all(
    chromeCandidates.map(async (candidate): Promise<string | null> => {
      try {
        await access(candidate);
        return candidate;
      } catch {
        return null;
      }
    }),
  );
  const chromeExecutable = resolvedCandidates.find(
    (candidate): candidate is string => candidate !== null,
  );

  if (chromeExecutable !== undefined) {
    return chromeExecutable;
  }

  throw new Error(
    "Generating the social card requires Chrome or Brave. Set CHROME_BIN to a Chromium executable.",
  );
}

async function waitForScreenshot(props: {
  readonly browserProcess: ReturnType<typeof spawn>;
  readonly screenshotPath: string;
}): Promise<void> {
  await new Promise<void>((resolveScreenshot, rejectScreenshot) => {
    let settled = false;

    const finish = (error?: Error): void => {
      if (settled) {
        return;
      }

      settled = true;
      clearInterval(screenshotInterval);
      clearTimeout(screenshotTimeout);

      if (error === undefined) {
        resolveScreenshot();
      } else {
        rejectScreenshot(error);
      }
    };

    const inspectScreenshot = (): void => {
      void stat(props.screenshotPath)
        .then((screenshotStats): void => {
          if (screenshotStats.size > 0) {
            finish();
          }
        })
        .catch((): void => {
          // Chrome has not finished writing the screenshot yet.
        });
    };

    const screenshotInterval = setInterval(inspectScreenshot, 50);
    const screenshotTimeout = setTimeout(
      (): void => finish(new Error("Chrome did not render the social card within 30 seconds.")),
      30_000,
    );

    props.browserProcess.once("error", (error): void => finish(error));
    inspectScreenshot();
  });
}

async function stopBrowserProcess(browserProcess: ReturnType<typeof spawn>): Promise<void> {
  if (browserProcess.exitCode !== null || browserProcess.signalCode !== null) {
    return;
  }

  await new Promise<void>((resolveExit) => {
    let settled = false;

    const finish = (): void => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(forcedExitTimeout);
      browserProcess.off("exit", finish);
      resolveExit();
    };

    const forcedExitTimeout = setTimeout((): void => {
      browserProcess.kill("SIGKILL");
      finish();
    }, 5_000);

    browserProcess.once("exit", finish);

    if (browserProcess.exitCode !== null || browserProcess.signalCode !== null) {
      finish();
      return;
    }

    browserProcess.kill("SIGTERM");
  });
}

const temporaryDirectory = await mkdtemp(resolve(tmpdir(), "agent-studio-social-card-"));

try {
  const [template, sourceLogo] = await Promise.all([
    readFile(templatePath, "utf8"),
    readFile(sourceLogoPath),
  ]);
  const renderedTemplate = template.replace(
    "__APP_LOGO_DATA_URI__",
    `data:image/svg+xml;base64,${sourceLogo.toString("base64")}`,
  );
  const temporaryTemplatePath = resolve(temporaryDirectory, "social-card.html");
  const rawScreenshotPath = resolve(temporaryDirectory, "social-card-browser.png");
  const chromeProfileDirectory = resolve(temporaryDirectory, "chrome-profile");
  await writeFile(temporaryTemplatePath, renderedTemplate, "utf8");

  const chromeExecutable = await resolveChromeExecutable();
  const browserProcess = spawn(
    chromeExecutable,
    [
      "--headless=new",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-gpu",
      "--force-device-scale-factor=1",
      "--hide-scrollbars",
      "--no-first-run",
      `--screenshot=${rawScreenshotPath}`,
      `--user-data-dir=${chromeProfileDirectory}`,
      `--window-size=${screenshotWidth},${screenshotHeight}`,
      pathToFileURL(temporaryTemplatePath).href,
    ],
    { stdio: "ignore" },
  );

  try {
    await waitForScreenshot({ browserProcess, screenshotPath: rawScreenshotPath });
  } finally {
    await stopBrowserProcess(browserProcess);
  }

  const rawMetadata = await sharp(rawScreenshotPath).metadata();
  if (rawMetadata.width !== screenshotWidth || rawMetadata.height !== screenshotHeight) {
    throw new Error(
      `Chrome rendered ${rawMetadata.width ?? "unknown"}x${rawMetadata.height ?? "unknown"}; expected ${screenshotWidth}x${screenshotHeight}.`,
    );
  }

  await sharp(rawScreenshotPath)
    .withMetadata({ icc: "srgb" })
    .png({ compressionLevel: 9 })
    .toFile(outputPath);
} finally {
  await rm(temporaryDirectory, { force: true, recursive: true });
}

console.log(`generated: ${outputPath}`);
