import { chromium, type Page } from 'playwright';

const defaultDevServerUrl =
	'http://127.0.0.1:6173/?fixture=large-diffshub&workers=on&scenario=scroll';
const targetAddedPath = 'Sources/BridgeViewer/NewPanel.ts';
const targetAddedText = "return 'full added file content';";

interface DevServerVerificationResult {
	readonly codeViewVisibleText: string;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly workerPoolState: string | null;
}

const devServerUrl = process.env['BRIDGE_VIEWER_DEV_SERVER_URL'] ?? defaultDevServerUrl;

const browser = await chromium.launch({ headless: true });

try {
	const page = await browser.newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
	await page.goto(devServerUrl, { waitUntil: 'networkidle', timeout: 30_000 });
	await page.waitForTimeout(1_200);
	await searchForAddedFile(page);
	await clickFileTreePath(page, targetAddedPath);
	await page.waitForTimeout(1_500);

	const result = await readVerificationResult(page);
	if (result.selectedDisplayPath !== targetAddedPath) {
		throw new Error(
			`Expected selected display path ${targetAddedPath}, got ${result.selectedDisplayPath ?? 'null'}`,
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

	console.log(
		JSON.stringify(
			{
				ok: true,
				devServerUrl,
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
		const codeScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
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
			selectedContentState:
				document
					.querySelector('[data-selected-content-state]')
					?.getAttribute('data-selected-content-state') ?? null,
			selectedDisplayPath:
				document
					.querySelector('[data-selected-display-path]')
					?.getAttribute('data-selected-display-path') ?? null,
			workerPoolState:
				document
					.querySelector('[data-bridge-pierre-worker-pool-state]')
					?.getAttribute('data-bridge-pierre-worker-pool-state') ?? null,
		};
	});
}
