/* oxlint-disable unicorn/consistent-function-scoping -- Playwright page callbacks must carry their own DOM helpers. */

import { chromium, type Page } from 'playwright';

const defaultDevServerUrl =
	'http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll';
const targetAddedPath = 'Sources/BridgeViewer/NewPanel.ts';
const targetAddedText = "return 'full added file content';";
const targetMarkdownPath = 'docs/plans/bridge-viewer-browser.md';
const targetMarkdownHeading = 'Browser fixture';

interface DevServerVerificationResult {
	readonly codeViewScrollHeight: number;
	readonly codeViewScrollTop: number;
	readonly codeViewVisibleText: string;
	readonly gitStatusFilterMenuState: GitStatusFilterMenuState | null;
	readonly selectedHeaderCollapseButtonState: HeaderCollapseButtonState | null;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly topScopeState: TopScopeState | null;
	readonly workerPoolState: string | null;
}

interface HeaderCollapseButtonState {
	readonly ariaExpanded: string | null;
	readonly ariaLabel: string | null;
	readonly hasBridgeHeaderKindIcon: boolean;
	readonly hasBridgeHeaderStatus: boolean;
	readonly height: number;
	readonly text: string;
	readonly topOffsetFromScrollOwner: number | null;
	readonly width: number;
}

interface GitStatusFilterMenuState {
	readonly ariaExpanded: string | null;
	readonly checkboxItemCount: number;
	readonly hasAllStatusesMenuItem: boolean;
	readonly height: number;
	readonly optionLabels: readonly string[];
	readonly rowHeights: readonly number[];
	readonly width: number;
}

interface TopScopeState {
	readonly activePressedCount: number;
	readonly backgroundColor: string;
	readonly buttonCount: number;
	readonly buttonFontSizes: readonly string[];
	readonly headerBackgroundColor: string;
	readonly height: number;
	readonly isSegmentedControl: boolean;
	readonly projectionButtonTestIds: readonly string[];
	readonly role: string | null;
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
				codeViewScrollHeight: result.codeViewScrollHeight,
				codeViewScrollTop: result.codeViewScrollTop,
				gitStatusFilterMenu: result.gitStatusFilterMenuState,
				selectedHeaderCollapseButton: result.selectedHeaderCollapseButtonState,
				markdownDevServerUrl,
				markdownDisplayPath: markdownResult.displayPath,
				selectedDisplayPath: result.selectedDisplayPath,
				topScope: result.topScopeState,
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
		const initialResult = await readVerificationResult(page);
		assertTopScopeState(initialResult.topScopeState);
		const gitStatusFilterMenuState = await inspectGitStatusFilterMenu(page);
		assertGitStatusFilterMenu(gitStatusFilterMenuState);
		await searchForAddedFile(page);
		await clickFileTreePath(page, targetAddedPath);
		await page.waitForTimeout(1_500);

		const result = {
			...(await readVerificationResult(page)),
			gitStatusFilterMenuState,
		};
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
		assertCodeViewScrolledToSelectedItem({ initialResult, result });
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
	if (
		collapseButtonState.topOffsetFromScrollOwner === null ||
		collapseButtonState.topOffsetFromScrollOwner < -2 ||
		collapseButtonState.topOffsetFromScrollOwner > 40
	) {
		throw new Error(
			`Expected selected CodeView header to align near the top of the scroll owner, got ${
				collapseButtonState.topOffsetFromScrollOwner?.toString() ?? 'null'
			}`,
		);
	}
	if (collapseButtonState.hasBridgeHeaderKindIcon) {
		throw new Error('Expected CodeView header to omit Bridge-owned file-kind icon');
	}
	if (collapseButtonState.hasBridgeHeaderStatus) {
		throw new Error('Expected CodeView header to omit Bridge-owned status badge');
	}
}

function assertCodeViewScrolledToSelectedItem(props: {
	readonly initialResult: DevServerVerificationResult;
	readonly result: DevServerVerificationResult;
}): void {
	if (props.initialResult.selectedDisplayPath === props.result.selectedDisplayPath) {
		throw new Error(
			`Expected dev verifier to switch selected files before scroll proof, stayed on ${
				props.result.selectedDisplayPath ?? 'null'
			}`,
		);
	}
	if (props.result.codeViewScrollHeight <= 0) {
		throw new Error('Expected CodeView scroll owner to report nonzero scroll height');
	}
	if (props.result.codeViewScrollTop <= props.initialResult.codeViewScrollTop) {
		throw new Error(
			[
				'Expected file rail click to scroll the single CodeView list to the selected item.',
				`Initial selected path: ${props.initialResult.selectedDisplayPath ?? 'null'}`,
				`Final selected path: ${props.result.selectedDisplayPath ?? 'null'}`,
				`Initial scrollTop: ${props.initialResult.codeViewScrollTop}`,
				`Final scrollTop: ${props.result.codeViewScrollTop}`,
			].join('\n'),
		);
	}
}

function assertGitStatusFilterMenu(menuState: GitStatusFilterMenuState): void {
	if (menuState.ariaExpanded !== 'true') {
		throw new Error(
			`Expected Git-status filter trigger aria-expanded=true while menu is open, got ${
				menuState.ariaExpanded ?? 'null'
			}`,
		);
	}
	if (menuState.hasAllStatusesMenuItem) {
		throw new Error(
			'Expected Git-status filter menu to use Clear filter instead of All statuses row',
		);
	}
	if (menuState.checkboxItemCount < 4 || menuState.checkboxItemCount > 5) {
		throw new Error(
			`Expected Git-status filter menu to show 4-5 status checkbox rows, got ${menuState.checkboxItemCount}`,
		);
	}
	if (menuState.width < 220 || menuState.width > 272) {
		throw new Error(`Expected compact Git-status filter menu width, got ${menuState.width}`);
	}
	if (menuState.height < 220 || menuState.height > 300) {
		throw new Error(`Expected compact Git-status filter menu height, got ${menuState.height}`);
	}
	for (const rowHeight of menuState.rowHeights) {
		if (rowHeight < 28 || rowHeight > 36) {
			throw new Error(`Expected Git-status filter menu row height near 32px, got ${rowHeight}`);
		}
	}
}

function assertTopScopeState(scopeState: TopScopeState | null): void {
	if (scopeState === null) {
		throw new Error('Expected top projection scope state');
	}
	if (!scopeState.isSegmentedControl) {
		throw new Error('Expected projection scope to declare segmented-control composition');
	}
	if (scopeState.role !== 'group') {
		throw new Error(`Expected projection scope role=group, got ${scopeState.role ?? 'null'}`);
	}
	if (scopeState.buttonCount !== 7) {
		throw new Error(`Expected seven projection scope buttons, got ${scopeState.buttonCount}`);
	}
	if (scopeState.activePressedCount !== 1) {
		throw new Error(
			`Expected exactly one active projection scope button, got ${scopeState.activePressedCount}`,
		);
	}
	if (scopeState.projectionButtonTestIds.length !== 7) {
		throw new Error(
			`Expected seven explicit projection button test ids, got ${scopeState.projectionButtonTestIds.length}`,
		);
	}
	for (const fontSize of scopeState.buttonFontSizes) {
		if (fontSize !== '11px') {
			throw new Error(`Expected compact 11px projection scope button font, got ${fontSize}`);
		}
	}
	if (scopeState.height < 24 || scopeState.height > 34) {
		throw new Error(`Expected compact projection scope height, got ${scopeState.height}`);
	}
	const backgroundIsTransparent =
		scopeState.backgroundColor === 'rgba(0, 0, 0, 0)' ||
		scopeState.backgroundColor === 'transparent';
	if (!backgroundIsTransparent && scopeState.backgroundColor !== scopeState.headerBackgroundColor) {
		throw new Error(
			[
				'Expected projection scope to sit on the same header plane.',
				`Scope background: ${scopeState.backgroundColor}`,
				`Header background: ${scopeState.headerBackgroundColor}`,
			].join('\n'),
		);
	}
	if (scopeState.backgroundColor === 'rgb(0, 0, 0)') {
		throw new Error('Expected projection scope not to render as a detached black strip');
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
					if (container.shadowRoot?.textContent?.includes(targetPath) !== true) {
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
					if (container.shadowRoot?.textContent?.includes(targetPath) !== true) {
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
				if (container.shadowRoot?.textContent?.includes(targetPath) !== true) {
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

async function inspectGitStatusFilterMenu(page: Page): Promise<GitStatusFilterMenuState> {
	await page.locator('[data-testid="bridge-review-git-status-menu-control"]').click();
	await page.waitForSelector('[data-testid="bridge-review-filter-popover"]', {
		state: 'visible',
		timeout: 10_000,
	});
	const menuState = await page.evaluate((): GitStatusFilterMenuState => {
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
	await page.keyboard.press('Escape');
	await page.waitForSelector('[data-testid="bridge-review-filter-popover"]', {
		state: 'detached',
		timeout: 10_000,
	});
	return menuState;
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
		interface SelectedHeaderElements {
			readonly button: HTMLButtonElement;
			readonly container: Element;
		}

		function findCodeViewHeaderElements(path: string): SelectedHeaderElements | null {
			for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
				if (container.shadowRoot?.textContent?.includes(path) !== true) {
					continue;
				}
				const button = container.querySelector(
					'[data-testid="bridge-code-view-header-collapse-button"]',
				);
				if (button instanceof HTMLButtonElement) {
					return { button, container };
				}
			}
			return null;
		}
		const codeScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
		const topHeader = document.querySelector('[data-testid="bridge-review-top-header"]');
		const topScope = document.querySelector('[data-testid="bridge-review-projection-scope"]');
		const topScopeBounds =
			topScope instanceof HTMLElement ? topScope.getBoundingClientRect() : null;
		const topScopeStyle = topScope instanceof HTMLElement ? getComputedStyle(topScope) : null;
		const topHeaderStyle = topHeader instanceof HTMLElement ? getComputedStyle(topHeader) : null;
		const projectionButtons =
			topScope instanceof HTMLElement
				? Array.from(
						topScope.querySelectorAll<HTMLButtonElement>(
							'button[data-testid^="bridge-review-projection-"]',
						),
					)
				: [];
		const codeScrollOwnerBounds =
			codeScrollOwner instanceof HTMLElement ? codeScrollOwner.getBoundingClientRect() : null;
		const selectedDisplayPath =
			document
				.querySelector('[data-selected-display-path]')
				?.getAttribute('data-selected-display-path') ?? null;
		const selectedHeaderElements =
			selectedDisplayPath === null ? null : findCodeViewHeaderElements(selectedDisplayPath);
		const selectedHeaderCollapseButton = selectedHeaderElements?.button ?? null;
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
			codeViewScrollHeight:
				codeScrollOwner instanceof HTMLElement ? codeScrollOwner.scrollHeight : 0,
			codeViewScrollTop: codeScrollOwner instanceof HTMLElement ? codeScrollOwner.scrollTop : 0,
			codeViewVisibleText: [
				codeScrollOwner instanceof HTMLElement ? (codeScrollOwner.textContent ?? '') : '',
				shadowText,
			]
				.join(' ')
				.replace(/\s+/g, ' ')
				.trim(),
			gitStatusFilterMenuState: null,
			selectedHeaderCollapseButtonState:
				selectedHeaderCollapseButton === null || selectedHeaderCollapseButtonBounds === null
					? null
					: {
							ariaExpanded: selectedHeaderCollapseButton.getAttribute('aria-expanded'),
							ariaLabel: selectedHeaderCollapseButton.getAttribute('aria-label'),
							hasBridgeHeaderKindIcon:
								selectedHeaderElements?.container.querySelector(
									'[data-testid="bridge-code-view-header-kind-icon"]',
								) !== null,
							hasBridgeHeaderStatus:
								selectedHeaderElements?.container.querySelector(
									'[data-testid="bridge-code-view-header-status"]',
								) !== null,
							height: selectedHeaderCollapseButtonBounds.height,
							text: selectedHeaderCollapseButton.textContent ?? '',
							topOffsetFromScrollOwner:
								codeScrollOwnerBounds === null
									? null
									: selectedHeaderCollapseButtonBounds.top - codeScrollOwnerBounds.top,
							width: selectedHeaderCollapseButtonBounds.width,
						},
			selectedContentState:
				document
					.querySelector('[data-selected-content-state]')
					?.getAttribute('data-selected-content-state') ?? null,
			selectedDisplayPath,
			topScopeState:
				topScope instanceof HTMLElement && topScopeBounds !== null && topScopeStyle !== null
					? {
							activePressedCount: topScope.querySelectorAll('[aria-pressed="true"]').length,
							backgroundColor: topScopeStyle.backgroundColor,
							buttonCount: topScope.querySelectorAll('button').length,
							buttonFontSizes: projectionButtons.map(
								(button: HTMLButtonElement): string => getComputedStyle(button).fontSize,
							),
							headerBackgroundColor: topHeaderStyle?.backgroundColor ?? '',
							height: topScopeBounds.height,
							isSegmentedControl: topScope.getAttribute('data-bridge-segmented-control') === 'true',
							projectionButtonTestIds: projectionButtons.map(
								(button: HTMLButtonElement): string => button.dataset['testid'] ?? '',
							),
							role: topScope.getAttribute('role'),
						}
					: null,
			workerPoolState:
				document
					.querySelector('[data-bridge-pierre-worker-pool-state]')
					?.getAttribute('data-bridge-pierre-worker-pool-state') ?? null,
		};
	});
}
