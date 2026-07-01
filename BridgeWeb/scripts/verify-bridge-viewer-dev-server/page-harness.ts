/* oxlint-disable unicorn/consistent-function-scoping -- Playwright page callbacks must carry their own DOM helpers. */

import type { Page } from 'playwright';

import {
	collectBridgeViewerHydrationDiagnosticsFromRoot,
	parseBridgeViewerHydrationDiagnostics,
	type BridgeViewerHydrationDiagnostics,
} from '../bridge-viewer-hydration-diagnostics.ts';
import type {
	DevServerVerificationResult,
	FilterBehaviorState,
	GitStatusFilterMenuState,
	ScrollMotionProbe,
	TopScopeState,
} from './types.ts';

export interface BridgeViewerDevServerPageHarnessProps {
	readonly targetAddedPath: string;
	readonly targetAddedText: string;
	readonly targetMarkdownPath: string;
}

export interface BridgeViewerDevServerPageHarness {
	readonly assertCodeViewScrolledToSelectedItem: (props: {
		readonly initialResult: DevServerVerificationResult;
		readonly result: DevServerVerificationResult;
	}) => void;
	readonly assertGitStatusFilterMenu: (menuState: GitStatusFilterMenuState) => void;
	readonly assertNoEmptyExpandedHeaders: (
		hydrationDiagnostics: BridgeViewerHydrationDiagnostics,
		phase: string,
	) => void;
	readonly assertSelectedHeaderCollapseButton: (result: DevServerVerificationResult) => void;
	readonly assertSelectedHeaderCollapseRoundTrip: (page: Page) => Promise<void>;
	readonly assertSelectedScrollMotion: (scrollMotion: ScrollMotionProbe | null) => void;
	readonly assertTopScopeStateRemoved: (scopeState: TopScopeState | null) => void;
	readonly clickFileTreePathAndMeasureScrollMotion: (
		page: Page,
		path: string,
	) => Promise<ScrollMotionProbe>;
	readonly fillBridgeViewerFileTreeSearch: (page: Page, searchText: string) => Promise<void>;
	readonly inspectGitStatusFilterMenu: (page: Page) => Promise<GitStatusFilterMenuState>;
	readonly readVerificationResult: (page: Page) => Promise<DevServerVerificationResult>;
	readonly searchForAddedFile: (page: Page) => Promise<void>;
	readonly searchTextForPath: (path: string) => string;
	readonly selectFileAndWaitForContent: (props: {
		readonly page: Page;
		readonly path: string;
		readonly searchText: string;
		readonly text: string;
	}) => Promise<void>;
	readonly verifyFilterBehavior: (
		page: Page,
		initialResult: DevServerVerificationResult,
	) => Promise<FilterBehaviorState>;
	readonly waitForCodeViewText: (page: Page, expectedText: string) => Promise<void>;
	readonly waitForFileTreePath: (page: Page, path: string) => Promise<void>;
	readonly waitForSelectedHeaderAligned: (page: Page) => Promise<void>;
	readonly waitForSelectedPath: (page: Page, path: string) => Promise<void>;
	readonly waitForReviewViewerReady: (page: Page) => Promise<void>;
}

export function createBridgeViewerDevServerPageHarness(
	props: BridgeViewerDevServerPageHarnessProps,
): BridgeViewerDevServerPageHarness {
	const { targetAddedPath, targetAddedText, targetMarkdownPath } = props;
	return {
		assertCodeViewScrolledToSelectedItem,
		assertGitStatusFilterMenu,
		assertNoEmptyExpandedHeaders,
		assertSelectedHeaderCollapseButton,
		assertSelectedHeaderCollapseRoundTrip,
		assertSelectedScrollMotion,
		assertTopScopeStateRemoved,
		clickFileTreePathAndMeasureScrollMotion,
		fillBridgeViewerFileTreeSearch,
		inspectGitStatusFilterMenu,
		readVerificationResult,
		searchForAddedFile,
		searchTextForPath,
		selectFileAndWaitForContent,
		verifyFilterBehavior,
		waitForCodeViewText,
		waitForFileTreePath,
		waitForSelectedHeaderAligned,
		waitForSelectedPath,
		waitForReviewViewerReady,
	};

	async function waitForReviewViewerReady(page: Page): Promise<void> {
		await page.waitForFunction(
			(): boolean =>
				document.querySelector('[data-testid="review-viewer-shell"]') !== null &&
				document.querySelector('file-tree-container')?.shadowRoot !== null &&
				document.querySelector('[data-testid="bridge-code-view-panel"]') !== null,
			{ timeout: 20_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-bridge-pierre-worker-pool-state]')
					?.getAttribute('data-bridge-pierre-worker-pool-state') === 'ready',
			{ timeout: 20_000 },
		);
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

	function assertSelectedScrollMotion(scrollMotion: ScrollMotionProbe | null): void {
		if (scrollMotion === null) {
			throw new Error('Expected selected file click to record CodeView scroll motion');
		}
		const absoluteObservedDelta = Math.abs(scrollMotion.totalObservedDelta);
		if (scrollMotion.scrollHeight <= scrollMotion.scrollClientHeight) {
			throw new Error(
				`Expected CodeView scroll range for motion proof, got height ${scrollMotion.scrollHeight} and client ${scrollMotion.scrollClientHeight}`,
			);
		}
		if (absoluteObservedDelta < 16) {
			throw new Error(
				[
					'Expected file-tree click to move the CodeView scroll owner.',
					`Total delta: ${scrollMotion.totalObservedDelta}`,
					`Samples: ${scrollMotion.samples.join(', ')}`,
				].join('\n'),
			);
		}
		const largeFrameDeltaCount = scrollMotionFrameDeltas(scrollMotion).filter(
			(frameDelta: number): boolean => frameDelta > 2000,
		).length;
		if (largeFrameDeltaCount > 1) {
			throw new Error(
				`Expected bounded CodeView reveal with at most one large frame delta, got ${largeFrameDeltaCount}: ${scrollMotion.samples.join(', ')}`,
			);
		}
		if (largeFrameDeltaCount === 0 && scrollMotion.uniqueScrollTopCount < 4) {
			throw new Error(
				`Expected nearby smooth CodeView motion with multiple scrollTop samples, got ${scrollMotion.uniqueScrollTopCount} unique values`,
			);
		}
		if (scrollMotion.directionChangeCount > 2) {
			throw new Error(
				`Expected mostly monotonic selected-file scroll motion, got ${scrollMotion.directionChangeCount} direction changes`,
			);
		}
	}

	function scrollMotionFrameDeltas(scrollMotion: ScrollMotionProbe): readonly number[] {
		return scrollMotion.samples
			.slice(1)
			.map((sampleValue: number, index: number): number =>
				Math.abs(sampleValue - (scrollMotion.samples[index] ?? sampleValue)),
			);
	}

	function assertGitStatusFilterMenu(menuState: GitStatusFilterMenuState): void {
		if (menuState.ariaExpanded !== 'true') {
			throw new Error(
				`Expected facet filter trigger aria-expanded=true while menu is open, got ${
					menuState.ariaExpanded ?? 'null'
				}`,
			);
		}
		if (menuState.hasAllStatusesMenuItem) {
			throw new Error(
				'Expected facet filter menu to use Clear filters instead of an All statuses row',
			);
		}
		if (menuState.checkboxItemCount < 8 || menuState.checkboxItemCount > 16) {
			throw new Error(
				`Expected facet filter menu to show combined Git-status and file-type checkbox rows, got ${menuState.checkboxItemCount}`,
			);
		}
		if (!menuState.optionLabels.some((label: string): boolean => label.includes('Added'))) {
			throw new Error('Expected facet filter menu to include Git status options');
		}
		if (!menuState.optionLabels.some((label: string): boolean => label.includes('Docs'))) {
			throw new Error('Expected facet filter menu to include file type options');
		}
		if (menuState.width < 360 || menuState.width > 560) {
			throw new Error(`Expected combined facet filter menu width, got ${menuState.width}`);
		}
		if (menuState.height < 300 || menuState.height > 760) {
			throw new Error(`Expected combined facet filter menu height, got ${menuState.height}`);
		}
		for (const rowHeight of menuState.rowHeights) {
			if (rowHeight < 36 || rowHeight > 60) {
				throw new Error(`Expected facet filter menu row height near 40px, got ${rowHeight}`);
			}
		}
	}

	function assertTopScopeStateRemoved(scopeState: TopScopeState | null): void {
		if (scopeState === null) {
			return;
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
		if (
			!backgroundIsTransparent &&
			scopeState.backgroundColor !== scopeState.headerBackgroundColor
		) {
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
		const collapsedResult = await readVerificationResult(page);
		assertNoEmptyExpandedHeaders(collapsedResult.hydrationDiagnostics, 'selected header collapsed');
		assertSelectedHeaderAnchoredAfterToggle({
			phase: 'collapsed',
			result: collapsedResult,
		});
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
		const expandedResult = await readVerificationResult(page);
		assertNoEmptyExpandedHeaders(expandedResult.hydrationDiagnostics, 'selected header expanded');
		assertSelectedHeaderAnchoredAfterToggle({
			phase: 'expanded',
			result: expandedResult,
		});
	}

	function assertNoEmptyExpandedHeaders(
		hydrationDiagnostics: BridgeViewerHydrationDiagnostics,
		phase: string,
	): void {
		if (!hydrationDiagnostics.hasEmptyExpandedHeaders) {
			return;
		}
		throw new Error(
			[
				`Expected no empty expanded CodeView headers during ${phase}.`,
				`Empty expanded header count: ${hydrationDiagnostics.emptyExpandedHeaderCount}`,
				`Rendered item ids: ${hydrationDiagnostics.renderedItemIds.join(', ')}`,
				`Rendered items without ids: ${hydrationDiagnostics.renderedItemsWithoutIdsCount}`,
			].join('\n'),
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

	function assertSelectedHeaderAnchoredAfterToggle(props: {
		readonly phase: 'collapsed' | 'expanded';
		readonly result: DevServerVerificationResult;
	}): void {
		const topOffset =
			props.result.selectedHeaderCollapseButtonState?.topOffsetFromScrollOwner ?? null;
		if (topOffset === null || topOffset < -2 || topOffset > 40) {
			throw new Error(
				`Expected selected CodeView header to stay anchored after ${props.phase}, got ${
					topOffset?.toString() ?? 'null'
				}`,
			);
		}
	}

	async function searchForAddedFile(page: Page): Promise<void> {
		await fillBridgeViewerFileTreeSearch(page, searchTextForPath(targetAddedPath));
		await waitForFileTreePath(page, targetAddedPath);
	}

	async function selectFileAndWaitForContent(props: {
		readonly page: Page;
		readonly path: string;
		readonly searchText: string;
		readonly text: string;
	}): Promise<void> {
		await fillBridgeViewerFileTreeSearch(props.page, props.searchText);
		await waitForFileTreePath(props.page, props.path);
		await clickFileTreePath(props.page, props.path);
		await waitForSelectedPath(props.page, props.path);
		await waitForCodeViewText(props.page, props.text);
	}

	function searchTextForPath(path: string): string {
		const basename = path.split('/').at(-1) ?? path;
		return basename.replace(/\.[^.]+$/u, '');
	}

	async function waitForFileTreePath(page: Page, path: string): Promise<void> {
		await page.waitForFunction(
			(targetPath: string): boolean => {
				const row = document
					.querySelector('file-tree-container')
					?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`);
				return row instanceof HTMLElement;
			},
			path,
			{ timeout: 10_000 },
		);
	}

	async function waitForSelectedPath(page: Page, path: string): Promise<void> {
		await page.waitForFunction(
			(targetPath: string): boolean =>
				document
					.querySelector('[data-selected-display-path]')
					?.getAttribute('data-selected-display-path') === targetPath,
			path,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-selected-content-state]')
					?.getAttribute('data-selected-content-state') === 'ready',
			{ timeout: 20_000 },
		);
	}

	async function waitForCodeViewText(page: Page, expectedText: string): Promise<void> {
		await page.waitForFunction(
			(text: string): boolean => {
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
				const scrollOwnerText =
					document.querySelector('.bridge-code-view-scroll-owner')?.textContent ?? '';
				return `${scrollOwnerText} ${shadowText}`.includes(text);
			},
			expectedText,
			{ timeout: 20_000 },
		);
	}

	async function waitForCodeViewProjectionItemCount(
		page: Page,
		expectedItemCount: number,
	): Promise<void> {
		await page.waitForFunction(
			(itemCount: number): boolean =>
				document
					.querySelector('[data-testid="bridge-code-view-panel"]')
					?.getAttribute('data-code-view-item-count') === itemCount.toString(),
			expectedItemCount,
			{ timeout: 10_000 },
		);
	}

	async function waitForCodeViewProjectionItemCountBelow(
		page: Page,
		upperBoundExclusive: number,
	): Promise<void> {
		await page.waitForFunction(
			(upperBound: number): boolean => {
				const itemCountAttribute = document
					.querySelector('[data-testid="bridge-code-view-panel"]')
					?.getAttribute('data-code-view-item-count');
				if (itemCountAttribute === null || itemCountAttribute === undefined) {
					return false;
				}
				const itemCount = Number.parseInt(itemCountAttribute, 10);
				return Number.isFinite(itemCount) && itemCount > 0 && itemCount < upperBound;
			},
			upperBoundExclusive,
			{ timeout: 10_000 },
		);
	}

	async function waitForSelectedHeaderAligned(page: Page): Promise<void> {
		await page.waitForFunction(
			(): boolean => {
				function findCodeViewHeaderCollapseButton(path: string): HTMLButtonElement | null {
					for (const container of Array.from(document.querySelectorAll('diffs-container'))) {
						if (container.shadowRoot?.textContent?.includes(path) !== true) {
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
				const selectedDisplayPath =
					document
						.querySelector('[data-selected-display-path]')
						?.getAttribute('data-selected-display-path') ?? null;
				const codeScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
				if (selectedDisplayPath === null || !(codeScrollOwner instanceof HTMLElement)) {
					return false;
				}
				const button = findCodeViewHeaderCollapseButton(selectedDisplayPath);
				if (!(button instanceof HTMLButtonElement)) {
					return false;
				}
				const offset =
					button.getBoundingClientRect().top - codeScrollOwner.getBoundingClientRect().top;
				return offset >= -2 && offset <= 40;
			},
			{ timeout: 10_000 },
		);
	}

	async function fillBridgeViewerFileTreeSearch(page: Page, searchText: string): Promise<void> {
		const isSearchOpen = await page.evaluate((): boolean => {
			const searchInput = document
				.querySelector('file-tree-container')
				?.shadowRoot?.querySelector('input[role="searchbox"], input[type="search"], input');
			return searchInput instanceof HTMLInputElement;
		});
		if (!isSearchOpen) {
			await page.locator('button[data-testid="bridge-review-search-toggle"]').click();
		}
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
			searchInput.dispatchEvent(
				new InputEvent('input', { bubbles: true, inputType: 'insertText' }),
			);
			searchInput.focus();
		}, searchText);
	}

	async function inspectGitStatusFilterMenu(page: Page): Promise<GitStatusFilterMenuState> {
		await page.locator('[data-testid="bridge-review-facet-menu-control"]').click();
		await page.waitForSelector('[data-testid="bridge-review-facet-popover"]', {
			state: 'visible',
			timeout: 10_000,
		});
		const menuState = await page.evaluate((): GitStatusFilterMenuState => {
			const trigger = document.querySelector('[data-testid="bridge-review-facet-menu-control"]');
			const popover = document.querySelector('[data-testid="bridge-review-facet-popover"]');
			const bounds = popover instanceof HTMLElement ? popover.getBoundingClientRect() : null;
			const checkboxItems = Array.from(document.querySelectorAll('[role="menuitemcheckbox"]'));
			const optionLabels = checkboxItems.map((item: Element): string => {
				const label = item.querySelector('[data-testid="bridge-review-facet-option-label"]');
				return (label?.textContent ?? item.textContent ?? '').replace(/\s+/g, ' ').trim();
			});
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
		await page.waitForSelector('[data-testid="bridge-review-facet-popover"]', {
			state: 'detached',
			timeout: 10_000,
		});
		return menuState;
	}

	async function verifyFilterBehavior(
		page: Page,
		initialResult: DevServerVerificationResult,
	): Promise<FilterBehaviorState> {
		await clickBridgeReviewFilterMenuOption({
			label: 'Docs',
			page,
			triggerTestId: 'bridge-review-facet-menu-control',
		});
		await waitForSelectedPath(page, targetMarkdownPath);
		await waitForCodeViewProjectionItemCountBelow(
			page,
			initialResult.hydrationDiagnostics.codeViewItemCount,
		);
		const docsResult = await readVerificationResult(page);
		if (docsResult.selectedDisplayPath !== targetMarkdownPath) {
			throw new Error(
				`Expected Docs filter to reconcile selection to ${targetMarkdownPath}, got ${
					docsResult.selectedDisplayPath ?? 'null'
				}`,
			);
		}
		if (docsResult.hydrationDiagnostics.codeViewItemCount <= 0) {
			throw new Error('Expected Docs filter projection to keep at least one visible item');
		}
		if (
			docsResult.hydrationDiagnostics.codeViewItemCount >=
			initialResult.hydrationDiagnostics.codeViewItemCount
		) {
			throw new Error(
				[
					'Expected Docs filter to reduce projected CodeView item count.',
					`Initial count: ${initialResult.hydrationDiagnostics.codeViewItemCount}`,
					`Docs count: ${docsResult.hydrationDiagnostics.codeViewItemCount}`,
				].join('\n'),
			);
		}

		await clickBridgeReviewFilterMenuOption({
			label: 'Clear filters',
			page,
			triggerTestId: 'bridge-review-facet-menu-control',
		});
		await waitForCodeViewProjectionItemCount(
			page,
			initialResult.hydrationDiagnostics.codeViewItemCount,
		);

		return {
			docsProjectionItemCount: docsResult.hydrationDiagnostics.codeViewItemCount,
			initialProjectionItemCount: initialResult.hydrationDiagnostics.codeViewItemCount,
			selectedPathAfterDocsFilter: docsResult.selectedDisplayPath,
		};
	}

	async function clickBridgeReviewFilterMenuOption(props: {
		readonly label: string;
		readonly page: Page;
		readonly triggerTestId: string;
	}): Promise<void> {
		await props.page.locator(`[data-testid="${props.triggerTestId}"]`).click();
		await props.page.waitForSelector('[data-testid="bridge-review-facet-popover"]', {
			state: 'visible',
			timeout: 10_000,
		});
		const didClick = await props.page.evaluate((label: string): boolean => {
			const candidateItems = Array.from(
				document.querySelectorAll('[role="menuitemcheckbox"], [role="menuitem"]'),
			);
			const option = candidateItems.find((element: Element): boolean =>
				(element.textContent ?? '').replace(/\s+/g, ' ').trim().includes(label),
			);
			if (!(option instanceof HTMLElement)) {
				return false;
			}
			option.click();
			return true;
		}, props.label);
		if (!didClick) {
			throw new Error(`Expected Bridge review filter option ${props.label}`);
		}
		await props.page.keyboard.press('Escape');
		await props.page.waitForSelector('[data-testid="bridge-review-facet-popover"]', {
			state: 'detached',
			timeout: 10_000,
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

	async function clickFileTreePathAndMeasureScrollMotion(
		page: Page,
		path: string,
	): Promise<ScrollMotionProbe> {
		return await page.evaluate(async (targetPath: string): Promise<ScrollMotionProbe> => {
			const scrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
			const row = document
				.querySelector('file-tree-container')
				?.shadowRoot?.querySelector(`[data-item-path="${CSS.escape(targetPath)}"]`);
			if (!(scrollOwner instanceof HTMLElement)) {
				throw new Error('Expected CodeView scroll owner before measuring selection motion');
			}
			if (!(row instanceof HTMLElement)) {
				throw new Error(`Expected file tree row for ${targetPath}`);
			}

			const samples: number[] = [];
			const sample = (): void => {
				samples.push(scrollOwner.scrollTop);
			};
			sample();
			row.click();
			for (let frameIndex = 0; frameIndex < 30; frameIndex += 1) {
				// oxlint-disable-next-line no-await-in-loop -- Smooth-scroll proof must sample sequential animation frames.
				await new Promise<void>((resolve): void => {
					requestAnimationFrame((): void => {
						resolve();
					});
				});
				sample();
			}

			const deltas = samples
				.slice(1)
				.map(
					(sampleValue: number, index: number): number =>
						sampleValue - (samples[index] ?? sampleValue),
				);
			let previousDirection = 0;
			let directionChangeCount = 0;
			for (const delta of deltas) {
				const direction = Math.sign(delta);
				if (direction === 0) {
					continue;
				}
				if (previousDirection !== 0 && direction !== previousDirection) {
					directionChangeCount += 1;
				}
				previousDirection = direction;
			}

			const initialScrollTop = samples[0] ?? 0;
			const finalSampleScrollTop = samples.at(-1) ?? initialScrollTop;
			return {
				directionChangeCount,
				finalSampleScrollTop,
				initialScrollTop,
				maximumSingleFrameDelta: Math.max(
					0,
					...deltas.map((delta: number): number => Math.abs(delta)),
				),
				sampleCount: samples.length,
				samples,
				scrollClientHeight: scrollOwner.clientHeight,
				scrollHeight: scrollOwner.scrollHeight,
				totalObservedDelta: finalSampleScrollTop - initialScrollTop,
				uniqueScrollTopCount: new Set(samples).size,
			};
		}, path);
	}

	async function readVerificationResult(page: Page): Promise<DevServerVerificationResult> {
		const hydrationDiagnostics = parseBridgeViewerHydrationDiagnostics(
			await page.evaluate(collectBridgeViewerHydrationDiagnosticsFromRoot, undefined),
		);
		const result = await page.evaluate(
			(): Omit<DevServerVerificationResult, 'hydrationDiagnostics'> => {
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
				const topHeaderStyle =
					topHeader instanceof HTMLElement ? getComputedStyle(topHeader) : null;
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
					filterBehaviorState: null,
					gitStatusFilterMenuState: null,
					markdownSelectionScrollMotion: null,
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
					selectedScrollMotion: null,
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
									isSegmentedControl:
										topScope.getAttribute('data-bridge-segmented-control') === 'true',
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
			},
		);
		return {
			...result,
			hydrationDiagnostics,
		};
	}
}
