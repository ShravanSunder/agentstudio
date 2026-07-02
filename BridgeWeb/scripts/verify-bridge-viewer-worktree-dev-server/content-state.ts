import type { Page } from 'playwright';

import {
	bridgeWorktreeDevFileContentRouteMatchesHandle,
	bridgeWorktreeDevFileContentRouteUsesOrigin,
} from '../bridge-worktree-dev-reload-diagnostics.ts';
import { worktreeFileScrollExtentCanarySatisfied } from '../verify-bridge-viewer-worktree-review-proof.ts';
import { worktreeDevServerOrigin } from './config.ts';
import { scrollPierreFileTreeUntilPathVisible } from './file-search-filter.ts';
import {
	defaultFileLineHeightPixels,
	type WorktreeFileContentRouteProbe,
	type WorktreeFileControlsStateSnapshot,
	type WorktreeFileScrollExtentCanary,
	type WorktreeFileScrollExtentSnapshot,
	type WorktreeFileSelectedContentRouteProof,
	type WorktreeFileTreeAnchorSnapshot,
	type WorktreeFileVisibleAppProof,
	type WorktreeFileVisibleRect,
	type WorktreeRenderedContentState,
} from './types.ts';
import { countTextLines } from './utils.ts';

export function assertSelectedContentRouteProof(props: {
	readonly expectedContentHandle: string;
	readonly probe: WorktreeFileContentRouteProbe;
}): WorktreeFileSelectedContentRouteProof {
	const hitUrls = props.probe.hitUrls();
	const foreignHitUrls = props.probe.foreignHitUrls();
	const selectedHitUrl = hitUrls.find((url: string): boolean =>
		bridgeWorktreeDevFileContentRouteMatchesHandle({
			expectedContentHandle: props.expectedContentHandle,
			expectedOrigin: worktreeDevServerOrigin,
			url,
		}),
	);
	const selectedResourceUrlContainsHandle = selectedHitUrl !== undefined;
	const selectedResourceUrlUsesDevServerFrontDoor =
		selectedHitUrl !== undefined &&
		bridgeWorktreeDevFileContentRouteUsesOrigin({
			expectedOrigin: worktreeDevServerOrigin,
			url: selectedHitUrl,
		});
	const proof: WorktreeFileSelectedContentRouteProof = {
		expectedContentHandle: props.expectedContentHandle,
		foreignHitCount: props.probe.foreignHitCount(),
		foreignHitUrls,
		hitCount: props.probe.hitCount(),
		hitUrls,
		selectedResourceUrlContainsHandle,
		selectedResourceUrlUsesDevServerFrontDoor,
	};
	if (
		proof.foreignHitCount !== 0 ||
		proof.hitCount <= 0 ||
		!proof.selectedResourceUrlContainsHandle ||
		!proof.selectedResourceUrlUsesDevServerFrontDoor
	) {
		throw new Error(
			`Expected selected Worktree/File content to request dev-server content route: ${JSON.stringify(proof)}`,
		);
	}
	return proof;
}

export async function readWorktreeRenderedContentState(
	page: Page,
): Promise<WorktreeRenderedContentState> {
	return await page.evaluate((): WorktreeRenderedContentState => {
		const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const text =
			typeof window.bridgeWorktreeVerifier === 'undefined'
				? (contentPanel?.textContent ?? '')
				: window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText();
		const selectedDisplayPath = contentPanel?.getAttribute('data-worktree-open-file-path') ?? null;
		const renderedText = text.endsWith('\n') ? text.slice(0, -1) : text;
		const treeTotalSizeSourceRaw =
			treePanel?.getAttribute('data-worktree-tree-total-size-source') ?? null;
		return {
			selectedCharacterCount: text.length,
			selectedContentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
			selectedDisplayPath,
			selectedLineCount:
				typeof window.bridgeWorktreeVerifier === 'undefined'
					? text.length === 0
						? 0
						: renderedText.split('\n').length
					: window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeLineCount(),
			selectedText: text,
			treeTotalSizePixels: Number(treePanel?.getAttribute('data-worktree-tree-total-size') ?? '0'),
			treeTotalSizeSource:
				treeTotalSizeSourceRaw === 'providerFacts' || treeTotalSizeSourceRaw === 'localProjection'
					? treeTotalSizeSourceRaw
					: null,
		};
	});
}

export async function waitForRenderedWorktreeContent(props: {
	readonly content: string;
	readonly label: string;
	readonly page: Page;
	readonly targetPath: string;
}): Promise<WorktreeRenderedContentState> {
	const deadline = Date.now() + 10_000;
	let latestRendered: WorktreeRenderedContentState | null = null;
	while (Date.now() < deadline) {
		latestRendered = await readWorktreeRenderedContentState(props.page);
		try {
			assertRenderedWorktreeContent({
				content: props.content,
				label: props.label,
				rendered: latestRendered,
				targetPath: props.targetPath,
			});
			return latestRendered;
		} catch {
			await props.page.waitForTimeout(100);
		}
	}
	throw new Error(
		`Expected ${props.label} rendered state to settle: ${JSON.stringify(latestRendered)}`,
	);
}

export function assertRenderedWorktreeContent(props: {
	readonly content: string;
	readonly label: string;
	readonly rendered: WorktreeRenderedContentState;
	readonly targetPath: string;
}): void {
	if (props.rendered.selectedDisplayPath !== props.targetPath) {
		throw new Error(`Expected ${props.label} path ${props.targetPath}`);
	}
	if (props.rendered.selectedContentState !== 'ready') {
		throw new Error(`Expected ${props.label} to be ready for ${props.targetPath}`);
	}
	if (!renderedTextIncludesContent(props.rendered.selectedText, props.content)) {
		throw new Error(`Expected ${props.label} content for ${props.targetPath}`);
	}
	const expectedLineCount = countTextLines(props.content);
	if (props.rendered.selectedLineCount < Math.min(expectedLineCount, 2)) {
		throw new Error(
			`Expected ${props.label} visible line structure for ${props.targetPath}, got ${props.rendered.selectedLineCount}`,
		);
	}
}

export function renderedTextIncludesContent(
	renderedText: string,
	expectedContent: string,
): boolean {
	const trimmedExpectedContent = expectedContent.trim();
	if (trimmedExpectedContent.length === 0) {
		return true;
	}
	if (renderedText.includes(trimmedExpectedContent)) {
		return true;
	}
	const normalizedRenderedText = normalizeRenderedTextForProof(renderedText);
	const expectedLines = trimmedExpectedContent
		.split('\n')
		.map(normalizeRenderedTextForProof)
		.filter((line) => line.length > 0 && line.length <= 240);
	const sampleLines = expectedLines.slice(0, Math.min(expectedLines.length, 20));
	const matchingLineCount = sampleLines.filter((line) =>
		normalizedRenderedText.includes(line),
	).length;
	return matchingLineCount >= Math.min(5, sampleLines.length);
}

export function normalizeRenderedTextForProof(text: string): string {
	return text.replace(/\s+/gu, ' ').trim();
}

export async function scrollTreeToFilePath(page: Page, path: string): Promise<void> {
	await scrollPierreFileTreeUntilPathVisible(page, path);
	await page.evaluate((targetPath: string): void => {
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const helpers = window.bridgeWorktreeVerifier;
		const scrollElement = helpers.getPierreFileTreeScrollElement();
		const button = helpers.getPierreFileTreeItem(targetPath);
		if (
			!(button instanceof HTMLElement) ||
			!(treePanel instanceof HTMLElement) ||
			!(scrollElement instanceof HTMLElement)
		) {
			throw new Error(`Expected Worktree/File tree row for ${targetPath}`);
		}
		button.scrollIntoView({ block: 'center' });
		if (scrollElement.scrollTop <= 0) {
			scrollElement.scrollTop = Math.min(
				scrollElement.scrollHeight - scrollElement.clientHeight,
				160,
			);
		}
	}, path);
}

export async function waitForPierreFileTreeAnchorSettled(page: Page, path: string): Promise<void> {
	await page.waitForFunction(
		(targetPath: string): boolean => {
			const helpers = window.bridgeWorktreeVerifier;
			const scrollElement = helpers.getPierreFileTreeScrollElement();
			const anchor = helpers.getPierreFileTreeItem(targetPath);
			if (!(scrollElement instanceof HTMLElement) || !(anchor instanceof HTMLElement)) {
				delete window.bridgeWorktreeVerifierLastTreeAnchorSignature;
				window.bridgeWorktreeVerifierStableTreeAnchorFrames = 0;
				return false;
			}
			const treeRect = scrollElement.getBoundingClientRect();
			const anchorRect = anchor.getBoundingClientRect();
			const visiblePaths = helpers
				.getPierreFileTreeItems()
				.map((candidate) => candidate.dataset['itemPath'] ?? '')
				.join('\u0000');
			const signature = [
				Math.round(scrollElement.scrollTop),
				Math.round(anchorRect.top - treeRect.top),
				visiblePaths,
			].join('|');
			if (window.bridgeWorktreeVerifierLastTreeAnchorSignature === signature) {
				window.bridgeWorktreeVerifierStableTreeAnchorFrames =
					(window.bridgeWorktreeVerifierStableTreeAnchorFrames ?? 0) + 1;
			} else {
				window.bridgeWorktreeVerifierLastTreeAnchorSignature = signature;
				window.bridgeWorktreeVerifierStableTreeAnchorFrames = 1;
			}
			return (window.bridgeWorktreeVerifierStableTreeAnchorFrames ?? 0) >= 2;
		},
		path,
		{ timeout: 10_000 },
	);
}

export async function clickWorktreeFilePath(page: Page, path: string): Promise<void> {
	for (let attempt = 0; attempt < 3; attempt += 1) {
		await dismissOpenBridgeMenus(page);
		await scrollPierreFileTreeUntilPathVisible(page, path);
		await page.evaluate((targetPath: string): void => {
			const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
			const scrollElement = window.bridgeWorktreeVerifier.getPierreFileTreeScrollElement();
			if (button instanceof HTMLElement && scrollElement instanceof HTMLElement) {
				const buttonRect = button.getBoundingClientRect();
				const scrollRect = scrollElement.getBoundingClientRect();
				const isFullyVisible =
					buttonRect.top >= scrollRect.top && buttonRect.bottom <= scrollRect.bottom;
				if (isFullyVisible) {
					return;
				}
				button.scrollIntoView({ block: 'center', inline: 'nearest' });
			}
		}, path);
		await page.waitForTimeout(50);
		const targetBox = await page.evaluate((targetPath: string): WorktreeFileVisibleRect | null => {
			const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
			if (!(button instanceof HTMLElement)) {
				return null;
			}
			const rect = button.getBoundingClientRect();
			return {
				height: rect.height,
				width: rect.width,
			};
		}, path);
		const targetCenter = await page.evaluate(
			(targetPath: string): { readonly x: number; readonly y: number } | null => {
				const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
				if (!(button instanceof HTMLElement)) {
					return null;
				}
				const rect = button.getBoundingClientRect();
				return {
					x: rect.left + rect.width / 2,
					y: rect.top + rect.height / 2,
				};
			},
			path,
		);
		if (
			targetBox === null ||
			targetBox.width <= 0 ||
			targetBox.height <= 0 ||
			targetCenter === null
		) {
			throw new Error(`Expected Worktree/File row for ${path}`);
		}
		const viewportSize = page.viewportSize();
		if (
			viewportSize !== null &&
			(targetCenter.y < 0 ||
				targetCenter.y > viewportSize.height ||
				targetCenter.x < 0 ||
				targetCenter.x > viewportSize.width)
		) {
			throw new Error(`Expected visible Worktree/File row for ${path}`);
		}
		await page.evaluate((targetPath: string): void => {
			const button = window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath);
			if (!(button instanceof HTMLElement) || button.dataset['itemPath'] !== targetPath) {
				throw new Error(`Expected exact Worktree/File row element for ${targetPath}`);
			}
			button.dispatchEvent(
				new MouseEvent('click', {
					bubbles: true,
					cancelable: true,
					composed: true,
					view: window,
				}),
			);
		}, path);
		const selected = await page
			.waitForFunction(
				(targetPath: string): boolean =>
					document
						.querySelector('[data-testid="bridge-file-viewer-shell"]')
						?.getAttribute('data-selected-display-path') === targetPath,
				path,
				{ timeout: 1_000 },
			)
			.then(
				() => true,
				() => false,
			);
		if (selected) {
			return;
		}
	}
	const selectedPath = await page.evaluate(
		(): string | null =>
			document
				.querySelector('[data-testid="bridge-file-viewer-shell"]')
				?.getAttribute('data-selected-display-path') ?? null,
	);
	throw new Error(`Expected Worktree/File click to select ${path}, got ${selectedPath ?? 'none'}`);
}

export async function dismissOpenBridgeMenus(page: Page): Promise<void> {
	if (!(await hasVisibleBridgeMenuPortal(page))) {
		return;
	}
	const controlsStateBeforeDismiss = await readWorktreeFileControlsStateSnapshot(page);
	await page.evaluate((): void => {
		if (document.activeElement instanceof HTMLElement) {
			document.activeElement.blur();
		}
	});
	await page.keyboard.press('Escape');
	await waitForNoVisibleBridgeMenuPortal(page);
	const controlsStateAfterDismiss = await readWorktreeFileControlsStateSnapshot(page);
	if (
		!worktreeFileControlsStateSnapshotsEqual(controlsStateBeforeDismiss, controlsStateAfterDismiss)
	) {
		throw new Error(
			`Expected Worktree/File menu dismissal to preserve controls state, before ${JSON.stringify(
				controlsStateBeforeDismiss,
			)}, after ${JSON.stringify(controlsStateAfterDismiss)}`,
		);
	}
}

export async function waitForNoVisibleBridgeMenuPortal(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean =>
			![...document.querySelectorAll('[data-base-ui-portal], [data-base-ui-portal] *')].some(
				(portalElement) => {
					if (!(portalElement instanceof HTMLElement)) {
						return false;
					}
					const rect = portalElement.getBoundingClientRect();
					const style = getComputedStyle(portalElement);
					return (
						rect.width > 0 &&
						rect.height > 0 &&
						style.visibility !== 'hidden' &&
						style.display !== 'none' &&
						style.pointerEvents !== 'none'
					);
				},
			),
		undefined,
		{ timeout: 2_000 },
	);
}

export async function hasVisibleBridgeMenuPortal(page: Page): Promise<boolean> {
	return await page.evaluate((): boolean =>
		[...document.querySelectorAll('[data-base-ui-portal], [data-base-ui-portal] *')].some(
			(portalElement) => {
				if (!(portalElement instanceof HTMLElement)) {
					return false;
				}
				const rect = portalElement.getBoundingClientRect();
				const style = getComputedStyle(portalElement);
				return (
					rect.width > 0 &&
					rect.height > 0 &&
					style.visibility !== 'hidden' &&
					style.display !== 'none' &&
					style.pointerEvents !== 'none'
				);
			},
		),
	);
}

export async function readWorktreeFileControlsStateSnapshot(
	page: Page,
): Promise<WorktreeFileControlsStateSnapshot> {
	return await page.evaluate(
		(): WorktreeFileControlsStateSnapshot => ({
			filterMenuText:
				document.querySelector('[data-testid="worktree-file-filter-menu"]')?.textContent ?? null,
			filterStatusText:
				document.querySelector('[data-testid="worktree-file-filter-status"]')?.textContent ?? null,
			regexPressed:
				document
					.querySelector('[data-testid="worktree-file-regex-toggle"]')
					?.getAttribute('aria-pressed') ?? null,
			searchValue:
				document.querySelector<HTMLInputElement>('[data-testid="worktree-file-search-input"]')
					?.value ?? null,
		}),
	);
}

export function worktreeFileControlsStateSnapshotsEqual(
	left: WorktreeFileControlsStateSnapshot,
	right: WorktreeFileControlsStateSnapshot,
): boolean {
	return (
		left.filterMenuText === right.filterMenuText &&
		left.filterStatusText === right.filterStatusText &&
		left.regexPressed === right.regexPressed &&
		left.searchValue === right.searchValue
	);
}

export async function scrollContentPaneToNonzeroOffset(page: Page): Promise<void> {
	await page.evaluate((): void => {
		const contentPanel = window.bridgeWorktreeVerifier.getBridgeFileViewerScrollableContent();
		if (!(contentPanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File content pane before content scroll canary');
		}
		const targetScrollTop = Math.min(
			Math.max(contentPanel.scrollHeight - contentPanel.clientHeight, 0),
			480,
		);
		if (targetScrollTop <= 0) {
			throw new Error(
				`Expected Worktree/File content pane to reserve enough height to scroll, got ${contentPanel.scrollHeight}`,
			);
		}
		contentPanel.scrollTop = targetScrollTop;
	});
	await page.waitForFunction(
		(): boolean => {
			const contentPanel = window.bridgeWorktreeVerifier.getBridgeFileViewerScrollableContent();
			return contentPanel instanceof HTMLElement && contentPanel.scrollTop > 0;
		},
		{ timeout: 10_000 },
	);
}

export async function readWorktreeFileTreeAnchorSnapshot(
	page: Page,
	path: string,
): Promise<WorktreeFileTreeAnchorSnapshot> {
	return await page.evaluate((targetPath: string): WorktreeFileTreeAnchorSnapshot => {
		const helpers = window.bridgeWorktreeVerifier;
		const scrollElement = helpers.getPierreFileTreeScrollElement();
		const anchor = helpers.getPierreFileTreeItem(targetPath);
		if (!(scrollElement instanceof HTMLElement) || !(anchor instanceof HTMLElement)) {
			throw new Error(`Expected Worktree/File anchor row for ${targetPath}`);
		}
		const treeRect = scrollElement.getBoundingClientRect();
		const anchorRect = anchor.getBoundingClientRect();
		const allButtons = helpers.getPierreFileTreeItems();
		const visibleButtons = allButtons.filter((candidate): candidate is HTMLElement => {
			const candidateRect = candidate.getBoundingClientRect();
			return candidateRect.bottom >= treeRect.top && candidateRect.top <= treeRect.bottom;
		});
		const visibleIndexes = visibleButtons.map((button) => allButtons.indexOf(button));
		return {
			anchorItemId: targetPath,
			anchorOffset: anchorRect.top - treeRect.top,
			measuredItemIds: visibleButtons.map((button) => button.dataset['itemPath'] ?? ''),
			scrollTop: scrollElement.scrollTop,
			visibleRange: {
				startIndex: Math.min(...visibleIndexes),
				endIndex: Math.max(...visibleIndexes),
			},
		};
	}, path);
}

export async function readWorktreeFileScrollExtentSnapshot(
	page: Page,
): Promise<WorktreeFileScrollExtentSnapshot> {
	return await page.evaluate((): WorktreeFileScrollExtentSnapshot => {
		const treePanel = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
		const helpers = window.bridgeWorktreeVerifier;
		const treeScrollElement = helpers.getPierreFileTreeScrollElement();
		const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const contentScrollElement = helpers.getBridgeFileViewerScrollableContent();
		if (!(treePanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File tree panel for extent canary');
		}
		if (!(treeScrollElement instanceof HTMLElement)) {
			throw new Error('Expected Pierre FileTree scroll element for extent canary');
		}
		if (!(contentPanel instanceof HTMLElement) || !(contentScrollElement instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File content panel for extent canary');
		}
		const contentDeclaredTotalSizeRaw = contentPanel.getAttribute(
			'data-worktree-open-file-total-size',
		);
		const contentDeclaredTotalSize =
			contentDeclaredTotalSizeRaw === null ? null : Number(contentDeclaredTotalSizeRaw);
		const treeDeclaredTotalSizeRaw = treePanel.getAttribute('data-worktree-tree-total-size');
		const treeDeclaredTotalSize =
			treeDeclaredTotalSizeRaw === null ? null : Number(treeDeclaredTotalSizeRaw);
		const treeDeclaredTotalSizeSourceRaw = treePanel.getAttribute(
			'data-worktree-tree-total-size-source',
		);
		const treeDeclaredTotalSizeSource =
			treeDeclaredTotalSizeSourceRaw === 'providerFacts' ||
			treeDeclaredTotalSizeSourceRaw === 'localProjection'
				? treeDeclaredTotalSizeSourceRaw
				: null;
		return {
			contentDeclaredTotalSizePixels:
				contentDeclaredTotalSize === null || Number.isFinite(contentDeclaredTotalSize)
					? contentDeclaredTotalSize
					: null,
			contentScrollClientHeight: contentScrollElement.clientHeight,
			contentScrollHeight: contentScrollElement.scrollHeight,
			contentScrollTop: contentScrollElement.scrollTop,
			treeDeclaredTotalSizePixels:
				treeDeclaredTotalSize === null || Number.isFinite(treeDeclaredTotalSize)
					? treeDeclaredTotalSize
					: null,
			treeDeclaredTotalSizeSource,
			treeScrollClientHeight: treeScrollElement.clientHeight,
			treeScrollHeight: treeScrollElement.scrollHeight,
			treeScrollTop: treeScrollElement.scrollTop,
		};
	});
}

export function makeScrollExtentCanary(props: {
	readonly afterReady: WorktreeFileScrollExtentSnapshot;
	readonly afterSelection: WorktreeFileScrollExtentSnapshot;
	readonly beforeSelection: WorktreeFileScrollExtentSnapshot;
	readonly selectedAnchorPath: string;
	readonly treeAnchorAfterReady: WorktreeFileTreeAnchorSnapshot;
	readonly treeAnchorBeforeSelection: WorktreeFileTreeAnchorSnapshot;
}): WorktreeFileScrollExtentCanary {
	const treeAnchorOffsetDelta =
		props.treeAnchorAfterReady.anchorOffset - props.treeAnchorBeforeSelection.anchorOffset;
	const contentScrollTopDelta = Math.abs(
		props.afterReady.contentScrollTop - props.afterSelection.contentScrollTop,
	);
	return {
		contentDeclaredTotalSizePixelsAfterReady: props.afterReady.contentDeclaredTotalSizePixels,
		contentDeclaredTotalSizePixelsAfterSelection:
			props.afterSelection.contentDeclaredTotalSizePixels,
		contentHeightDeltaPixels:
			props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight,
		contentScrollClientHeightAfterReady: props.afterReady.contentScrollClientHeight,
		contentScrollClientHeightAfterSelection: props.afterSelection.contentScrollClientHeight,
		contentScrollHeightAfterReady: props.afterReady.contentScrollHeight,
		contentScrollHeightAfterSelection: props.afterSelection.contentScrollHeight,
		contentScrollTopAfterReady: props.afterReady.contentScrollTop,
		contentScrollTopAfterSelection: props.afterSelection.contentScrollTop,
		contentScrollTopDeltaPixels: contentScrollTopDelta,
		exactSizeTolerancePass:
			Math.abs(props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight) <=
			1,
		stableAnchorPass:
			Math.abs(treeAnchorOffsetDelta) <= 1 &&
			Math.abs(props.treeAnchorAfterReady.scrollTop - props.treeAnchorBeforeSelection.scrollTop) <=
				1,
		stableAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffset: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIds: props.treeAnchorBeforeSelection.measuredItemIds,
			reconciliationReason: 'exactLineCount',
			scrollHeightAfter: props.afterReady.contentScrollHeight,
			scrollHeightBefore: props.afterSelection.contentScrollHeight,
			scrollTopAfter: props.afterReady.contentScrollTop,
			scrollTopBefore: props.afterSelection.contentScrollTop,
			scrollTopDeltaPixels: contentScrollTopDelta,
			totalContentHeightAfter: props.afterReady.contentDeclaredTotalSizePixels,
			totalContentHeightBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeAfter: props.afterReady.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			visibleRange: {
				endIndex: Math.ceil(
					(props.afterReady.contentScrollTop + props.afterReady.contentScrollClientHeight) /
						defaultFileLineHeightPixels,
				),
				startIndex: Math.floor(props.afterReady.contentScrollTop / defaultFileLineHeightPixels),
			},
		},
		selectedAnchorPath: props.selectedAnchorPath,
		treeAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffsetAfterReady: props.treeAnchorAfterReady.anchorOffset,
			anchorOffsetBeforeSelection: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIdsAfterReady: props.treeAnchorAfterReady.measuredItemIds,
			measuredItemIdsBeforeSelection: props.treeAnchorBeforeSelection.measuredItemIds,
			scrollTopAfterReady: props.treeAnchorAfterReady.scrollTop,
			scrollTopBeforeSelection: props.treeAnchorBeforeSelection.scrollTop,
			visibleRangeAfterReady: props.treeAnchorAfterReady.visibleRange,
			visibleRangeBeforeSelection: props.treeAnchorBeforeSelection.visibleRange,
		},
		treeDeclaredTotalSizePixels: props.afterReady.treeDeclaredTotalSizePixels,
		treeDeclaredTotalSizeSource: props.afterReady.treeDeclaredTotalSizeSource,
		treeHeightDeltaPixels:
			props.afterReady.treeScrollHeight - props.beforeSelection.treeScrollHeight,
		treeScrollClientHeightAfterReady: props.afterReady.treeScrollClientHeight,
		treeScrollHeightAfterReady: props.afterReady.treeScrollHeight,
		treeScrollHeightBeforeSelection: props.beforeSelection.treeScrollHeight,
		treeScrollTopAfterReady: props.afterReady.treeScrollTop,
		treeScrollTopBeforeSelection: props.beforeSelection.treeScrollTop,
	};
}

export function assertWorktreeScrollExtentCanary(canary: WorktreeFileScrollExtentCanary): void {
	if (!worktreeFileScrollExtentCanarySatisfied(canary)) {
		throw new Error(
			`Expected durable Worktree/File scroll extent proof: ${JSON.stringify(canary)}`,
		);
	}
}

export async function readWorktreeFileVisibleAppProof(
	page: Page,
): Promise<WorktreeFileVisibleAppProof> {
	return await page.evaluate((): WorktreeFileVisibleAppProof => {
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Runs inside the Playwright page context.
		const visibleRectForPageElement = (element: HTMLElement): WorktreeFileVisibleRect => {
			const rect = element.getBoundingClientRect();
			return {
				height: rect.height,
				width: rect.width,
			};
		};
		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const treePane = document.querySelector('[data-testid="bridge-file-viewer-sidebar"]');
		const contentPane = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
		const filterCount = document.querySelector('[data-testid="worktree-file-filter-count"]');
		const sourceProvenance = document.querySelector('[data-testid="worktree-file-provenance"]');
		if (!(appRoot instanceof HTMLElement)) {
			throw new Error('Expected visible shared Bridge app root');
		}
		if (!(shell instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer shell');
		}
		if (!(treePane instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer tree pane');
		}
		if (!(contentPane instanceof HTMLElement)) {
			throw new Error('Expected visible Bridge FileViewer content pane');
		}
		if (!(filterCount instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File filter count element');
		}
		if (!(sourceProvenance instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File provenance element');
		}
		const helpers = window.bridgeWorktreeVerifier;
		const sampledRows = helpers.getPierreFileTreeItems().slice(0, 24);
		const sampledRowTops = sampledRows.map((row) => Math.round(row.getBoundingClientRect().top));
		const distinctSampledRowTops = new Set(sampledRowTops);
		const outsideIntentionalUi = document.body.cloneNode(true);
		if (!(outsideIntentionalUi instanceof HTMLElement)) {
			throw new Error('Expected cloneable page body');
		}
		outsideIntentionalUi
			.querySelectorAll(
				'[data-testid="bridge-file-viewer-sidebar"], [data-testid="bridge-file-viewer-code-canvas"]',
			)
			.forEach((node) => {
				node.remove();
			});
		const outsideText = outsideIntentionalUi.textContent ?? '';
		const shellStyle = window.getComputedStyle(shell);
		const contentRect = contentPane.getBoundingClientRect();
		const treeRect = treePane.getBoundingClientRect();
		const isMeaningfullyVisible = (element: HTMLElement): boolean => {
			const rect = element.getBoundingClientRect();
			const style = window.getComputedStyle(element);
			return (
				style.display !== 'none' &&
				style.visibility !== 'hidden' &&
				rect.width > 2 &&
				rect.height > 2 &&
				element.getClientRects().length > 0
			);
		};
		return {
			appRootRect: visibleRectForPageElement(appRoot),
			contentPaneRect: visibleRectForPageElement(contentPane),
			contentVisibleLineCount: helpers.getBridgeFileViewerRenderedCodeLineCount(),
			cssLayoutApplied:
				shellStyle.display === 'flex' &&
				shell.getAttribute('data-sidebar-position') === 'right' &&
				contentRect.left < treeRect.left,
			filterMenuCount: shell.querySelectorAll('[data-testid="worktree-file-filter-menu"]').length,
			filterCountMeaningfullyVisible: isMeaningfullyVisible(filterCount),
			filterCountText: filterCount.textContent ?? '',
			forbiddenTextAbsentOutsideIntentionalUi:
				!outsideText.includes('"frames"') &&
				!outsideText.includes('frameKind') &&
				!outsideText.includes('resourceUrl') &&
				!outsideText.includes('agentstudio://resource/') &&
				!outsideText.includes('BridgeWeb/src/'),
			regexToggleCount: shell.querySelectorAll('[data-testid="worktree-file-regex-toggle"]').length,
			sourceProvenanceMeaningfullyVisible: isMeaningfullyVisible(sourceProvenance),
			sourceProvenanceText: sourceProvenance.textContent ?? '',
			sampledTreeRowCount: sampledRows.length,
			sampledTreeRowsHaveDistinctVerticalPositions:
				sampledRows.length >= 8 && distinctSampledRowTops.size === sampledRows.length,
			searchControlCount: shell.querySelectorAll('[data-testid="worktree-file-search-control"]')
				.length,
			searchInputCount: shell.querySelectorAll('[data-testid="worktree-file-search-input"]').length,
			sharedRailToolbarCount: shell.querySelectorAll(
				'[data-testid="bridge-file-viewer-rail-toolbar"]',
			).length,
			sharedRailToolbarUsesSharedAttr:
				shell
					.querySelector('[data-testid="bridge-file-viewer-rail-toolbar"]')
					?.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
			sourceBaseRef: shell.getAttribute('data-worktree-base-ref'),
			sourceCursor: shell.getAttribute('data-worktree-source-cursor'),
			sourceId: shell.getAttribute('data-worktree-source-id'),
			sourceScenarioName: shell.getAttribute('data-worktree-scenario'),
			sourceState: shell.getAttribute('data-worktree-source-state'),
			treePaneRect: visibleRectForPageElement(treePane),
			worktreeRootToken: shell.getAttribute('data-worktree-root-token'),
		};
	});
}

export function assertWorktreeFileVisibleAppProof(props: {
	readonly expectedSourceBaseRef: string;
	readonly expectedSourceCursor: string;
	readonly expectedSourceId: string;
	readonly expectedSourceScenarioName: string;
	readonly expectedWorktreeRootToken: string;
	readonly proof: WorktreeFileVisibleAppProof;
}): void {
	const proof = props.proof;
	assertVisibleRect('Worktree/File app root', proof.appRootRect);
	assertVisibleRect('Worktree/File tree pane', proof.treePaneRect);
	assertVisibleRect('Worktree/File content pane', proof.contentPaneRect);
	if (!proof.cssLayoutApplied) {
		throw new Error(`Expected Worktree/File packaged CSS layout proof: ${JSON.stringify(proof)}`);
	}
	if (proof.sharedRailToolbarCount !== 1 || !proof.sharedRailToolbarUsesSharedAttr) {
		throw new Error(`Expected Worktree/File shared rail toolbar: ${JSON.stringify(proof)}`);
	}
	if (proof.searchControlCount !== 1) {
		throw new Error(`Expected Worktree/File shared search control: ${JSON.stringify(proof)}`);
	}
	if (proof.searchInputCount > 1) {
		throw new Error(
			`Expected Worktree/File search input to mount at most once: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.regexToggleCount !== 1) {
		throw new Error(`Expected Worktree/File shared regex toggle: ${JSON.stringify(proof)}`);
	}
	if (proof.filterMenuCount !== 1) {
		throw new Error(`Expected Worktree/File shadcn filter menu: ${JSON.stringify(proof)}`);
	}
	if (proof.filterCountMeaningfullyVisible || proof.sourceProvenanceMeaningfullyVisible) {
		throw new Error(
			`Expected Worktree/File rail metadata to stay non-visible: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.sampledTreeRowsHaveDistinctVerticalPositions) {
		throw new Error(
			`Expected Worktree/File tree rows to occupy distinct rows: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.contentVisibleLineCount <= 1) {
		throw new Error(
			`Expected Worktree/File selected content to preserve line structure: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.forbiddenTextAbsentOutsideIntentionalUi) {
		throw new Error(
			`Expected no raw Worktree/File payload text outside intended UI: ${JSON.stringify(proof)}`,
		);
	}
	if (
		proof.sourceBaseRef !== props.expectedSourceBaseRef ||
		proof.sourceCursor !== props.expectedSourceCursor ||
		proof.sourceId !== props.expectedSourceId ||
		!proof.filterCountText.includes('/') ||
		proof.sourceProvenanceText !== props.expectedSourceId ||
		proof.sourceScenarioName !== props.expectedSourceScenarioName ||
		proof.sourceState !== 'live' ||
		proof.worktreeRootToken !== props.expectedWorktreeRootToken
	) {
		throw new Error(
			`Expected page-visible Worktree/File source provenance: ${JSON.stringify(proof)}`,
		);
	}
}

export function assertVisibleRect(label: string, rect: WorktreeFileVisibleRect): void {
	if (rect.width <= 0 || rect.height <= 0) {
		throw new Error(`Expected visible ${label} rect: ${JSON.stringify(rect)}`);
	}
}
