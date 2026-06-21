import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import { createBridgeReviewViewerStore } from '../state/review-viewer-store.js';
import { makeBridgeViewerBrowserFixture } from '../test-support/bridge-viewer-mocked-backend.js';
import { createBridgeReviewProjectionSyncClient } from '../workers/projection/review-projection-sync-client.js';
import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerTransport,
} from '../workers/projection/review-projection-worker-client.js';
import {
	buildBridgeReviewProjectionWorkerSuccessResponse,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from '../workers/projection/review-projection-worker-rpc.js';
import { startBridgeReviewProjectionCoordinatorRequest } from './use-review-projection-coordinator.js';

describe('Bridge review projection coordinator', () => {
	test('uses the sync lane for small interactive packages and flushes telemetry after apply', async () => {
		const store = createBridgeReviewViewerStore();
		const telemetryRecorder = makeTelemetryRecorder();
		const flushForces: Array<boolean | undefined> = [];

		startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage: makeBridgeViewerBrowserFixture({ fixtureClass: 'small-mixed' }).reviewPackage,
			projectionMode: { kind: 'normalReview' },
			facets: [],
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			projectionWorkerClient: null,
			syncProjectionClient: createBridgeReviewProjectionSyncClient({
				createRequestId: (): string => 'sync-small-request',
				now: makeStepClock(),
			}),
			telemetryRecorder,
			telemetryParentTraceContext: null,
			flushTelemetry: (flushProps): void => {
				flushForces.push(flushProps?.force);
			},
		});

		await flushProjectionCoordinatorMicrotasks();

		expect(store.getState().rootSnapshot.projectionStatus).toBe('ready');
		expect(store.getState().workerStatus.lane).toBe('sync');
		expect(store.getState().workerStatus.lastCompletedRequestId).toBe('sync-small-request');
		expect(store.getState().projection?.orderedItemIds.length).toBeGreaterThan(0);
		expect(telemetryRecorder.samples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.trees.projection_build',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.transport': 'worker',
					'agentstudio.bridge.worker.lane': 'none',
				}),
			}),
		]);
		expect(flushForces).toEqual([true]);
	});

	test('uses the worker lane for large packages when a worker client is available', async () => {
		const store = createBridgeReviewViewerStore();
		const telemetryRecorder = makeTelemetryRecorder();
		const deferredWorker = makeDeferredProjectionWorkerClient('worker-large-request');
		const flushForces: Array<boolean | undefined> = [];

		startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage: makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' })
				.reviewPackage,
			projectionMode: { kind: 'normalReview' },
			facets: [],
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			projectionWorkerClient: deferredWorker.client,
			syncProjectionClient: createBridgeReviewProjectionSyncClient(),
			telemetryRecorder,
			telemetryParentTraceContext: null,
			flushTelemetry: (flushProps): void => {
				flushForces.push(flushProps?.force);
			},
		});

		expect(store.getState().rootSnapshot.projectionStatus).toBe('running');
		expect(store.getState().workerStatus.lane).toBe('worker');
		expect(deferredWorker.requests).toHaveLength(1);
		deferredWorker.resolveSuccess(4);
		await flushProjectionCoordinatorMicrotasks();

		expect(store.getState().rootSnapshot.projectionStatus).toBe('ready');
		expect(store.getState().workerStatus.lastCompletedRequestId).toBe('worker-large-request');
		expect(telemetryRecorder.samples[0]?.stringAttributes).toEqual(
			expect.objectContaining({
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.lane': 'projection',
			}),
		);
		expect(flushForces).toEqual([true]);
	});

	test('aborts and ignores a completion after the coordinator request is cleaned up', async () => {
		const store = createBridgeReviewViewerStore();
		const telemetryRecorder = makeTelemetryRecorder();
		const deferredWorker = makeDeferredProjectionWorkerClient('worker-stale-request');
		const cleanup = startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage: makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' })
				.reviewPackage,
			projectionMode: { kind: 'normalReview' },
			facets: [],
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			projectionWorkerClient: deferredWorker.client,
			syncProjectionClient: createBridgeReviewProjectionSyncClient(),
			telemetryRecorder,
			telemetryParentTraceContext: null,
			flushTelemetry: (): void => {
				throw new Error('stale projection completion must not flush telemetry');
			},
		});

		cleanup();
		expect(deferredWorker.abortedKeys).toEqual(['bridge-review-projection']);
		expect(store.getState().rootSnapshot.projectionStatus).toBe('idle');
		expect(store.getState().workerStatus.pendingRequestCount).toBe(0);
		deferredWorker.resolveSuccess(6);
		await flushProjectionCoordinatorMicrotasks();

		expect(store.getState().rootSnapshot.projectionStatus).toBe('idle');
		expect(store.getState().projection).toBeNull();
		expect(telemetryRecorder.samples).toEqual([]);
	});

	test('falls back to the sync lane for large packages when no worker client is available', async () => {
		const store = createBridgeReviewViewerStore();
		const telemetryRecorder = makeTelemetryRecorder();
		let flushCount = 0;

		startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage: makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' })
				.reviewPackage,
			projectionMode: { kind: 'normalReview' },
			facets: [],
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			projectionWorkerClient: null,
			syncProjectionClient: createBridgeReviewProjectionSyncClient({
				createRequestId: (): string => 'sync-large-fallback-request',
				now: makeStepClock(),
			}),
			telemetryRecorder,
			telemetryParentTraceContext: null,
			flushTelemetry: (): void => {
				flushCount += 1;
			},
		});

		await flushProjectionCoordinatorMicrotasks();

		expect(store.getState().rootSnapshot.projectionStatus).toBe('ready');
		expect(store.getState().workerStatus.lane).toBe('sync');
		expect(store.getState().workerStatus.lastCompletedRequestId).toBe(
			'sync-large-fallback-request',
		);
		expect(telemetryRecorder.samples[0]?.stringAttributes).toEqual(
			expect.objectContaining({
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.lane': 'none',
			}),
		);
		expect(flushCount).toBe(1);
	});

	test('marks active projection requests failed when the worker reports failure', async () => {
		const store = createBridgeReviewViewerStore();
		const telemetryRecorder = makeTelemetryRecorder();
		const failingWorker = makeFailingProjectionWorkerClient('worker-failure-request');
		let flushCount = 0;

		startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage: makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' })
				.reviewPackage,
			projectionMode: { kind: 'normalReview' },
			facets: [],
			gitStatusFilter: 'all',
			fileClassFilter: 'all',
			projectionWorkerClient: failingWorker,
			syncProjectionClient: createBridgeReviewProjectionSyncClient(),
			telemetryRecorder,
			telemetryParentTraceContext: null,
			flushTelemetry: (): void => {
				flushCount += 1;
			},
		});

		await flushProjectionCoordinatorMicrotasks();

		expect(store.getState().rootSnapshot.projectionStatus).toBe('failed');
		expect(store.getState().workerStatus.lastCompletedRequestId).toBe('worker-failure-request');
		expect(store.getState().projection).toBeNull();
		expect(telemetryRecorder.samples).toEqual([]);
		expect(flushCount).toBe(0);
	});
});

interface TestTelemetryRecorder extends BridgeTelemetryRecorder {
	readonly samples: BridgeTelemetrySample[];
}

function makeTelemetryRecorder(): TestTelemetryRecorder {
	const samples: BridgeTelemetrySample[] = [];
	return {
		samples,
		isEnabled: (scope: BridgeTelemetryScope): boolean => scope === 'web',
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		flush: (): boolean => true,
	};
}

function makeDeferredProjectionWorkerClient(requestId: string): {
	readonly client: BridgeReviewProjectionWorkerClient;
	readonly requests: readonly BridgeReviewProjectionWorkerRequest[];
	readonly abortedKeys: readonly string[];
	readonly resolveSuccess: (durationMilliseconds: number) => void;
} {
	const requests: BridgeReviewProjectionWorkerRequest[] = [];
	const abortedKeys: string[] = [];
	const deferredResponses = new Map<string, Deferred<BridgeReviewProjectionWorkerResponse>>();
	const transport: BridgeReviewProjectionWorkerTransport = {
		send: (
			request: BridgeReviewProjectionWorkerRequest,
		): Promise<BridgeReviewProjectionWorkerResponse> => {
			requests.push(request);
			const deferredResponse = createDeferred<BridgeReviewProjectionWorkerResponse>();
			deferredResponses.set(request.requestId, deferredResponse);
			return deferredResponse.promise;
		},
		abort: (abortKey: string): void => {
			abortedKeys.push(abortKey);
		},
	};
	return {
		client: createBridgeReviewProjectionWorkerClient({
			transport,
			createRequestId: (): string => requestId,
		}),
		requests,
		abortedKeys,
		resolveSuccess: (durationMilliseconds: number): void => {
			const request = requests[0];
			if (request === undefined) {
				throw new Error('expected projection worker request before resolving');
			}
			deferredResponses.get(request.requestId)?.resolve(
				buildBridgeReviewProjectionWorkerSuccessResponse({
					request,
					durationMilliseconds,
				}),
			);
		},
	};
}

function makeFailingProjectionWorkerClient(requestId: string): BridgeReviewProjectionWorkerClient {
	return createBridgeReviewProjectionWorkerClient({
		createRequestId: (): string => requestId,
		transport: {
			send: async (
				request: BridgeReviewProjectionWorkerRequest,
			): Promise<BridgeReviewProjectionWorkerResponse> => ({
				schemaVersion: 1,
				method: request.method,
				ok: false,
				requestId: request.requestId,
				packageId: request.packageId,
				reviewGeneration: request.reviewGeneration,
				revision: request.revision,
				projectionRequestFingerprint: request.projectionRequestFingerprint,
				abortKey: request.abortKey,
				error: {
					code: 'projectionFailed',
					message: 'test projection failure',
				},
			}),
		},
	});
}

function makeStepClock(): () => number {
	let currentTime = 0;
	return (): number => {
		currentTime += 1;
		return currentTime;
	};
}

async function flushProjectionCoordinatorMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveValue: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolveValue = resolve;
	});
	if (resolveValue === null) {
		throw new Error('Deferred promise handler was not initialized.');
	}

	return {
		promise,
		resolve: resolveValue,
	};
}
