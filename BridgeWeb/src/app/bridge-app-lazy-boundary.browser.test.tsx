import type { ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewProjectionRequestIdentity } from '../review-viewer/models/review-projection-models.js';
import type { UseBridgeReviewProjectionCoordinatorProps } from '../review-viewer/projections/use-review-projection-coordinator.js';

const bridgeAppLazyBoundaryMock = vi.hoisted(() => ({
	fileViewerImportCount: 0,
	fileViewerModuleMode: 'ready' as 'ready' | 'deferred',
	projectionApplyCount: 0,
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

vi.mock('../review-viewer/projections/use-review-projection-coordinator.js', async () => {
	const React = await import('react');
	const { buildBridgeReviewProjection } =
		await import('../review-viewer/navigation/review-projection.js');
	return {
		useBridgeReviewProjectionCoordinator: (
			props: UseBridgeReviewProjectionCoordinatorProps,
		): void => {
			React.useEffect((): void => {
				if (props.reviewPackage === null) {
					return;
				}
				const identity: BridgeReviewProjectionRequestIdentity = {
					requestId: `lazy-boundary-projection-${bridgeAppLazyBoundaryMock.projectionApplyCount + 1}`,
					packageId: props.reviewPackage.packageId,
					reviewGeneration: props.reviewPackage.reviewGeneration,
					revision: props.reviewPackage.revision,
					projectionRequestFingerprint: 'lazy-boundary-projection',
				};
				props.store.getState().actions.startProjectionRequest(identity);
				props.store.getState().actions.applyProjectionWorkerResult({
					identity,
					result: buildBridgeReviewProjection({
						reviewPackage: props.reviewPackage,
						request: {
							mode: props.projectionMode,
							facets: props.facets,
						},
					}),
				});
				bridgeAppLazyBoundaryMock.projectionApplyCount += 1;
			}, [props.facets, props.projectionMode, props.reviewPackage, props.store]);
		},
	};
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
		bridgeAppLazyBoundaryMock.projectionApplyCount = 0;
		bridgeAppLazyBoundaryMock.reviewViewerShellImportCount = 0;
		bridgeAppLazyBoundaryMock.resolveFileViewerModule?.();
		bridgeAppLazyBoundaryMock.resolveFileViewerModule = null;
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
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

	test('does not load the ready Review shell while Review is hidden before first ready activation', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds,
		});
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

		requireHTMLButtonElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		).click();
		await expect
			.poll(() => document.querySelector('[data-testid="bridge-file-viewer-lazy-mock"]') !== null)
			.toBe(true);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: reviewPackage.query.queryId,
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: snapshotFrame.sequence,
			payload: snapshotFrame,
		});
		await expect.poll(() => bridgeAppLazyBoundaryMock.projectionApplyCount).toBe(1);

		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(bridgeAppLazyBoundaryMock.reviewViewerShellImportCount).toBe(0);
		expect(
			reviewModeHost.querySelector('[data-testid="review-viewer-shell-lazy-mock"]'),
		).toBeNull();
	});
});

async function dispatchHostAdmittedReviewIntakeFrame(frame: BridgeIntakeFrame): Promise<void> {
	document.dispatchEvent(
		new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
	);
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(frame),
				nonce: 'push-nonce',
			},
		}),
	);
	await Promise.resolve();
}

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
