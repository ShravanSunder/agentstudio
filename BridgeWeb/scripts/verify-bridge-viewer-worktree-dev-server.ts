import { chromium, type Page } from 'playwright';

import { bridgeReviewPackageSchema } from '../src/foundation/review-package/bridge-review-package-schema.ts';

const defaultWorktreeDevServerUrl = 'http://127.0.0.1:5173/?fixture=worktree&workers=on';
const worktreeDevServerUrl =
	process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] ?? defaultWorktreeDevServerUrl;
const targetPathOverride = process.env['BRIDGE_VIEWER_WORKTREE_TARGET_PATH'] ?? null;

interface WorktreeDevServerVerificationResult {
	readonly packageContentHandleId: string;
	readonly packageForbiddenTextAbsent: boolean;
	readonly selectedCharacterCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly targetPath: string;
	readonly workerPoolState: string | null;
}

const browser = await chromium.launch({ headless: true });

try {
	const result = await verifyWorktreeDevServer();
	console.log(
		JSON.stringify(
			{
				ok: true,
				devServerUrl: worktreeDevServerUrl,
				...result,
			},
			null,
			2,
		),
	);
} finally {
	await browser.close();
}

async function verifyWorktreeDevServer(): Promise<WorktreeDevServerVerificationResult> {
	const reviewPackage = await fetchWorktreeReviewPackage();
	const targetItem =
		Object.values(reviewPackage.itemsById).find((item) =>
			targetPathOverride === null
				? item.changeKind === 'added' &&
					item.headPath === 'BridgeWeb/scripts/app-asset-contract.ts' &&
					item.contentRoles.head !== null &&
					item.contentRoles.head !== undefined
				: item.headPath === targetPathOverride || item.basePath === targetPathOverride,
		) ??
		Object.values(reviewPackage.itemsById).find((item) =>
			targetPathOverride === null
				? item.changeKind === 'added' &&
					item.contentRoles.head !== null &&
					item.contentRoles.head !== undefined
				: item.headPath === targetPathOverride || item.basePath === targetPathOverride,
		) ??
		Object.values(reviewPackage.itemsById).find((item) =>
			targetPathOverride === null
				? item.contentRoles.head !== null && item.contentRoles.head !== undefined
				: item.headPath === targetPathOverride || item.basePath === targetPathOverride,
		);
	if (targetItem === undefined) {
		throw new Error(
			targetPathOverride === null
				? 'Expected at least one worktree item with a head content handle'
				: `Expected worktree item for ${targetPathOverride}`,
		);
	}
	const targetPath = targetItem.headPath ?? targetItem.basePath;
	const headHandle = targetItem.contentRoles.head ?? targetItem.contentRoles.file ?? null;
	if (targetPath === null || targetPath === undefined || headHandle === null) {
		throw new Error('Expected worktree target item with display path and content handle');
	}
	const content = await fetchWorktreeContent(headHandle.handleId);
	const packageText = JSON.stringify(reviewPackage);
	if (content.length === 0) {
		throw new Error(`Expected non-empty content for ${headHandle.handleId}`);
	}
	if (packageText.includes(content.slice(0, Math.min(80, content.length)))) {
		throw new Error('Expected worktree review package to omit file body content');
	}

	const page = await makeVerificationPage();
	try {
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await revealFileTreePath(page, targetPath);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('file-tree-container')
					?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(path)}"]`) instanceof
				HTMLElement,
			targetPath,
			{ timeout: 30_000 },
		);
		await clickFileTreePath(page, targetPath);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-selected-display-path]')
					?.getAttribute('data-selected-display-path') === path,
			targetPath,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-selected-content-state]')
					?.getAttribute('data-selected-content-state') === 'ready',
			{ timeout: 20_000 },
		);
		const result = await page.evaluate(
			(): Omit<
				WorktreeDevServerVerificationResult,
				'packageContentHandleId' | 'packageForbiddenTextAbsent' | 'targetPath'
			> => {
				const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				return {
					selectedCharacterCount: Number(
						panel?.getAttribute('data-selected-content-character-count') ?? '0',
					),
					selectedContentState:
						document
							.querySelector('[data-selected-content-state]')
							?.getAttribute('data-selected-content-state') ?? null,
					selectedDisplayPath:
						document
							.querySelector('[data-selected-display-path]')
							?.getAttribute('data-selected-display-path') ?? null,
					selectedLineCount: Number(panel?.getAttribute('data-selected-content-line-count') ?? '0'),
					workerPoolState:
						document
							.querySelector('[data-bridge-pierre-worker-pool-state]')
							?.getAttribute('data-bridge-pierre-worker-pool-state') ?? null,
				};
			},
		);
		if (result.selectedDisplayPath !== targetPath) {
			throw new Error(`Expected selected display path ${targetPath}`);
		}
		if (result.selectedContentState !== 'ready') {
			throw new Error(`Expected selected content ready for ${targetPath}`);
		}
		if (result.selectedCharacterCount <= 0 || result.selectedLineCount <= 0) {
			throw new Error(`Expected materialized selected content for ${targetPath}`);
		}
		await assertSelectedHeaderCollapseRoundTrip(page, targetPath);
		if (result.workerPoolState !== 'ready') {
			throw new Error(`Expected worker pool ready, got ${result.workerPoolState ?? 'null'}`);
		}
		return {
			...result,
			packageContentHandleId: headHandle.handleId,
			packageForbiddenTextAbsent: true,
			targetPath,
		};
	} finally {
		await page.close();
	}
}

async function fetchWorktreeReviewPackage(): Promise<
	ReturnType<typeof bridgeReviewPackageSchema.parse>
> {
	const packageUrl = new URL('/__bridge-worktree/package', worktreeDevServerUrl);
	const response = await fetch(packageUrl);
	if (!response.ok) {
		throw new Error(`Worktree package request failed: ${response.status}`);
	}
	return bridgeReviewPackageSchema.parse(await response.json());
}

async function fetchWorktreeContent(handleId: string): Promise<string> {
	const contentUrl = new URL(
		`/__bridge-worktree/content/${encodeURIComponent(handleId)}`,
		worktreeDevServerUrl,
	);
	const response = await fetch(contentUrl);
	if (!response.ok) {
		throw new Error(`Worktree content request failed: ${response.status}`);
	}
	return await response.text();
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

async function revealFileTreePath(page: Page, path: string): Promise<void> {
	const basename = path.split('/').at(-1) ?? path;
	await fillBridgeViewerFileTreeSearch(page, basename.replace(/\.[^.]+$/u, ''));
}

async function fillBridgeViewerFileTreeSearch(page: Page, searchText: string): Promise<void> {
	await page.locator('button[data-testid="bridge-review-search-toggle"]').click();
	await page.waitForFunction((): boolean => {
		const searchInput = document
			.querySelector('file-tree-container')
			?.shadowRoot?.querySelector('input[role="searchbox"], input[type="search"], input');
		return searchInput instanceof HTMLInputElement;
	});
	await page.evaluate((value: string): void => {
		const searchInput = document
			.querySelector('file-tree-container')
			?.shadowRoot?.querySelector<HTMLInputElement>(
				'input[role="searchbox"], input[type="search"], input',
			);
		if (searchInput === null || searchInput === undefined) {
			throw new Error('Expected Bridge viewer file tree search input');
		}
		searchInput.value = value;
		searchInput.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
		searchInput.focus();
	}, searchText);
}

async function assertSelectedHeaderCollapseRoundTrip(page: Page, path: string): Promise<void> {
	await waitForSelectedHeaderExpansion(page, path, 'true');
	await clickSelectedHeaderCollapseButton(page, path);
	await waitForSelectedHeaderExpansion(page, path, 'false');
	await assertSelectedHeaderAnchored(page, path, 'collapsed');
	await clickSelectedHeaderCollapseButton(page, path);
	await waitForSelectedHeaderExpansion(page, path, 'true');
	await assertSelectedHeaderAnchored(page, path, 'expanded');
}

async function clickSelectedHeaderCollapseButton(page: Page, path: string): Promise<void> {
	const didClick = await page.evaluate((targetPath: string): boolean => {
		for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
			if (container.shadowRoot?.textContent?.includes(targetPath) !== true) {
				continue;
			}
			const headerButton = container.querySelector(
				'[data-testid="bridge-code-view-header-collapse-button"]',
			);
			if (headerButton instanceof HTMLButtonElement) {
				headerButton.click();
				return true;
			}
			return false;
		}
		return false;
	}, path);
	if (!didClick) {
		throw new Error(`Expected selected CodeView header collapse button for ${path}`);
	}
}

async function waitForSelectedHeaderExpansion(
	page: Page,
	path: string,
	ariaExpanded: 'false' | 'true',
): Promise<void> {
	await page.waitForFunction(
		(props: { readonly path: string; readonly ariaExpanded: 'false' | 'true' }): boolean => {
			for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
				if (container.shadowRoot?.textContent?.includes(props.path) !== true) {
					continue;
				}
				const button = container.querySelector(
					'[data-testid="bridge-code-view-header-collapse-button"]',
				);
				return button?.getAttribute('aria-expanded') === props.ariaExpanded;
			}
			return false;
		},
		{ path, ariaExpanded },
		{ timeout: 10_000 },
	);
}

async function assertSelectedHeaderAnchored(
	page: Page,
	path: string,
	phase: 'collapsed' | 'expanded',
): Promise<void> {
	const topOffset = await page.evaluate((targetPath: string): number | null => {
		const scrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
		const scrollOwnerBounds =
			scrollOwner instanceof HTMLElement ? scrollOwner.getBoundingClientRect() : null;
		if (scrollOwnerBounds === null) {
			return null;
		}
		for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
			if (container.shadowRoot?.textContent?.includes(targetPath) !== true) {
				continue;
			}
			const button = container.querySelector(
				'[data-testid="bridge-code-view-header-collapse-button"]',
			);
			if (!(button instanceof HTMLElement)) {
				return null;
			}
			return button.getBoundingClientRect().top - scrollOwnerBounds.top;
		}
		return null;
	}, path);
	if (topOffset === null || topOffset < -2 || topOffset > 40) {
		throw new Error(
			`Expected worktree selected header to stay anchored after ${phase}, got ${
				topOffset?.toString() ?? 'null'
			}`,
		);
	}
}
