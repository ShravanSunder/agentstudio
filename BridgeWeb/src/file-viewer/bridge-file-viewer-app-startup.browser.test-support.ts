import { actFrame } from './bridge-file-viewer-browser-test-harness.js';

interface FileViewerUiTraceEntry {
	readonly contentStateText: string | null;
	readonly hasLazyFrame: boolean;
	readonly hasShell: boolean;
	readonly initialSurfaceState: string | null;
	readonly metadataTreeRowCount: string | null;
	readonly timestampMilliseconds: number;
	readonly visibleText: string;
}

declare global {
	interface Window {
		bridgeFileViewerUiTrace?: FileViewerUiTraceEntry[];
	}
}

export function startFileViewerUiTrace(): () => void {
	window.bridgeFileViewerUiTrace = [];
	const recordSnapshot = (): void => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const contentState = document.querySelector('[data-testid="bridge-file-viewer-content-state"]');
		window.bridgeFileViewerUiTrace?.push({
			contentStateText: normalizedText(contentState?.textContent ?? null),
			hasLazyFrame:
				document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]') !== null,
			hasShell: shell !== null,
			initialSurfaceState: shell?.getAttribute('data-worktree-initial-surface-state') ?? null,
			metadataTreeRowCount: shell?.getAttribute('data-worktree-metadata-tree-row-count') ?? null,
			timestampMilliseconds: performance.now(),
			visibleText: normalizedText(document.body.textContent ?? '') ?? '',
		});
	};
	recordSnapshot();
	const observer = new MutationObserver(recordSnapshot);
	observer.observe(document.body, {
		attributes: true,
		childList: true,
		characterData: true,
		subtree: true,
	});
	return (): void => {
		observer.disconnect();
		recordSnapshot();
	};
}

export async function waitForFileViewerTrace(
	predicate: (entries: readonly FileViewerUiTraceEntry[]) => boolean,
	attempt = 0,
): Promise<void> {
	if (predicate(fileViewerUiTraceEntries())) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(
			`Expected FileView UI trace predicate to pass; entries=${JSON.stringify(
				fileViewerUiTraceEntries().slice(-5),
			)}`,
		);
	}
	await actFrame();
	await waitForFileViewerTrace(predicate, attempt + 1);
}

export function fileViewerUiTraceEntries(): readonly FileViewerUiTraceEntry[] {
	return window.bridgeFileViewerUiTrace ?? [];
}

function normalizedText(text: string | null): string | null {
	if (text === null) {
		return null;
	}
	return text.replace(/\s+/gu, ' ').trim();
}

export function fileViewerPendingCanvasIsVisible(visibleText: string): boolean {
	return (
		visibleText.includes('Select a file') ||
		visibleText.includes('Preparing code viewer') ||
		visibleText.includes('Code highlighting worker unavailable')
	);
}
