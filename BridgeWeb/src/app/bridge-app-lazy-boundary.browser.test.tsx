import type { ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

const bridgeAppLazyBoundaryMock = vi.hoisted(() => ({
	fileViewerImportCount: 0,
	fileViewerModuleMode: 'ready' as 'ready' | 'deferred',
	reviewViewerShellImportCount: 0,
	resolveFileViewerModule: null as null | (() => void),
}));

vi.mock('../file-viewer/bridge-file-viewer-app.js', () => {
	type FileViewerMockModule = {
		readonly BridgeFileViewerApp: () => ReactElement;
	};
	const makeFileViewerMockModule = (): FileViewerMockModule => ({
		BridgeFileViewerApp: (): ReactElement => <main data-testid="bridge-file-viewer-lazy-mock" />,
	});
	bridgeAppLazyBoundaryMock.fileViewerImportCount += 1;
	if (bridgeAppLazyBoundaryMock.fileViewerModuleMode === 'deferred') {
		return new Promise<FileViewerMockModule>((resolve) => {
			bridgeAppLazyBoundaryMock.resolveFileViewerModule = (): void => {
				resolve(makeFileViewerMockModule());
			};
		});
	}
	return makeFileViewerMockModule();
});

vi.mock('../review-viewer/shell/review-viewer-shell.js', () => {
	bridgeAppLazyBoundaryMock.reviewViewerShellImportCount += 1;
	return {
		BridgeReviewEmptyShell: (): ReactElement => <main data-testid="bridge-review-empty-shell" />,
		BridgeReviewMetadataFailedShell: (): ReactElement => (
			<main data-testid="bridge-review-metadata-failed-shell" />
		),
		BridgeReviewMetadataLoadingShell: (): ReactElement => (
			<main data-testid="bridge-review-metadata-loading-shell" />
		),
		BridgeReviewProjectionFailedShell: (): ReactElement => (
			<main data-testid="bridge-review-projection-failed-shell" />
		),
		BridgeReviewProjectionPendingShell: (): ReactElement => (
			<main data-testid="bridge-review-projection-pending-shell" />
		),
		ReviewViewerShell: (): ReactElement => <main data-testid="review-viewer-shell-lazy-mock" />,
	};
});

describe('BridgeApp lazy mode boundaries', () => {
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		bridgeAppLazyBoundaryMock.fileViewerImportCount = 0;
		bridgeAppLazyBoundaryMock.fileViewerModuleMode = 'ready';
		bridgeAppLazyBoundaryMock.reviewViewerShellImportCount = 0;
		bridgeAppLazyBoundaryMock.resolveFileViewerModule?.();
		bridgeAppLazyBoundaryMock.resolveFileViewerModule = null;
	});

	test('does not load the FileViewer module for the default Review route', async () => {
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

		expect(bridgeAppLazyBoundaryMock.fileViewerImportCount).toBe(0);
		expect(bridgeAppLazyBoundaryMock.reviewViewerShellImportCount).toBe(0);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-viewer-content-topbar"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-viewer-context-switcher"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-rail-toolbar"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-file-viewer-lazy-mock"]')).toBeNull();
	});

	test('keeps mode hosts mounted while the FileViewer module is suspended', async () => {
		bridgeAppLazyBoundaryMock.fileViewerModuleMode = 'deferred';
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		const fileModeButton = requireHTMLButtonElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);

		fileModeButton.click();

		await expect
			.poll(
				() =>
					document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]') !== null,
			)
			.toBe(true);

		const fileModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
		);
		const fileLoadingFrame = requireHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]'),
		);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).toBe(appRoot);
		expect(document.querySelector('[data-testid="bridge-viewer-mode-host-review"]')).toBe(
			reviewModeHost,
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(fileModeHost.hidden).toBe(false);
		expect(fileLoadingFrame.closest('[data-testid="bridge-viewer-mode-host-file"]')).toBe(
			fileModeHost,
		);
		expect(document.querySelector('[data-testid="bridge-file-viewer-lazy-mock"]')).toBeNull();
		await expect.poll(() => bridgeAppLazyBoundaryMock.fileViewerImportCount).toBe(1);

		bridgeAppLazyBoundaryMock.resolveFileViewerModule?.();

		await expect
			.poll(() => document.querySelector('[data-testid="bridge-file-viewer-lazy-mock"]') !== null)
			.toBe(true);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).toBe(appRoot);
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected HTMLElement');
	}
	return element;
}

function requireHTMLButtonElement(element: Element | null): HTMLButtonElement {
	if (!(element instanceof HTMLButtonElement)) {
		throw new Error('Expected HTMLButtonElement');
	}
	return element;
}
