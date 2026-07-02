import { useEffect, useRef, useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import type {
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewProjectionRequestIdentity } from '../review-viewer/models/review-projection-models.js';
import type { UseBridgeReviewProjectionCoordinatorProps } from '../review-viewer/projections/use-review-projection-coordinator.js';
import { waitForBridgeViewerAnimationFrame } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';

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
	afterEach(() => {
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		bridgeAppLazyBoundaryMock.fileViewerShellImportCount = 0;
		bridgeAppLazyBoundaryMock.fileViewerShellModuleMode = 'ready';
		bridgeAppLazyBoundaryMock.projectionApplyCount = 0;
		bridgeAppLazyBoundaryMock.reviewViewerShellImportCount = 0;
		bridgeAppLazyBoundaryMock.resolveFileViewerShellModule?.();
		bridgeAppLazyBoundaryMock.resolveFileViewerShellModule = null;
		vi.resetModules();
		document.documentElement.removeAttribute('data-bridge-nonce');
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

	test('warms FileView frames on a Review-first route without loading the visual shell', async () => {
		const bufferedFrame: WorktreeFileProtocolFrame = {
			kind: 'reset',
			streamId: 'worktree-file:test',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'subscriptionReset',
		};
		let loadInitialSurfaceCount = 0;
		const { BridgeApp } = await import('./bridge-app.js');

		render(
			<BridgeApp
				fileViewerProps={{
					loadInitialSurface: async (): Promise<WorktreeFileInitialSurface> => {
						loadInitialSurfaceCount += 1;
						return { frames: [bufferedFrame] };
					},
				}}
				viewerMode="review"
			/>,
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);

		await expect.poll(() => loadInitialSurfaceCount).toBe(1);
		expect(bridgeAppLazyBoundaryMock.fileViewerShellImportCount).toBe(0);
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]')).toBeNull();
	});

	test('keeps mode hosts mounted while the FileViewer visual shell is suspended', async () => {
		bridgeAppLazyBoundaryMock.fileViewerShellModuleMode = 'deferred';
		const bufferedFrame: WorktreeFileProtocolFrame = {
			kind: 'reset',
			streamId: 'worktree-file:test',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'subscriptionReset',
		};
		let loadInitialSurfaceCount = 0;
		const { BridgeApp } = await import('./bridge-app.js');

		render(
			<BridgeApp
				fileViewerProps={{
					loadInitialSurface: async () => {
						loadInitialSurfaceCount += 1;
						return { frames: [bufferedFrame] };
					},
				}}
				viewerMode="review"
			/>,
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);
		await Promise.resolve();

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
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]')).toBeNull();
		await expect.poll(() => bridgeAppLazyBoundaryMock.fileViewerShellImportCount).toBe(1);
		await expect.poll(() => loadInitialSurfaceCount).toBe(1);

		bridgeAppLazyBoundaryMock.resolveFileViewerShellModule?.();

		await expect
			.poll(
				() => document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
			)
			.toBe(true);
		expect(document.querySelector('[data-testid="bridge-app-root"]')).toBe(appRoot);
	});

	test('does not restart FileView initial loading for fresh wrapper props with the same source', async () => {
		const bufferedFrame: WorktreeFileProtocolFrame = {
			kind: 'reset',
			streamId: 'worktree-file:test',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'subscriptionReset',
		};
		let loadInitialSurfaceCount = 0;
		const loadInitialSurface = async (): Promise<WorktreeFileInitialSurface> => {
			loadInitialSurfaceCount += 1;
			return { frames: [bufferedFrame] };
		};
		const { BridgeApp } = await import('./bridge-app.js');
		const { rerender } = render(
			<BridgeApp fileViewerProps={{ loadInitialSurface }} viewerMode="file" />,
		);

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
		);
		await expect.poll(() => loadInitialSurfaceCount).toBe(1);

		rerender(<BridgeApp fileViewerProps={{ loadInitialSurface }} viewerMode="file" />);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(loadInitialSurfaceCount).toBe(1);
	});

	test('merges subscribed FileView frames that arrive before the initial surface resolves', async () => {
		let publishFrame: WorktreeFileFrameSubscriber | null = null;
		let resolveInitialSurface: ((frames: readonly WorktreeFileProtocolFrame[]) => void) | null =
			null;
		let subscriberFrameCount = 0;
		const initialSurfacePromise = new Promise<readonly WorktreeFileProtocolFrame[]>((resolve) => {
			resolveInitialSurface = resolve;
		});
		const baselineFrame = makeWorktreeSnapshotFrame({
			sequence: 1,
			path: 'src/baseline.ts',
		});
		const preLoadFrame = makeWorktreeTreeWindowFrame({
			sequence: 2,
			path: 'src/pre-load-delta.ts',
		});
		const waitForBridgeReady = (callback: () => void): (() => void) => {
			callback();
			return (): void => {};
		};
		const fileViewerProps = {
			loadInitialSurface: async () => ({
				frames: await initialSurfacePromise,
			}),
			subscribeFrames: (subscriber: WorktreeFileFrameSubscriber): (() => void) => {
				publishFrame = subscriber;
				return (): void => {
					publishFrame = null;
				};
			},
		};
		const ObservedFileViewerController = (): ReactElement => {
			const didStartObservationRef = useRef(false);
			const controlledProps = useBridgeFileViewerFrameControllerProps({
				enabled: true,
				fileViewerProps,
				waitForBridgeReady,
			});
			const [loadedFrameKinds, setLoadedFrameKinds] = useState('');
			useEffect((): (() => void) | void => {
				if (didStartObservationRef.current) {
					return;
				}
				didStartObservationRef.current = true;
				void controlledProps?.loadInitialSurface?.().then((surface): void => {
					setLoadedFrameKinds(surface.frames.map((frame) => frame.frameKind).join(','));
				});
				return controlledProps?.subscribeFrames?.((): void => {
					subscriberFrameCount += 1;
				});
			}, [controlledProps]);
			return <output data-testid="merged-frame-kinds">{loadedFrameKinds}</output>;
		};
		const { useBridgeFileViewerFrameControllerProps } =
			await import('./bridge-file-viewer-frame-controller.js');

		render(<ObservedFileViewerController />);
		await expect.poll(() => publishFrame !== null).toBe(true);
		const publishReadyFrame = publishFrame as WorktreeFileFrameSubscriber | null;
		if (publishReadyFrame === null) {
			throw new Error('Expected FileView frame publisher to be registered.');
		}
		publishReadyFrame([preLoadFrame]);
		await waitForBridgeViewerAnimationFrame();
		expect(subscriberFrameCount).toBe(0);

		const resolveReadyInitialSurface = resolveInitialSurface as
			| ((frames: readonly WorktreeFileProtocolFrame[]) => void)
			| null;
		if (resolveReadyInitialSurface === null) {
			throw new Error('Expected FileView initial surface resolver to be registered.');
		}
		resolveReadyInitialSurface([baselineFrame]);

		await expect
			.poll(() => document.querySelector('[data-testid="merged-frame-kinds"]')?.textContent)
			.toBe('worktree.snapshot,worktree.treeWindow');
		expect(subscriberFrameCount).toBe(0);
	});

	test('sends Review metadata interest from the mode controller after native intake', async () => {
		const commandDetails: unknown[] = [];
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
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
		const { BridgeApp } = await import('./bridge-app.js');

		render(<BridgeApp viewerMode="review" />);

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

		await expect
			.poll(() =>
				commandDetails.find(
					(detail) => isRecord(detail) && detail['method'] === 'bridge.metadata_interest.update',
				),
			)
			.toMatchObject({
				method: 'bridge.metadata_interest.update',
				params: {
					protocol: 'review',
					streamId,
					generation: reviewPackage.reviewGeneration,
					itemIds: [reviewPackage.orderedItemIds[0]],
					lane: 'foreground',
				},
			});
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
			.poll(
				() => document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
			)
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
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
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
		const bufferedFrame: WorktreeFileProtocolFrame = {
			kind: 'reset',
			streamId: 'worktree-file:test',
			generation: 1,
			sequence: 0,
			frameKind: 'worktree.reset',
			reason: 'subscriptionReset',
		};
		let loadInitialSurfaceCount = 0;
		// No data-bridge-nonce: the file frame controller waits on bridge-ready, and an
		// unanswered bridge.ready RPC (which a command nonce would require) would never resolve.
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		const { BridgeApp } = await import('./bridge-app.js');
		// A stable fileViewerProps reference keeps the File frame controller from reloading across
		// mode switches. Mode switches are driven by the viewerMode prop because the mocked Review
		// shell does not render the context switcher once the Review projection is active.
		const fileViewerProps = {
			loadInitialSurface: async (): Promise<WorktreeFileInitialSurface> => {
				loadInitialSurfaceCount += 1;
				return { frames: [bufferedFrame] };
			},
		};

		const { rerender } = render(
			<BridgeApp fileViewerProps={fileViewerProps} viewerMode="review" />,
		);

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
		await expect.poll(() => bridgeAppLazyBoundaryMock.projectionApplyCount).toBe(1);

		const reviewModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		const projectionApplyCountBeforeRoundTrip = bridgeAppLazyBoundaryMock.projectionApplyCount;

		// Switch to Files: the File surface loads its initial surface exactly once.
		rerender(<BridgeApp fileViewerProps={fileViewerProps} viewerMode="file" />);
		await expect
			.poll(
				() => document.querySelector('[data-testid="bridge-file-viewer-shell-lazy-mock"]') !== null,
			)
			.toBe(true);
		await expect.poll(() => loadInitialSurfaceCount).toBe(1);
		const fileModeHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
		);
		expect(reviewModeHost.hidden).toBe(true);
		expect(fileModeHost.hidden).toBe(false);

		// Switch back to Review.
		rerender(<BridgeApp fileViewerProps={fileViewerProps} viewerMode="review" />);
		await expect
			.poll(() => {
				const host = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
				return host instanceof HTMLElement && !host.hidden;
			})
			.toBe(true);

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
		expect(loadInitialSurfaceCount).toBe(1);
		// The Review projection was not re-applied across the round trip (no re-apply storm).
		expect(bridgeAppLazyBoundaryMock.projectionApplyCount).toBe(
			projectionApplyCountBeforeRoundTrip,
		);
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

function makeWorktreeSnapshotFrame(props: {
	readonly path: string;
	readonly sequence: number;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'snapshot',
		streamId: 'worktree-file:test',
		generation: 1,
		sequence: props.sequence,
		frameKind: 'worktree.snapshot',
		source: makeWorktreeSourceIdentity(),
		metadataLineage: {
			loadedBy: 'startup_window',
			lane: 'foreground',
		},
		treeRows: [makeWorktreeTreeRow(props.path)],
	};
}

function makeWorktreeTreeWindowFrame(props: {
	readonly path: string;
	readonly sequence: number;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:test',
		generation: 1,
		sequence: props.sequence,
		frameKind: 'worktree.treeWindow',
		projectionIdentity: {
			source: makeWorktreeSourceIdentity(),
			pathScope: [],
			sortKey: 'path',
			groupKey: 'none',
			filterKey: 'all',
			treeWindowKey: 'pre-load-window',
		},
		metadataLineage: {
			loadedBy: 'idle',
			lane: 'idle',
		},
		rows: [makeWorktreeTreeRow(props.path)],
	};
}

function makeWorktreeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-lazy-boundary-test',
		repoId: 'repo-lazy-boundary-test',
		worktreeId: 'worktree-lazy-boundary-test',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-lazy-boundary-test',
	};
}

function makeWorktreeTreeRow(path: string): WorktreeTreeRowMetadata {
	const pathParts = path.split('/');
	return {
		rowId: `row:${path}`,
		path,
		name: pathParts.at(-1) ?? path,
		parentPath: pathParts.length > 1 ? pathParts.slice(0, -1).join('/') : null,
		depth: Math.max(pathParts.length - 1, 0),
		isDirectory: false,
		fileId: `file:${path}`,
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
