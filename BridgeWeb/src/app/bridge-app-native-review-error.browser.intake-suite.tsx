import { act } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

import type { BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import type { BridgeFileViewerBrowserTestProductSession } from '../file-viewer/bridge-file-viewer-browser-test-app.js';
import { makeTreeRowsOnlyMetadataEvents } from '../file-viewer/bridge-file-viewer-browser-test-fixtures.js';
import { createBridgeFileViewerBrowserTestCommWorkerTransportFactory } from '../file-viewer/bridge-file-viewer-browser-test-harness.js';
import { BridgeFileViewerRuntimeTransportFactoryProvider } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import {
	actClick,
	chunkedTextResponse,
	createInProcessBridgeReviewWorkerTransportFactory,
	dispatchHostAdmittedReviewIntakeFrame,
	dispatchHostDiffStatus,
	installBridgeReadyHandshake,
	pollWithinAct,
	pollWithinActUntilTruthy,
	recordBridgeSchemeRPCFetch,
	recordBridgeTelemetryBatchFetch,
	telemetrySamplesFromBatches,
} from './bridge-app-native-review-error.browser.test-support.js';
import { BridgeApp } from './bridge-app.js';

describe('BridgeApp native review intake Browser Mode', () => {
	afterEach(() => {
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		terminateBridgePierreWorkerPoolSingletonForTest();
		vi.restoreAllMocks();
	});

	test('keeps review intake readiness local to the comm worker after bridge ready', async () => {
		const commands: BridgeRPCCommand[] = [];
		const workerCommands: BridgeWorkerMainToServerMessage[] = [];
		const handshake = installBridgeReadyHandshake();
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		try {
			render(
				<BridgeApp
					reviewWorkerTransportFactory={createInProcessBridgeReviewWorkerTransportFactory({
						onWorkerCommand: (command): void => {
							workerCommands.push(command);
						},
						sendSchemeRpcCommand: async (command): Promise<void> => {
							commands.push(command);
						},
					})}
				/>,
			);
			await act(async (): Promise<void> => {
				await waitForBridgeViewerAnimationFrame();
			});
			const reviewIntakeReadyCommands = await pollWithinAct({
				getValue: () =>
					workerCommands.filter((command): boolean => command.command === 'reviewIntakeReady'),
				isSatisfied: (value): boolean => value.length > 0,
			});

			expect(reviewIntakeReadyCommands).toEqual([
				expect.objectContaining({
					command: 'reviewIntakeReady',
					protocolId: 'review',
					reason: null,
					streamId: 'review:bridge-app-test-pane',
				}),
			]);
			expect(commands).not.toContainEqual(
				expect.objectContaining({ method: 'bridge.intakeReady' }),
			);
		} finally {
			handshake.dispose();
		}
	});

	test('renders package failure when native review intake publishes an error frame', async () => {
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute(
			'data-bridge-review-stream-id',
			'review:bridge-app-test-pane',
		);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId: 'review:bridge-app-test-pane',
			generation: 1,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId: 'review:bridge-app-test-pane',
				generation: 1,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'query-startup',
			},
		});
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'error',
			streamId: 'review:bridge-app-test-pane',
			generation: 1,
			sequence: 1,
			message: 'loadFailed',
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]'),
		);
		expect(document.body.textContent).toContain('Review metadata unavailable');
		expect(document.body.textContent).toContain('loadFailed');
		expect(document.body.textContent).not.toContain('Waiting for review metadata');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
	});

	test('keeps shared review frame chrome visible while review metadata is loading', async () => {
		const streamId = 'review:bridge-app-test-pane';
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp viewerMode="review" />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: 1,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: 1,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'query-startup',
			},
		});

		await pollWithinActUntilTruthy(() =>
			document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
		);

		const reviewModeHost = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		expect(
			reviewModeHost.querySelector('[data-testid="bridge-viewer-content-topbar"]'),
		).not.toBeNull();
		expect(
			reviewModeHost.querySelector('[data-testid="bridge-viewer-context-switcher"]'),
		).not.toBeNull();
		expect(
			reviewModeHost.querySelector('[data-testid="bridge-review-rail-toolbar"]'),
		).not.toBeNull();
	});

	test('keeps loading shell when diff status is ready before streamed review metadata applies', async () => {
		const streamId = 'review:bridge-app-test-pane';
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'reset',
			streamId,
			generation: 1,
			sequence: 0,
			payload: {
				kind: 'reset',
				streamId,
				generation: 1,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'query-startup',
			},
		});
		await dispatchHostDiffStatus({
			epoch: 1,
			revision: 1,
			status: 'ready',
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
		);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(document.querySelector('[data-testid="review-viewer-shell"]')).toBeNull();
	});

	test('renders metadata failure when native review snapshot descriptors are rejected', async () => {
		const telemetryBatches: BridgeTelemetryBatch[] = [];
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource, init): Promise<Response> => {
			const telemetryResponse = recordBridgeTelemetryBatchFetch(resource, init, telemetryBatches);
			return (
				telemetryResponse ??
				recordBridgeSchemeRPCFetch(resource, init, []) ??
				new Response('unexpected request', { status: 404 })
			);
		});
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		const firstContentDescriptor = snapshotFrame.comparison.contentDescriptors?.[0];
		if (firstContentDescriptor === undefined) {
			throw new Error('Expected snapshot content descriptor');
		}
		const rejectedSnapshotFrame = {
			...snapshotFrame,
			comparison: {
				...snapshotFrame.comparison,
				contentDescriptors: [
					{
						...firstContentDescriptor,
						descriptor: {
							...firstContentDescriptor.descriptor,
							resourceUrl: firstContentDescriptor.descriptor.resourceUrl.replace(
								'?generation=1',
								'?generation=2',
							),
						},
					},
					...(snapshotFrame.comparison.contentDescriptors?.slice(1) ?? []),
				],
			},
		};
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
		await dispatchHostAdmittedReviewIntakeFrame(
			{
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
			},
			{
				telemetryConfig: {
					enabledScopes: ['web'],
					maxSamplesPerBatch: 16,
					maxEncodedBatchBytes: 65_536,
					minimumFlushIntervalMilliseconds: 0,
					endpointUrl: 'agentstudio://telemetry/batch',
					scenario: 'metadata_apply_rejected_snapshot_v1',
				},
			},
		);
		await dispatchHostAdmittedReviewIntakeFrame({
			kind: 'snapshot',
			streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: rejectedSnapshotFrame.sequence,
			payload: rejectedSnapshotFrame,
		});

		requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]'),
		);
		expect(document.body.textContent).toContain('review_metadata_snapshot_rejected');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(telemetrySamplesFromBatches(telemetryBatches)).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.review_metadata_apply',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.result': 'failed',
					'agentstudio.bridge.result_reason': 'snapshot_materializer_rejected',
				}),
			}),
		);
	});

	test('renders the review shell when native review intake publishes streamed metadata', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse(['struct FixtureView {}\n'])
				: new Response('unexpected request', { status: 404 });
		});
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		render(<BridgeApp />);
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

		await pollWithinActUntilTruthy(() =>
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		requireBridgeViewerHTMLElement(document.querySelector('[data-testid="review-viewer-shell"]'));
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).toBeNull();
		expect(document.body.textContent).not.toContain('Waiting for review metadata');
	});

	test('traces review metadata loading surface without blanking shared chrome', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (resource): Promise<Response> => {
			const resourceUrl =
				typeof resource === 'string'
					? resource
					: resource instanceof URL
						? resource.toString()
						: resource.url;
			return resourceUrl.startsWith('agentstudio://resource/review/content/')
				? chunkedTextResponse(['struct ReviewTraceView {}\n'])
				: new Response('unexpected request', { status: 404 });
		});
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

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
		await pollWithinActUntilTruthy(() =>
			document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]'),
		);

		const traceRecorder = installReviewSurfaceTraceRecorder();
		try {
			await dispatchHostAdmittedReviewIntakeFrame({
				kind: 'snapshot',
				streamId,
				generation: reviewPackage.reviewGeneration,
				sequence: snapshotFrame.sequence,
				payload: snapshotFrame,
			});

			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="review-viewer-shell"]'),
			);
			traceRecorder.record('ready');
		} finally {
			traceRecorder.disconnect();
		}

		expect(traceRecorder.entries).toContainEqual(
			expect.objectContaining({
				hasMetadataLoadingShell: true,
				hasSharedChrome: true,
			}),
		);
		expect(traceRecorder.entries).toContainEqual(
			expect.objectContaining({
				hasReviewShell: true,
				hasSharedChrome: true,
			}),
		);
		expect(traceRecorder.entries).not.toContainEqual(
			expect.objectContaining({
				hasEmptyShell: true,
			}),
		);
		expect(
			traceRecorder.entries.every(
				(entry) =>
					entry.hasSharedChrome &&
					(entry.hasMetadataLoadingShell ||
						entry.hasProjectionPendingShell ||
						entry.hasReviewShell),
			),
		).toBe(true);
	});

	test('starts FileView stream when a Review pane switches to Files mode', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const streamId = 'review:bridge-app-test-pane';
		const sourceDiscoveryEvents: string[] = [];
		const handshake = installBridgeReadyHandshake();
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sequence: 1,
			sourceIdentity: reviewPackage.query.queryId,
			streamId,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 80),
		});
		const productSession: BridgeFileViewerBrowserTestProductSession = {
			currentSource: () => {
				sourceDiscoveryEvents.push('file.source.current');
				return availableFileSource();
			},
			initialMetadataEvents: makeTreeRowsOnlyMetadataEvents(),
		};
		const transportFactory = createBridgeFileViewerBrowserTestCommWorkerTransportFactory({
			productSessionRef: { current: productSession },
		});
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);

		try {
			render(
				<BridgeFileViewerRuntimeTransportFactoryProvider transportFactory={transportFactory}>
					<BridgeApp />
				</BridgeFileViewerRuntimeTransportFactoryProvider>,
			);
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
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="review-viewer-shell"]'),
			);
			expect(sourceDiscoveryEvents).toEqual([]);

			await actClick(
				requireBridgeViewerHTMLElement(
					document.querySelector('[data-testid="bridge-viewer-context-file"]'),
				),
			);

			await pollWithinAct({
				getValue: () => sourceDiscoveryEvents,
				isSatisfied: (value) => value.length > 0,
			});
			expect(sourceDiscoveryEvents).toEqual(['file.source.current']);
			expect(
				document
					.querySelector('[data-testid="bridge-app-root"]')
					?.getAttribute('data-bridge-viewer-mode'),
			).toBe('file');
			expect(
				document
					.querySelector('[data-testid="bridge-viewer-mode-host-file"]')
					?.getAttribute('data-bridge-viewer-mode-active'),
			).toBe('true');
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
			);
		} finally {
			handshake.dispose();
		}
	});
});

interface ReviewSurfaceTraceEntry {
	readonly phase: string;
	readonly hasEmptyShell: boolean;
	readonly hasMetadataLoadingShell: boolean;
	readonly hasProjectionPendingShell: boolean;
	readonly hasReviewShell: boolean;
	readonly hasSharedChrome: boolean;
}

function installReviewSurfaceTraceRecorder(): {
	readonly entries: readonly ReviewSurfaceTraceEntry[];
	readonly disconnect: () => void;
	readonly record: (phase: string) => void;
} {
	const entries: ReviewSurfaceTraceEntry[] = [];
	let lastSignature = '';
	const record = (phase: string): void => {
		const entry = reviewSurfaceTraceEntry(phase);
		const signature = JSON.stringify(entry);
		if (signature === lastSignature) {
			return;
		}
		lastSignature = signature;
		entries.push(entry);
	};
	const observer = new MutationObserver((): void => {
		record('mutation');
	});
	observer.observe(document.body, {
		attributes: true,
		childList: true,
		subtree: true,
	});
	record('initial');
	return {
		entries,
		disconnect: (): void => {
			observer.disconnect();
		},
		record,
	};
}

function reviewSurfaceTraceEntry(phase: string): ReviewSurfaceTraceEntry {
	const reviewModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
	return {
		phase,
		hasEmptyShell: document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null,
		hasMetadataLoadingShell:
			document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') !== null,
		hasProjectionPendingShell:
			document.querySelector('[data-testid="bridge-review-projection-pending-shell"]') !== null,
		hasReviewShell: document.querySelector('[data-testid="review-viewer-shell"]') !== null,
		hasSharedChrome:
			reviewModeHost?.querySelector('[data-testid="bridge-viewer-content-topbar"]') !== null &&
			reviewModeHost?.querySelector('[data-testid="bridge-viewer-context-switcher"]') !== null &&
			reviewModeHost?.querySelector('[data-testid="bridge-review-rail-toolbar"]') !== null,
	};
}

function availableFileSource(): ReturnType<
	NonNullable<BridgeFileViewerBrowserTestProductSession['currentSource']>
> {
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
}
