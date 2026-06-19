/* oxlint-disable unicorn/consistent-function-scoping -- Playwright page callbacks must carry their own DOM helpers. */

import { chromium, type Page } from 'playwright';

const defaultDevServerUrl =
	'http://127.0.0.1:6173/?fixture=large-diffshub&workers=on&scenario=scroll';
const targetAddedPath = 'Sources/BridgeViewer/NewPanel.ts';
const targetAddedText = "return 'full added file content';";
const targetMarkdownPath = 'docs/plans/bridge-viewer-browser.md';
const targetMarkdownHeading = 'Browser fixture';

interface DevServerVerificationResult {
	readonly codeViewVisibleText: string;
	readonly selectedHeaderCollapseButtonState: HeaderCollapseButtonState | null;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly workerPoolState: string | null;
}

interface HeaderCollapseButtonState {
	readonly ariaExpanded: string | null;
	readonly ariaLabel: string | null;
	readonly height: number;
	readonly text: string;
	readonly width: number;
}

const devServerUrl = process.env['BRIDGE_VIEWER_DEV_SERVER_URL'] ?? defaultDevServerUrl;
const markdownDevServerUrl = devServerUrlWithScenario(devServerUrl, 'markdown');

const browser = await chromium.launch({ headless: true });

try {
	const result = await verifyScrollScenario();
	const markdownResult = await verifyMarkdownScenario();

	console.log(
		JSON.stringify(
			{
				ok: true,
				devServerUrl,
				markdownDevServerUrl,
				markdownDisplayPath: markdownResult.displayPath,
				selectedDisplayPath: result.selectedDisplayPath,
				workerPoolState: result.workerPoolState,
			},
			null,
			2,
		),
	);
} finally {
	await browser.close();
}

async function verifyScrollScenario(): Promise<DevServerVerificationResult> {
	const page = await makeVerificationPage();
	try {
		await page.goto(devServerUrl, { waitUntil: 'networkidle', timeout: 30_000 });
		await page.waitForTimeout(1_200);
		await searchForAddedFile(page);
		await clickFileTreePath(page, targetAddedPath);
		await page.waitForTimeout(1_500);

		const result = await readVerificationResult(page);
		assertSelectedHeaderCollapseButton(result);
		if (result.selectedDisplayPath !== targetAddedPath) {
			throw new Error(
				`Expected selected display path ${targetAddedPath}, got ${
					result.selectedDisplayPath ?? 'null'
				}`,
			);
		}
		if (result.selectedContentState !== 'ready') {
			throw new Error(
				`Expected selected content state ready, got ${result.selectedContentState ?? 'null'}`,
			);
		}
		if (result.workerPoolState !== 'ready') {
			throw new Error(`Expected worker pool state ready, got ${result.workerPoolState ?? 'null'}`);
		}
		if (!result.codeViewVisibleText.includes(targetAddedText)) {
			throw new Error(
				[
					'Expected added file content to be visible in the CodeView scroll owner.',
					`Missing text: ${targetAddedText}`,
					`Visible text: ${result.codeViewVisibleText.slice(0, 500)}`,
				].join('\n'),
			);
		}
		await assertSelectedHeaderCollapseRoundTrip(page);
		return result;
	} finally {
		await page.close();
	}
}

interface MarkdownScenarioResult {
	readonly displayPath: string | null;
}

async function verifyMarkdownScenario(): Promise<MarkdownScenarioResult> {
	const page = await makeVerificationPage();
	try {
		await page.goto(markdownDevServerUrl, { waitUntil: 'networkidle', timeout: 30_000 });
		await page.waitForFunction(
			(heading: string): boolean =>
				document
					.querySelector('[data-testid="bridge-markdown-preview"]')
					?.textContent?.includes(heading) ?? false,
			targetMarkdownHeading,
			{ timeout: 10_000 },
		);
		const result = await page.evaluate((): MarkdownScenarioResult => {
			return {
				displayPath:
					document
						.querySelector('[data-markdown-preview-source-path]')
						?.getAttribute('data-markdown-preview-source-path') ?? null,
			};
		});
		if (result.displayPath !== targetMarkdownPath) {
			throw new Error(
				`Expected markdown preview source ${targetMarkdownPath}, got ${
					result.displayPath ?? 'null'
				}`,
			);
		}
		return result;
	} finally {
		await page.close();
	}
}

async function makeVerificationPage(): Promise<Page> {
	return await browser.newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
}

function devServerUrlWithScenario(url: string, scenario: string): string {
	const parsedUrl = new URL(url);
	parsedUrl.searchParams.set('scenario', scenario);
	return parsedUrl.toString();
}

function assertSelectedHeaderCollapseButton(result: DevServerVerificationResult): void {
	const collapseButtonState = result.selectedHeaderCollapseButtonState;
	if (collapseButtonState === null) {
		throw new Error(`Expected selected CodeView header collapse button for ${targetAddedPath}`);
	}
	if (collapseButtonState.ariaExpanded !== 'true') {
		throw new Error(
			`Expected selected CodeView header collapse button aria-expanded=true, got ${
				collapseButtonState.ariaExpanded ?? 'null'
			}`,
		);
	}
	if (collapseButtonState.width < 18 || collapseButtonState.width > 32) {
		throw new Error(
			`Expected selected CodeView header collapse button compact width, got ${collapseButtonState.width}`,
		);
	}
	if (collapseButtonState.height < 18 || collapseButtonState.height > 32) {
		throw new Error(
			`Expected selected CodeView header collapse button compact height, got ${collapseButtonState.height}`,
		);
	}
}

async function assertSelectedHeaderCollapseRoundTrip(page: Page): Promise<void> {
	const didCollapse = await clickSelectedHeaderCollapseButton(page);
	if (!didCollapse) {
		throw new Error(
			`Expected clickable selected CodeView header collapse button for ${targetAddedPath}`,
		);
	}
	await page.waitForFunction(
		(path: string): boolean => {
			function findCodeViewHeaderCollapseButton(targetPath: string): HTMLButtonElement | null {
				for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
					const matchingMetadata = Array.from(
						container.querySelectorAll('[data-testid="bridge-code-view-header-metadata"]'),
					).find((element: Element): boolean => element.textContent?.includes(targetPath) ?? false);
					if (matchingMetadata === undefined) {
						continue;
					}
					const button = container.querySelector(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					);
					if (button instanceof HTMLButtonElement) {
						return button;
					}
				}
				return null;
			}
			const button = findCodeViewHeaderCollapseButton(path);
			return button?.getAttribute('aria-expanded') === 'false';
		},
		targetAddedPath,
		{ timeout: 10_000 },
	);
	const collapsedText = (await readVerificationResult(page)).codeViewVisibleText;
	if (collapsedText.includes(targetAddedText)) {
		throw new Error('Expected selected added file content to be hidden after header collapse');
	}

	const didExpand = await clickSelectedHeaderCollapseButton(page);
	if (!didExpand) {
		throw new Error(
			`Expected clickable selected CodeView header expand button for ${targetAddedPath}`,
		);
	}
	await page.waitForFunction(
		(path: string): boolean => {
			function findCodeViewHeaderCollapseButton(targetPath: string): HTMLButtonElement | null {
				for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
					const matchingMetadata = Array.from(
						container.querySelectorAll('[data-testid="bridge-code-view-header-metadata"]'),
					).find((element: Element): boolean => element.textContent?.includes(targetPath) ?? false);
					if (matchingMetadata === undefined) {
						continue;
					}
					const button = container.querySelector(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					);
					if (button instanceof HTMLButtonElement) {
						return button;
					}
				}
				return null;
			}
			const button = findCodeViewHeaderCollapseButton(path);
			return button?.getAttribute('aria-expanded') === 'true';
		},
		targetAddedPath,
		{ timeout: 10_000 },
	);
	await page.waitForFunction(
		(expectedText: string): boolean => {
			const shadowText = Array.from(document.querySelectorAll('diffs-container'))
				.flatMap((container: Element): readonly string[] => {
					const shadowRoot = container.shadowRoot;
					if (shadowRoot === null) {
						return [];
					}
					return Array.from(shadowRoot.querySelectorAll('[data-line], [data-content], pre')).map(
						(element: Element): string => element.textContent ?? '',
					);
				})
				.join(' ');
			return shadowText.includes(expectedText);
		},
		targetAddedText,
		{ timeout: 10_000 },
	);
}

async function clickSelectedHeaderCollapseButton(page: Page): Promise<boolean> {
	return await page.evaluate((path: string): boolean => {
		function findCodeViewHeaderCollapseButton(targetPath: string): HTMLButtonElement | null {
			for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
				const matchingMetadata = Array.from(
					container.querySelectorAll('[data-testid="bridge-code-view-header-metadata"]'),
				).find((element: Element): boolean => element.textContent?.includes(targetPath) ?? false);
				if (matchingMetadata === undefined) {
					continue;
				}
				const button = container.querySelector(
					'[data-testid="bridge-code-view-header-collapse-button"]',
				);
				if (button instanceof HTMLButtonElement) {
					return button;
				}
			}
			return null;
		}
		const button = findCodeViewHeaderCollapseButton(path);
		if (button === null) {
			return false;
		}
		button.click();
		return true;
	}, targetAddedPath);
}

async function searchForAddedFile(page: Page): Promise<void> {
	await page.locator('button[data-testid="bridge-review-search-toggle"]').click();
	await page
		.locator('[data-testid="bridge-review-search-control"] input[role="searchbox"]')
		.fill('NewPanel');
	await page.waitForFunction(
		(path: string): boolean => {
			const row = document
				.querySelector('file-tree-container')
				?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(path)}"]`);
			return row instanceof HTMLElement;
		},
		targetAddedPath,
		{ timeout: 10_000 },
	);
}

async function clickFileTreePath(page: Page, path: string): Promise<void> {
	const didClick = await page.evaluate((targetPath: string): boolean => {
		const row = document
			.querySelector('file-tree-container')
			?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`);
		if (!(row instanceof HTMLElement)) {
			return false;
		}
		row.click();
		return true;
	}, path);
	if (!didClick) {
		throw new Error(`Expected file tree row for ${path}`);
	}
}

async function readVerificationResult(page: Page): Promise<DevServerVerificationResult> {
	return await page.evaluate((): DevServerVerificationResult => {
		function findCodeViewHeaderCollapseButton(path: string): HTMLButtonElement | null {
			for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
				const matchingMetadata = Array.from(
					container.querySelectorAll('[data-testid="bridge-code-view-header-metadata"]'),
				).find((element: Element): boolean => element.textContent?.includes(path) ?? false);
				if (matchingMetadata === undefined) {
					continue;
				}
				const button = container.querySelector(
					'[data-testid="bridge-code-view-header-collapse-button"]',
				);
				if (button instanceof HTMLButtonElement) {
					return button;
				}
			}
			return null;
		}
		const codeScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
		const selectedDisplayPath =
			document
				.querySelector('[data-selected-display-path]')
				?.getAttribute('data-selected-display-path') ?? null;
		const selectedHeaderCollapseButton =
			selectedDisplayPath === null ? null : findCodeViewHeaderCollapseButton(selectedDisplayPath);
		const selectedHeaderCollapseButtonBounds =
			selectedHeaderCollapseButton === null
				? null
				: selectedHeaderCollapseButton.getBoundingClientRect();
		const shadowText = Array.from(document.querySelectorAll('diffs-container'))
			.flatMap((container: Element): readonly string[] => {
				const shadowRoot = container.shadowRoot;
				if (shadowRoot === null) {
					return [];
				}
				return Array.from(shadowRoot.querySelectorAll('[data-line], [data-content], pre')).map(
					(element: Element): string => element.textContent ?? '',
				);
			})
			.join(' ');
		return {
			codeViewVisibleText: [
				codeScrollOwner instanceof HTMLElement ? (codeScrollOwner.textContent ?? '') : '',
				shadowText,
			]
				.join(' ')
				.replace(/\s+/g, ' ')
				.trim(),
			selectedHeaderCollapseButtonState:
				selectedHeaderCollapseButton === null || selectedHeaderCollapseButtonBounds === null
					? null
					: {
							ariaExpanded: selectedHeaderCollapseButton.getAttribute('aria-expanded'),
							ariaLabel: selectedHeaderCollapseButton.getAttribute('aria-label'),
							height: selectedHeaderCollapseButtonBounds.height,
							text: selectedHeaderCollapseButton.textContent ?? '',
							width: selectedHeaderCollapseButtonBounds.width,
						},
			selectedContentState:
				document
					.querySelector('[data-selected-content-state]')
					?.getAttribute('data-selected-content-state') ?? null,
			selectedDisplayPath,
			workerPoolState:
				document
					.querySelector('[data-bridge-pierre-worker-pool-state]')
					?.getAttribute('data-bridge-pierre-worker-pool-state') ?? null,
		};
	});
}
