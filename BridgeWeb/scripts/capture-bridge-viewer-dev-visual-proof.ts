import { mkdir, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';

import { chromium, type Page } from 'playwright';
import { z } from 'zod';

const defaultDevServerUrl =
	'http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll';
const targetAddedPath = 'Sources/BridgeViewer/NewPanel.ts';
const targetSearchText = 'NewPanel';

const bridgeViewerVisualProofSchema = z.object({
	artifactDirectory: z.string(),
	devServerUrl: z.string(),
	gitStatusFilterMenu: z.object({
		ariaExpanded: z.string().nullable(),
		checkboxItemCount: z.number().int().nonnegative(),
		hasAllStatusesMenuItem: z.boolean(),
		height: z.number().nonnegative(),
		optionLabels: z.array(z.string()),
		rowHeights: z.array(z.number().nonnegative()),
		width: z.number().nonnegative(),
	}),
	screenshots: z.object({
		gitStatusFilterOpen: z.string(),
		gitStatusFilterPopoverCrop: z.string(),
		largeScrolledView: z.string(),
	}),
	selectedDisplayPath: z.string().nullable(),
	workerPoolState: z.string().nullable(),
});

type BridgeViewerVisualProof = z.infer<typeof bridgeViewerVisualProofSchema>;

const devServerUrl = process.env['BRIDGE_VIEWER_DEV_SERVER_URL'] ?? defaultDevServerUrl;
const repoRoot =
	basename(process.cwd()) === 'BridgeWeb' ? resolve(process.cwd(), '..') : process.cwd();
const artifactDirectory =
	process.env['BRIDGE_VIEWER_VISUAL_PROOF_DIR'] ??
	resolve(
		repoRoot,
		'tmp',
		'bridge-viewer-visual-proof',
		`${new Date().toISOString().replace(/[:.]/gu, '-')}-dev-server`,
	);

await mkdir(artifactDirectory, { recursive: true });

const browser = await chromium.launch({ headless: true });

try {
	const page = await makeProofPage();
	try {
		await page.goto(devServerUrl, { waitUntil: 'networkidle', timeout: 30_000 });
		await page.waitForTimeout(1_200);
		await searchForFile(page);
		await clickFileTreePath(page, targetAddedPath);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-selected-display-path]')
					?.getAttribute('data-selected-display-path') === path,
			targetAddedPath,
			{ timeout: 10_000 },
		);
		await page.waitForTimeout(800);

		const largeScrolledViewPath = resolve(artifactDirectory, 'large-scrolled-view.png');
		await page.screenshot({ fullPage: false, path: largeScrolledViewPath });

		await clearRailSearch(page);
		const gitStatusFilterMenu = await openGitStatusFilterMenu(page);
		await waitForFilterPopoverSettled(page);
		const gitStatusFilterOpenPath = resolve(artifactDirectory, 'git-status-filter-open.png');
		await page.screenshot({ fullPage: false, path: gitStatusFilterOpenPath });
		const gitStatusFilterPopoverCropPath = resolve(
			artifactDirectory,
			'git-status-filter-popover-crop.png',
		);
		await page
			.locator('[data-testid="bridge-review-filter-popover"]')
			.screenshot({ path: gitStatusFilterPopoverCropPath });

		const selectedState = await readSelectedState(page);
		const proof = bridgeViewerVisualProofSchema.parse({
			artifactDirectory,
			devServerUrl,
			gitStatusFilterMenu,
			screenshots: {
				gitStatusFilterOpen: gitStatusFilterOpenPath,
				gitStatusFilterPopoverCrop: gitStatusFilterPopoverCropPath,
				largeScrolledView: largeScrolledViewPath,
			},
			selectedDisplayPath: selectedState.selectedDisplayPath,
			workerPoolState: selectedState.workerPoolState,
		});
		await writeFile(
			resolve(artifactDirectory, 'bridge-viewer-dev-visual-proof.json'),
			`${JSON.stringify(proof, null, 2)}\n`,
			'utf8',
		);
		console.log(JSON.stringify({ ok: true, ...proof }, null, 2));
	} finally {
		await page.close();
	}
} finally {
	await browser.close();
}

async function makeProofPage(): Promise<Page> {
	return await browser.newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
}

async function searchForFile(page: Page): Promise<void> {
	await page.locator('button[data-testid="bridge-review-search-toggle"]').click();
	await page
		.locator('[data-testid="bridge-review-search-control"] input[role="searchbox"]')
		.fill(targetSearchText);
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

async function clearRailSearch(page: Page): Promise<void> {
	const searchInput = page.locator(
		'[data-testid="bridge-review-search-control"] input[role="searchbox"]',
	);
	await searchInput.fill('');
	await page.keyboard.press('Escape');
	await page.locator('[data-testid="bridge-review-git-status-menu-control"]').focus();
	await page.waitForFunction(
		(): boolean => {
			const input = document.querySelector('[data-testid="bridge-review-search-input"]');
			if (!(input instanceof HTMLElement)) {
				return true;
			}
			const computedStyle = window.getComputedStyle(input);
			return computedStyle.opacity === '0' || computedStyle.pointerEvents === 'none';
		},
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

async function openGitStatusFilterMenu(
	page: Page,
): Promise<BridgeViewerVisualProof['gitStatusFilterMenu']> {
	await page.locator('[data-testid="bridge-review-git-status-menu-control"]').click();
	await page.waitForSelector('[data-testid="bridge-review-filter-popover"]', {
		state: 'visible',
		timeout: 10_000,
	});
	return await page.evaluate((): BridgeViewerVisualProof['gitStatusFilterMenu'] => {
		const trigger = document.querySelector('[data-testid="bridge-review-git-status-menu-control"]');
		const popover = document.querySelector('[data-testid="bridge-review-filter-popover"]');
		const bounds = popover instanceof HTMLElement ? popover.getBoundingClientRect() : null;
		const checkboxItems = Array.from(document.querySelectorAll('[role="menuitemcheckbox"]'));
		const optionLabels = checkboxItems.map((item: Element): string =>
			(item.textContent ?? '').replace(/\s+/g, ' ').trim(),
		);
		return {
			ariaExpanded: trigger?.getAttribute('aria-expanded') ?? null,
			checkboxItemCount: checkboxItems.length,
			hasAllStatusesMenuItem: optionLabels.some((label: string): boolean =>
				label.includes('All statuses'),
			),
			height: bounds?.height ?? 0,
			optionLabels,
			rowHeights: checkboxItems.map((item: Element): number =>
				item instanceof HTMLElement ? item.getBoundingClientRect().height : 0,
			),
			width: bounds?.width ?? 0,
		};
	});
}

async function waitForFilterPopoverSettled(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const popover = document.querySelector('[data-testid="bridge-review-filter-popover"]');
			if (!(popover instanceof HTMLElement)) {
				return false;
			}
			const computedStyle = window.getComputedStyle(popover);
			return computedStyle.opacity === '1' && computedStyle.transform === 'none';
		},
		{ timeout: 10_000 },
	);
}

async function readSelectedState(page: Page): Promise<{
	readonly selectedDisplayPath: string | null;
	readonly workerPoolState: string | null;
}> {
	return await page.evaluate(
		(): {
			readonly selectedDisplayPath: string | null;
			readonly workerPoolState: string | null;
		} => ({
			selectedDisplayPath:
				document
					.querySelector('[data-selected-display-path]')
					?.getAttribute('data-selected-display-path') ?? null,
			workerPoolState:
				document
					.querySelector('[data-bridge-pierre-worker-pool-state]')
					?.getAttribute('data-bridge-pierre-worker-pool-state') ?? null,
		}),
	);
}
