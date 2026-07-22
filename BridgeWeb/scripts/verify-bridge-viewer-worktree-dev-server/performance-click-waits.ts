import type { Page } from 'playwright';

import { clickWorktreeFilePath } from './content-state.ts';

export async function readReviewCodeViewItemCount(page: Page): Promise<number> {
	return await page.evaluate((): number => {
		const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		if (!(codePanel instanceof HTMLElement)) {
			return 0;
		}
		const itemCount = Number(codePanel.getAttribute('data-code-view-item-count') ?? '0');
		return Number.isFinite(itemCount) ? itemCount : 0;
	});
}

export async function clickVisibleWorktreeFilePath(page: Page, path: string): Promise<void> {
	const targetVisible = await page.evaluate((targetPath: string): boolean => {
		const button = window.bridgeWorktreeVerifier
			.getPierreFileTreeItems()
			.find((candidate) => candidate.dataset['itemPath'] === targetPath);
		const scrollElement = window.bridgeWorktreeVerifier.getPierreFileTreeScrollElement();
		if (!(button instanceof HTMLElement) || !(scrollElement instanceof HTMLElement)) {
			return false;
		}
		const buttonRect = button.getBoundingClientRect();
		const scrollRect = scrollElement.getBoundingClientRect();
		return buttonRect.bottom > scrollRect.top && buttonRect.top < scrollRect.bottom;
	}, path);
	if (!targetVisible) {
		throw new Error(`Expected visible Worktree/File row for performance click ${path}`);
	}
	await clickWorktreeFilePath(page, path);
}

export async function waitForWorktreeFirstVisibleContentWindow(props: {
	readonly page: Page;
	readonly path: string;
	readonly timeoutMilliseconds?: number;
}): Promise<void> {
	try {
		await props.page.waitForFunction(
			(targetPath: string): boolean => {
				const contentPanel = document.querySelector(
					'[data-testid="bridge-file-viewer-code-canvas"]',
				);
				if (!(contentPanel instanceof HTMLElement)) {
					return false;
				}
				const selectedPath = contentPanel.getAttribute('data-worktree-open-file-path');
				const openState = contentPanel.getAttribute('data-worktree-open-file-state');
				const lineCount = window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeLineCount();
				const renderedText = window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText();
				const fallbackText =
					contentPanel.querySelector('[data-testid="bridge-file-viewer-first-window-fallback"]')
						?.textContent ?? '';
				return (
					selectedPath === targetPath &&
					openState === 'ready' &&
					((lineCount > 0 && renderedText.trim().length > 0) || fallbackText.trim().length > 0)
				);
			},
			props.path,
			{ timeout: props.timeoutMilliseconds ?? 20_000 },
		);
	} catch (error) {
		throw new Error(
			`Timed out waiting for first visible Worktree/File content window for ${props.path}: ${await worktreeFirstVisibleContentWindowDiagnosticMessage(props.page)}`,
			{ cause: error },
		);
	}
}

export async function waitForWorktreeSelectedPathMilliseconds(props: {
	readonly page: Page;
	readonly path: string;
	readonly startedAt: number;
	readonly timeoutMilliseconds: number;
}): Promise<number> {
	try {
		await props.page.waitForFunction(
			(targetPath: string): boolean =>
				document
					.querySelector('[data-testid="bridge-file-viewer-shell"]')
					?.getAttribute('data-selected-display-path') === targetPath,
			props.path,
			{ timeout: props.timeoutMilliseconds },
		);
	} catch (error) {
		const debugState = await props.page.evaluate((targetPath: string) => {
			const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			return {
				currentOpenPath: contentPanel?.getAttribute('data-worktree-open-file-path') ?? null,
				currentOpenState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
				selectedDisplayPath: shell?.getAttribute('data-selected-display-path') ?? null,
				sourceCursor: shell?.getAttribute('data-worktree-source-cursor') ?? null,
				targetPath,
				targetTreeRowExists:
					window.bridgeWorktreeVerifier.getPierreFileTreeItem(targetPath) !== null,
			};
		}, props.path);
		throw new Error(
			`Timed out waiting for selected Worktree/File path ${props.path}: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
	return Math.max(0, performance.now() - props.startedAt);
}

export async function waitForAnyWorktreeSelectedPathTiming(props: {
	readonly page: Page;
	readonly startedAt: number;
	readonly timeoutMilliseconds: number;
}): Promise<{
	readonly path: string;
	readonly selectedPathMilliseconds: number;
}> {
	try {
		const selectedPathHandle = await props.page.waitForFunction(
			(): string | false => {
				const selectedPath = document
					.querySelector('[data-testid="bridge-file-viewer-shell"]')
					?.getAttribute('data-selected-display-path');
				return selectedPath === undefined || selectedPath === null || selectedPath.length === 0
					? false
					: selectedPath;
			},
			{ timeout: props.timeoutMilliseconds },
		);
		const path = await selectedPathHandle.jsonValue();
		if (typeof path !== 'string' || path.length === 0) {
			throw new Error(`Expected non-empty selected Worktree/File path, got ${String(path)}`);
		}
		return {
			path,
			selectedPathMilliseconds: Math.max(0, performance.now() - props.startedAt),
		};
	} catch (error) {
		const debugState = await props.page.evaluate(() => {
			const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			return {
				currentOpenPath: contentPanel?.getAttribute('data-worktree-open-file-path') ?? null,
				currentOpenState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
				selectedDisplayPath: shell?.getAttribute('data-selected-display-path') ?? null,
				sourceCursor: shell?.getAttribute('data-worktree-source-cursor') ?? null,
			};
		});
		throw new Error(
			`Timed out waiting for any selected Worktree/File startup path: ${JSON.stringify(debugState)}`,
			{ cause: error },
		);
	}
}

export async function waitForWorktreeOpenFileReadyMilliseconds(props: {
	readonly page: Page;
	readonly path: string;
	readonly startedAt: number;
	readonly timeoutMilliseconds: number;
}): Promise<number> {
	await props.page.waitForFunction(
		(targetPath: string): boolean => {
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			return (
				contentPanel?.getAttribute('data-worktree-open-file-path') === targetPath &&
				contentPanel?.getAttribute('data-worktree-open-file-state') === 'ready'
			);
		},
		props.path,
		{ timeout: props.timeoutMilliseconds },
	);
	return Math.max(0, performance.now() - props.startedAt);
}

export async function worktreeFirstVisibleContentWindowDiagnosticMessage(
	page: Page,
): Promise<string> {
	const diagnostic = await page.evaluate(
		(): {
			readonly lineCount: number;
			readonly openState: string | null;
			readonly renderedTextLength: number;
			readonly selectedPath: string | null;
		} => {
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const renderedText = window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText();
			return {
				lineCount: window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeLineCount(),
				openState:
					contentPanel instanceof HTMLElement
						? contentPanel.getAttribute('data-worktree-open-file-state')
						: null,
				renderedTextLength: renderedText.trim().length,
				selectedPath:
					contentPanel instanceof HTMLElement
						? contentPanel.getAttribute('data-worktree-open-file-path')
						: null,
			};
		},
	);
	return JSON.stringify(diagnostic);
}
