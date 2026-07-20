import type { Page } from 'playwright';

import {
	parseBridgeWorktreeDevReloadIntegerList,
	parseBridgeWorktreeDevReloadIntegerToken,
	parseBridgeWorktreeDevReloadStringList,
} from '../bridge-worktree-dev-reload-diagnostics.ts';
import {
	selectVisibleReviewCollapseControlProof,
	type ReviewCollapseControlCandidate,
	type ReviewCollapseControlProof,
	type ReviewRenderedSelectionExpectation,
	type ReviewRenderedSelectionSnapshot,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import type { WorktreeDevReloadProof } from './types.ts';

export async function reviewClickFailureDiagnosticMessage(props: {
	readonly page: Page;
	readonly targetPath: string;
}): Promise<string> {
	const diagnostic = await props.page.evaluate((targetPath: string) => {
		const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
		const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		const treeHost = document.querySelector(
			'[data-testid="bridge-review-trees-panel"] file-tree-container',
		);
		const treeRoot = treeHost?.shadowRoot ?? null;
		const buttons = Array.from(
			treeRoot?.querySelectorAll<HTMLElement>(
				'button[data-item-path]:not([data-file-tree-sticky-row]):not([data-item-parked])',
			) ?? [],
		);
		const targetButton =
			buttons.find((button): boolean => button.getAttribute('data-item-path') === targetPath) ??
			null;
		const selectedButton =
			buttons.find((button): boolean => button.getAttribute('aria-selected') === 'true') ?? null;
		const targetRect = targetButton?.getBoundingClientRect() ?? null;
		const centerX = targetRect === null ? null : targetRect.left + targetRect.width / 2;
		const centerY = targetRect === null ? null : targetRect.top + targetRect.height / 2;
		const elementAtTargetCenter =
			centerX === null || centerY === null ? null : document.elementFromPoint(centerX, centerY);
		const activeElement = treeRoot?.activeElement ?? document.activeElement;
		return {
			activeElementItemPath:
				activeElement instanceof HTMLElement ? activeElement.getAttribute('data-item-path') : null,
			codeViewItemCount:
				codePanel instanceof HTMLElement
					? Number(codePanel.getAttribute('data-code-view-item-count') ?? '0')
					: 0,
			elementAtTargetCenterItemPath:
				elementAtTargetCenter instanceof HTMLElement
					? elementAtTargetCenter.getAttribute('data-item-path')
					: null,
			elementAtTargetCenterTagName: elementAtTargetCenter?.tagName ?? null,
			selectedButtonItemPath: selectedButton?.getAttribute('data-item-path') ?? null,
			selectedContentState:
				reviewShell instanceof HTMLElement
					? reviewShell.getAttribute('data-selected-content-state')
					: null,
			selectedDisplayPath:
				reviewShell instanceof HTMLElement
					? reviewShell.getAttribute('data-selected-display-path')
					: null,
			selectedMaterializedItemType:
				codePanel instanceof HTMLElement
					? codePanel.getAttribute('data-selected-materialized-item-type')
					: null,
			selectedModelContentState:
				codePanel instanceof HTMLElement
					? codePanel.getAttribute('data-selected-materialized-model-content-state')
					: null,
			targetButtonAriaSelected: targetButton?.getAttribute('aria-selected') ?? null,
			targetButtonConnected: targetButton?.isConnected ?? false,
			targetButtonItemPath: targetButton?.getAttribute('data-item-path') ?? null,
			targetButtonRect:
				targetRect === null
					? null
					: {
							bottom: targetRect.bottom,
							height: targetRect.height,
							left: targetRect.left,
							right: targetRect.right,
							top: targetRect.top,
							width: targetRect.width,
						},
			targetPath,
			textLength:
				codePanel instanceof HTMLElement ? (codePanel.textContent ?? '').trim().length : 0,
			visiblePaths: buttons
				.slice(0, 16)
				.map((button): string | null => button.getAttribute('data-item-path')),
		};
	}, props.targetPath);
	return JSON.stringify(diagnostic);
}

export async function waitForReviewRenderedSelection(props: {
	readonly expectedItemId: string;
	readonly expectedMaterializedItemType: ReviewRenderedSelectionExpectation['expectedMaterializedItemType'];
	readonly expectedVisibleText: string;
	readonly page: Page;
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(expected: {
				readonly expectedItemId: string;
				readonly expectedMaterializedItemType: ReviewRenderedSelectionExpectation['expectedMaterializedItemType'];
				readonly expectedVisibleText: string;
			}): boolean => {
				const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				const codeViewOverflow = codePanel?.getAttribute('data-bridge-code-view-overflow') ?? null;
				const selectedItemId = codePanel?.getAttribute('data-selected-item-id') ?? null;
				const selectedMaterializedItemType =
					codePanel?.getAttribute('data-selected-materialized-item-type') ?? null;
				const lightDomHeaders = [
					...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
				].filter(
					(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
				);
				const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
					(element: Element): readonly HTMLButtonElement[] =>
						[
							...(element.shadowRoot?.querySelectorAll(
								'[data-testid="bridge-code-view-header-collapse-button"]',
							) ?? []),
						].filter(
							(headerElement: Element): headerElement is HTMLButtonElement =>
								headerElement instanceof HTMLButtonElement,
						),
				);
				const selectedHeaderPresent = [...lightDomHeaders, ...shadowDomHeaders].some(
					(selectedHeader: HTMLButtonElement): boolean =>
						selectedHeader.dataset['bridgeCodeViewItemId'] === expected.expectedItemId,
				);
				const shadowText = [...document.querySelectorAll('diffs-container')]
					.map((element: Element): string => element.shadowRoot?.textContent ?? '')
					.join(' ');
				const visibleText = [
					codePanel instanceof HTMLElement ? (codePanel.textContent ?? '') : '',
					shadowText,
				].join(' ');
				return (
					codeViewOverflow === 'wrap' &&
					selectedItemId === expected.expectedItemId &&
					selectedHeaderPresent &&
					selectedMaterializedItemType === expected.expectedMaterializedItemType &&
					visibleText.includes(expected.expectedVisibleText)
				);
			},
			{
				expectedItemId: props.expectedItemId,
				expectedMaterializedItemType: props.expectedMaterializedItemType,
				expectedVisibleText: props.expectedVisibleText,
			},
			{ timeout: 30_000 },
		);
	} catch (error) {
		const debugState = await readReviewRenderedSelectionSnapshot(props.page);
		throw new Error(
			`Timed out waiting for Review CodeView to render ${props.expectedItemId}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

export async function readReviewRenderedSelectionSnapshot(
	page: Page,
): Promise<ReviewRenderedSelectionSnapshot> {
	return page.evaluate((): ReviewRenderedSelectionSnapshot => {
		const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		const codeViewOverflow = codePanel?.getAttribute('data-bridge-code-view-overflow') ?? null;
		const selectedItemId = codePanel?.getAttribute('data-selected-item-id') ?? null;
		const lightDomHeaders = [
			...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
		].filter(
			(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
		);
		const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
			(element: Element): readonly HTMLButtonElement[] =>
				[
					...(element.shadowRoot?.querySelectorAll(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					) ?? []),
				].filter(
					(headerElement: Element): headerElement is HTMLButtonElement =>
						headerElement instanceof HTMLButtonElement,
				),
		);
		const selectedHeaderPresent = [...lightDomHeaders, ...shadowDomHeaders].some(
			(selectedHeader: HTMLButtonElement): boolean =>
				selectedHeader.dataset['bridgeCodeViewItemId'] === selectedItemId,
		);
		const shadowText = [...document.querySelectorAll('diffs-container')]
			.map((element: Element): string => element.shadowRoot?.textContent ?? '')
			.join(' ');
		const visibleText = [
			codePanel instanceof HTMLElement ? (codePanel.textContent ?? '') : '',
			shadowText,
		].join(' ');
		return {
			codeViewOverflow,
			selectedHeaderPresent,
			selectedItemId,
			selectedMaterializedFileLineCount:
				codePanel instanceof HTMLElement
					? Number(codePanel.getAttribute('data-selected-materialized-file-line-count') ?? '0')
					: 0,
			selectedMaterializedItemType:
				codePanel?.getAttribute('data-selected-materialized-item-type') ?? null,
			visibleText,
		};
	});
}

export async function readReviewCollapseControlProof(props: {
	readonly expectedItemId: string;
	readonly page: Page;
}): Promise<ReviewCollapseControlProof> {
	const candidates = await props.page.evaluate((): ReviewCollapseControlCandidate[] => {
		const lightDomHeaders = [
			...document.querySelectorAll('[data-testid="bridge-code-view-header-collapse-button"]'),
		].filter(
			(element: Element): element is HTMLButtonElement => element instanceof HTMLButtonElement,
		);
		const shadowDomHeaders = [...document.querySelectorAll('diffs-container')].flatMap(
			(element: Element): readonly HTMLButtonElement[] =>
				[
					...(element.shadowRoot?.querySelectorAll(
						'[data-testid="bridge-code-view-header-collapse-button"]',
					) ?? []),
				].filter(
					(headerElement: Element): headerElement is HTMLButtonElement =>
						headerElement instanceof HTMLButtonElement,
				),
		);
		return [...lightDomHeaders, ...shadowDomHeaders].map(
			(selectedHeader: HTMLButtonElement): ReviewCollapseControlCandidate => {
				const selectedHeaderRect = selectedHeader.getBoundingClientRect();
				const selectedHeaderStyle = getComputedStyle(selectedHeader);
				return {
					proof: {
						ariaExpanded: selectedHeader.getAttribute('aria-expanded'),
						fontSize: selectedHeaderStyle.fontSize,
						height: selectedHeaderRect.height,
						itemId: selectedHeader.dataset['bridgeCodeViewItemId'] ?? null,
						present: true,
						primitiveSlot: selectedHeader.getAttribute('data-slot'),
					},
					visible: selectedHeader.getClientRects().length > 0,
				};
			},
		);
	});
	return selectVisibleReviewCollapseControlProof({
		candidates,
		expectedItemId: props.expectedItemId,
	});
}

export async function waitForWorktreeSourceCursor(props: {
	readonly page: Page;
	readonly sourceCursor: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(expectedSourceCursor: string): boolean =>
			document
				.querySelector('[data-testid="bridge-file-viewer-shell"]')
				?.getAttribute('data-worktree-source-cursor') === expectedSourceCursor,
		props.sourceCursor,
		{ timeout: 20_000 },
	);
}

export async function waitForWorktreeDevForceSplitReloadDelivered(props: {
	readonly page: Page;
	readonly sourceCursor: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(expectedSourceCursor: string): boolean =>
			document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] ===
				'force-split-reset' &&
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] ===
				'delivered' &&
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] ===
				expectedSourceCursor,
		props.sourceCursor,
		{ timeout: 20_000 },
	);
}

export async function waitForWorktreeDevReloadDelivered(props: {
	readonly page: Page;
	readonly sourceCursor: string;
}): Promise<void> {
	await props.page.waitForFunction(
		(expectedSourceCursor: string): boolean =>
			document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] === 'normal' &&
			document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] === 'delivered' &&
			document.documentElement.dataset['bridgeWorktreeDevLastReloadSourceCursor'] ===
				expectedSourceCursor,
		props.sourceCursor,
		{ timeout: 20_000 },
	);
}

export async function setWorktreeDevSplitResetReplacementDelay(props: {
	readonly delayMilliseconds: number | null;
	readonly page: Page;
}): Promise<void> {
	await props.page.evaluate((delayMilliseconds: number | null): void => {
		if (delayMilliseconds === null) {
			delete document.documentElement.dataset['bridgeWorktreeDevSplitResetReplacementDelayMs'];
			return;
		}
		document.documentElement.dataset['bridgeWorktreeDevSplitResetReplacementDelayMs'] =
			String(delayMilliseconds);
	}, props.delayMilliseconds);
}

export async function waitForWorktreeRefreshButtonEnabled(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const refreshButton = document.querySelector<HTMLButtonElement>(
				'[data-testid="worktree-file-refresh"]',
			);
			return refreshButton !== null && !refreshButton.disabled;
		},
		{ timeout: 10_000 },
	);
}

export async function waitForWorktreeFileSourceCleared(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			return shell instanceof HTMLElement && !shell.hasAttribute('data-worktree-source-state');
		},
		{ timeout: 10_000 },
	);
}

export async function installWorktreeRefreshClickProbe(page: Page): Promise<void> {
	await page.evaluate((): void => {
		document.documentElement.dataset['bridgeWorktreeVerifierRefreshClicked'] = 'pending';
		document.documentElement.dataset['bridgeWorktreeVerifierRefreshClickBubbled'] = 'pending';
		const refreshButton = document.querySelector('[data-testid="worktree-file-refresh"]');
		refreshButton?.addEventListener(
			'click',
			(): void => {
				document.documentElement.dataset['bridgeWorktreeVerifierRefreshClicked'] = 'clicked';
			},
			{ once: true, capture: true },
		);
		document.addEventListener(
			'click',
			(): void => {
				document.documentElement.dataset['bridgeWorktreeVerifierRefreshClickBubbled'] = 'bubbled';
			},
			{ once: true },
		);
	});
}

export async function setWorktreeOpenStateWaitLabel(page: Page, label: string): Promise<void> {
	await page.evaluate((nextLabel: string): void => {
		document.documentElement.dataset['bridgeWorktreeVerifierOpenWaitLabel'] = nextLabel;
	}, label);
}

export async function waitForWorktreeRefreshClickProbe(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean =>
			document.documentElement.dataset['bridgeWorktreeVerifierRefreshClicked'] === 'clicked',
		{ timeout: 5_000 },
	);
}

export async function readWorktreeRefreshButtonDisabled(page: Page): Promise<boolean> {
	return await page.evaluate((): boolean => {
		const refreshButton = document.querySelector<HTMLButtonElement>(
			'[data-testid="worktree-file-refresh"]',
		);
		if (refreshButton === null) {
			throw new Error('Expected Worktree/File refresh button to be present');
		}
		return refreshButton.disabled;
	});
}

export async function readWorktreeDevReloadProof(page: Page): Promise<WorktreeDevReloadProof> {
	const rawProof = await page.evaluate(() => {
		const frameGenerationsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameGenerations'] ??
			'';
		const frameKindsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'] ?? '';
		const frameSequencesText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameSequences'] ?? '';
		const frameStreamIdsText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameStreamIds'] ?? '';
		const frameCountText =
			document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameCount'] ?? null;
		return {
			frameCountText,
			frameGenerationsText,
			frameKindsText,
			frameSequencesText,
			frameStreamIdsText,
			request: document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] ?? null,
			sourceCursor:
				document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] ??
				null,
			status:
				document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] ?? null,
		};
	});
	return {
		frameCount:
			rawProof.frameCountText === null
				? 0
				: parseBridgeWorktreeDevReloadIntegerToken({
						label: 'frame count',
						token: rawProof.frameCountText,
					}),
		frameGenerations: parseBridgeWorktreeDevReloadIntegerList({
			label: 'frame generations',
			text: rawProof.frameGenerationsText,
		}),
		frameKinds: parseBridgeWorktreeDevReloadStringList(rawProof.frameKindsText),
		frameSequences: parseBridgeWorktreeDevReloadIntegerList({
			label: 'frame sequences',
			text: rawProof.frameSequencesText,
		}),
		frameStreamIds: parseBridgeWorktreeDevReloadStringList(rawProof.frameStreamIdsText),
		request: rawProof.request,
		sourceCursor: rawProof.sourceCursor,
		status: rawProof.status,
	};
}
