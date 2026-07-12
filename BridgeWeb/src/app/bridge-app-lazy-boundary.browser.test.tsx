import type { ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import type { BridgeFileViewerBrowserTestProductSession } from '../file-viewer/bridge-file-viewer-browser-test-app.js';
import { makeTreeRowsOnlyMetadataEvents } from '../file-viewer/bridge-file-viewer-browser-test-fixtures.js';
import { createBridgeFileViewerBrowserTestCommWorkerTransportFactory } from '../file-viewer/bridge-file-viewer-browser-test-harness.js';
import { BridgeFileViewerRuntimeTransportFactoryProvider } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewProjectionRequestIdentity } from '../review-viewer/models/review-projection-models.js';
import type { UseBridgeReviewProjectionCoordinatorProps } from '../review-viewer/projections/use-review-projection-coordinator.js';
import { waitForBridgeViewerAnimationFrame } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import {
	actClick,
	actUpdate,
	actWait,
	createInProcessBridgeReviewWorkerTransportFactory,
	installBridgeReadyHandshake,
	pollWithinAct,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
} from './bridge-app-native-review-error.browser.test-support.js';

const bridgeAppLazyBoundaryMock = vi.hoisted(() => ({
	fileViewerShellImportCount: 0,
	fileViewerShellModuleMode: 'ready' as 'ready' | 'deferred',
	projectionApplyCount: 0,
	reviewViewerShellImportCount: 0,
	resolveFileViewerShellModule: null as null | (() => void),
}));

vi.mock('../file-viewer/bridge-file-viewer-shell.js', () => {
	type FileViewerShellMockModule = {
		readonly BridgeFileViewerShell: () => ReactElement;
	};
	const makeFileViewerShellMockModule = (): FileViewerShellMockModule => ({
		BridgeFileViewerShell: (): ReactElement => (
			<main data-testid="bridge-file-viewer-shell-lazy-mock" />
		),
	});
	bridgeAppLazyBoundaryMock.fileViewerShellImportCount += 1;
	if (bridgeAppLazyBoundaryMock.fileViewerShellModuleMode === 'deferred') {
		return new Promise<FileViewerShellMockModule>((resolve) => {
			bridgeAppLazyBoundaryMock.resolveFileViewerShellModule = (): void => {
				resolve(makeFileViewerShellMockModule());
			};
		});
	}
	return makeFileViewerShellMockModule();
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
	let bridgeReadyDisposers: readonly (() => void)[] = [];

	afterEach(async () => {
		for (const dispose of bridgeReadyDisposers) {
			dispose();
		}
		bridgeReadyDisposers = [];
		const resolveFileViewerShellModule = bridgeAppLazyBoundaryMock.resolveFileViewerShellModule;
		bridgeAppLazyBoundaryMock.resolveFileViewerShellModule = null;
		if (resolveFileViewerShellModule !== null) {
			await actWait(async (): Promise<void> => {
				resolveFileViewerShellModule();
				await Promise.resolve();
				await waitForBridgeViewerAnimationFrame();
			});
		}
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		bridgeAppLazyBoundaryMock.fileViewerShellImportCount = 0;
		bridgeAppLazyBoundaryMock.fileViewerShellModuleMode = 'ready';
		bridgeAppLazyBoundaryMock.projectionApplyCount = 0;
		bridgeAppLazyBoundaryMock.reviewViewerShellImportCount = 0;
		vi.restoreAllMocks();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
	});

	test('does not load the FileViewer visual shell for the default Review route', async () => {
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

		expect(bridgeAppLazyBoundaryMock.fileViewerShellImportCount).toBe(0);
		expect(bridgeAppLazyBoundaryMock.reviewViewerShellImportCount).toBe(0);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-viewer-content-topbar"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-viewer-context-switcher"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-review-rail-toolbar"]')).not.toBeNull();
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]')).toBeNull();
	});

	// This test must run before any test that activates Files mode with the
	// default (non-deferred) mock module, e.g. 'defers FileView frame loading...'
	// below. Browser-mode `vi.resetModules()` clears vitest's own registry but
	// does not force the browser's ESM graph to re-evaluate every transitively
	// imported module (no `experimental.viteModuleRunner` here), so
	// `bridge-file-viewer-app.tsx`'s module-scope `LazyBridgeFileViewerShell`
	// stays the same `React.lazy()` instance across tests in this file. Once
	// any earlier test resolves it (mock mode 'ready'), it never suspends
	// again, so this Suspense-fallback assertion needs to run first.
	test('keeps mode hosts mounted while the FileViewer visual shell is suspended', async () => {
		bridgeAppLazyBoundaryMock.fileViewerShellModuleMode = 'deferred';
		let sourceDiscoveryCount = 0;
		bridgeReadyDisposers = [
			...bridgeReadyDisposers,
			installBridgeReadyHandshake({ pushNonce: 'push-nonce' }).dispose,
		];
		const { BridgeApp } = await import('./bridge-app.js');

		renderFileProductApp(
			<BridgeApp viewerMode="review" />,
			fileProductSessionWithSourceDiscoveryCounter((): void => {
				sourceDiscoveryCount += 1;
			}),
		);
		await actUpdate((): void => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
		});

		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		const fileModeButton = requireHTMLButtonElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);

		await actClick(fileModeButton);

		expect(
			await pollWithinAct({
				getValue: () =>
					document.querySelector('[data-testid="bridge-file-viewer-lazy-loading-frame"]') !== null,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);

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
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]')).toBeNull();
		expect(
			await pollWithinActUntilEqual(() => bridgeAppLazyBoundaryMock.fileViewerShellImportCount, 1),
		).toBe(1);
		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);

		await actWait(async (): Promise<void> => {
			bridgeAppLazyBoundaryMock.resolveFileViewerShellModule?.();
			await waitForBridgeViewerAnimationFrame();
			await waitForBridgeViewerAnimationFrame();
		});

		expect(
			await pollWithinAct({
				getValue: () =>
					document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).toBe(appRoot);
	});

	test('defers FileView frame loading on a Review-first route until Files activates', async () => {
		let sourceDiscoveryCount = 0;
		bridgeReadyDisposers = [
			...bridgeReadyDisposers,
			installBridgeReadyHandshake({ pushNonce: 'push-nonce' }).dispose,
		];
		const { BridgeApp } = await import('./bridge-app.js');

		renderFileProductApp(
			<BridgeApp viewerMode="review" />,
			fileProductSessionWithSourceDiscoveryCounter((): void => {
				sourceDiscoveryCount += 1;
			}),
		);
		await actUpdate((): void => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
		});
		expect(sourceDiscoveryCount).toBe(0);
		expect(bridgeAppLazyBoundaryMock.fileViewerShellImportCount).toBe(0);
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]')).toBeNull();

		const fileModeButton = requireHTMLButtonElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);
		await actWait(async (): Promise<void> => {
			fileModeButton.click();
			await Promise.resolve();
			await waitForBridgeViewerAnimationFrame();
		});

		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);
	});

	test('sends Review metadata interest from the mode controller after native intake', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
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
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const transportFactory = createInProcessBridgeReviewWorkerTransportFactory({
			sendSchemeRpcCommand: async (command): Promise<unknown> => {
				commandDetails.push(command);
				return {};
			},
		});
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp reviewWorkerTransportFactory={transportFactory} viewerMode="review" />);

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

		expect(
			await pollWithinActUntilTruthy(() =>
				commandDetails.find(
					(detail) => isRecord(detail) && detail['method'] === 'bridge.metadata_interest.update',
				),
			),
		).toMatchObject({
			method: 'bridge.metadata_interest.update',
			params: {
				protocol: 'review',
				streamId,
				generation: reviewPackage.reviewGeneration,
				itemIds: [reviewPackage.orderedItemIds[0]],
				lane: 'foreground',
			},
		});
		expect(
			await pollWithinAct({
				getValue: () =>
					document.querySelector('[data-testid="review-viewer-shell-lazy-mock"]') !== null,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);
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
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

		const fileModeButton = requireHTMLButtonElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);
		await actWait(async (): Promise<void> => {
			fileModeButton.click();
			await Promise.resolve();
			await waitForBridgeViewerAnimationFrame();
		});
		expect(
			await pollWithinAct({
				getValue: () =>
					document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);
		expect(
			await pollWithinAct({
				getValue: () =>
					requireHTMLElement(
						document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
					).hidden,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);
		bridgeAppLazyBoundaryMock.reviewViewerShellImportCount = 0;
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
		expect(
			await pollWithinActUntilEqual(() => bridgeAppLazyBoundaryMock.projectionApplyCount, 1),
		).toBe(1);

		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(bridgeAppLazyBoundaryMock.reviewViewerShellImportCount).toBe(0);
		expect(
			reviewModeHost.querySelector('[data-testid="review-viewer-shell-lazy-mock"]'),
		).toBeNull();
	});

	test('applies Review metadata from a hidden initial File route without loading the Review shell', async () => {
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
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="file" />);

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

		expect(
			await pollWithinActUntilEqual(() => bridgeAppLazyBoundaryMock.projectionApplyCount, 1),
		).toBe(1);

		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(bridgeAppLazyBoundaryMock.reviewViewerShellImportCount).toBe(0);
		expect(
			reviewModeHost.querySelector('[data-testid="review-viewer-shell-lazy-mock"]'),
		).toBeNull();
	});

	test('keeps both mode hosts and Review projection across a Review -> File -> Review round trip', async () => {
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
		let sourceDiscoveryCount = 0;
		bridgeReadyDisposers = [
			...bridgeReadyDisposers,
			installBridgeReadyHandshake({ pushNonce: 'push-nonce' }).dispose,
		];
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const { BridgeApp } = await import('./bridge-app.js');
		const productSession = fileProductSessionWithSourceDiscoveryCounter((): void => {
			sourceDiscoveryCount += 1;
		});
		const transportFactory = createBridgeFileViewerBrowserTestCommWorkerTransportFactory({
			productSessionRef: { current: productSession },
		});
		const wrapApp = (viewerMode: 'file' | 'review'): ReactElement => (
			<BridgeFileViewerRuntimeTransportFactoryProvider transportFactory={transportFactory}>
				<BridgeApp viewerMode={viewerMode} />
			</BridgeFileViewerRuntimeTransportFactoryProvider>
		);
		const { rerender } = render(wrapApp('review'));

		// Establish the Review projection from native intake.
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
		expect(
			await pollWithinActUntilEqual(() => bridgeAppLazyBoundaryMock.projectionApplyCount, 1),
		).toBe(1);

		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		const projectionApplyCountBeforeRoundTrip = bridgeAppLazyBoundaryMock.projectionApplyCount;

		// Switch to Files: the pane worker discovers and opens the typed File source exactly once.
		await actUpdate((): void => {
			rerender(wrapApp('file'));
		});
		expect(
			await pollWithinAct({
				getValue: () =>
					document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);
		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);
		const fileModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(fileModeHost.hidden).toBe(false);

		// Switch back to Review.
		await actUpdate((): void => {
			rerender(wrapApp('review'));
		});
		expect(
			await pollWithinAct({
				getValue: () => {
					const host = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
					return host instanceof HTMLElement && !host.hidden;
				},
				isSatisfied: (value): boolean => value,
			}),
		).toBe(true);

		// Both mode hosts keep DOM identity across the round trip.
		expect(document.querySelector('[data-testid="bridge-viewer-mode-host-review"]')).toBe(
			reviewModeHost,
		);
		expect(document.querySelector('[data-testid="bridge-viewer-mode-host-file"]')).toBe(
			fileModeHost,
		);
		// The File host stays mounted (hidden) with its already-loaded shell; it never reloaded.
		expect(fileModeHost.hidden).toBe(true);
		expect(
			fileModeHost.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]'),
		).not.toBeNull();
		expect(sourceDiscoveryCount).toBe(1);
		// The Review projection was not re-applied across the round trip (no re-apply storm).
		expect(bridgeAppLazyBoundaryMock.projectionApplyCount).toBe(
			projectionApplyCountBeforeRoundTrip,
		);
	});
});

async function dispatchHostAdmittedReviewIntakeFrame(frame: BridgeIntakeFrame): Promise<void> {
	await actUpdate((): void => {
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
	});
	await actWait(waitForBridgeViewerAnimationFrame);
}

function renderFileProductApp(
	app: ReactElement,
	productSession: BridgeFileViewerBrowserTestProductSession,
): ReturnType<typeof render> {
	const transportFactory = createBridgeFileViewerBrowserTestCommWorkerTransportFactory({
		productSessionRef: { current: productSession },
	});
	return render(
		<BridgeFileViewerRuntimeTransportFactoryProvider transportFactory={transportFactory}>
			{app}
		</BridgeFileViewerRuntimeTransportFactoryProvider>,
	);
}

function fileProductSessionWithSourceDiscoveryCounter(
	onSourceDiscovery: () => void,
): BridgeFileViewerBrowserTestProductSession {
	return {
		currentSource: () => {
			onSourceDiscovery();
			return {
				status: 'available',
				source: {
					cwdScope: null,
					freshness: 'live',
					includeStatuses: true,
					repoId: '00000000-0000-4000-8000-000000000001',
					rootPathToken: 'browser-test-root',
					worktreeId: '00000000-0000-4000-8000-000000000002',
				},
			};
		},
		initialMetadataEvents: makeTreeRowsOnlyMetadataEvents(),
	};
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

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
