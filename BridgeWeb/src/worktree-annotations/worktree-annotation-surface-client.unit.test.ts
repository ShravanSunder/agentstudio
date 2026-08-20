import { describe, expect, test, vi } from 'vitest';

import type { BridgeWorkerAnnotationProjectionSnapshot } from '../core/comm-worker/bridge-comm-worker-annotation-projection-decoder.js';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { createBridgeWorkerRpcLifecycleStore } from '../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';
import { WorktreeAnnotationProjectionStore } from './worktree-annotation-projection-store.js';
import { createWorktreeAnnotationSurfaceClient } from './worktree-annotation-surface-client.js';

const sessionId = '00000000-0000-7000-8000-000000000011';
const threadId = '00000000-0000-7000-8000-000000000012';
const messageId = '00000000-0000-7000-8000-000000000013';

describe('worktree annotation finite projection store', () => {
	test('installs one complete finite snapshot atomically', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const listener = vi.fn();
		store.subscribe(listener);

		store.apply(projectionSnapshot(4, 8));

		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.getSnapshot()).toMatchObject({
			presentationRevision: 1,
			revision: 4,
			readStatus: { kind: 'ready' },
			worktreeId: 'worktree-1',
		});
		expect(store.getSnapshot().threads[0]?.messages[0]?.messageId).toBe(messageId);
	});

	test('rejects an older semantic revision without publishing', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const listener = vi.fn();
		store.subscribe(listener);
		store.apply(projectionSnapshot(5, 9));

		store.apply(projectionSnapshot(4, 10));

		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.getSnapshot().revision).toBe(5);
	});

	test('preserves exact command outcomes and cold output history across projection replacement', () => {
		const store = new WorktreeAnnotationProjectionStore();
		store.recordCommandOutcome({
			requestId: 'annotation-request-1',
			sessionId,
			status: { kind: 'committed' },
			surface: 'file',
		});
		store.replaceOutputHistory([
			{
				attemptId: '00000000-0000-7000-8000-000000000021',
				createdAt: 1,
				messageCount: 1,
				outputKind: 'clipboard_markdown',
				repeatedFromAttemptId: null,
				sessionId,
				state: 'succeeded',
				updatedAt: 2,
			},
		]);

		store.apply(projectionSnapshot(6, 11));

		expect(store.getSnapshot().commandOutcomes).toHaveLength(1);
		expect(store.getSnapshot().outputHistory).toHaveLength(1);
	});
});

describe('worktree annotation surface command rendezvous', () => {
	test('sends one typed projection retry for the owning surface', () => {
		const harness = createSurfaceClientHarness();

		harness.client.retryProjection();

		expect(harness.sentCommands).toContainEqual({
			command: 'annotationProjectionRetry',
			epoch: 0,
			surface: 'fileView',
		});
		harness.client.dispose();
	});

	test('exact Save outcome settles while projection transport is unavailable', async () => {
		const harness = createSurfaceClientHarness();
		const save = harness.client.execute({
			editToken: '00000000-0000-7000-8000-000000000014',
			expectedDraftRevision: 1,
			expectedSessionRevision: 2,
			kind: 'draft.save',
			messageId,
			sessionId,
		});

		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationProjectionConvergence',
			state: { kind: 'unavailable', retryable: true },
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});
		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationCommandAccepted',
			outcome: {
				requestId: 'product-save-1',
				sessionId,
				status: { kind: 'committed' },
				surface: 'file',
			},
			productRequestId: 'product-save-1',
			requestId: 'worker-save-1',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		await expect(save).resolves.toMatchObject({
			requestId: 'product-save-1',
			status: { kind: 'committed' },
		});
		expect(harness.client.getSnapshot().readStatus).toEqual({
			kind: 'unavailable',
			retryable: true,
		});
		expect(harness.client.getSnapshot().commandOutcomes).toHaveLength(1);
		harness.client.dispose();
	});

	test('dispose rejects a pending command and ignores its late outcome', async () => {
		const harness = createSurfaceClientHarness();
		const pending = harness.client.execute({ kind: 'session.discover' });

		harness.client.dispose();
		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationCommandAccepted',
			outcome: {
				requestId: 'late-product-request',
				sessionId: null,
				status: { kind: 'committed' },
				surface: 'file',
			},
			productRequestId: 'late-product-request',
			requestId: 'worker-save-1',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		await expect(pending).rejects.toThrow('Annotation surface client is disposed.');
		expect(harness.client.getSnapshot().commandOutcomes).toEqual([]);
	});

	test('bounds unmatched accept, outcome, and degraded-failure correlations', async () => {
		const harness = createSurfaceClientHarness([
			'worker-accepted-0',
			'worker-accepted-1',
			'worker-failure-0',
			'worker-failure-1',
		]);
		for (let index = 0; index < 129; index += 1) {
			harness.publish({
				direction: 'serverWorkerToMain',
				kind: 'annotationCommandAccepted',
				outcome: {
					requestId: `product-orphan-${index.toString()}`,
					sessionId: null,
					status: { kind: 'committed' },
					surface: 'file',
				},
				productRequestId: `product-orphan-${index.toString()}`,
				requestId: `worker-accepted-${index.toString()}`,
				surface: 'fileView',
				transferDescriptors: [],
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			});
			harness.publish({
				direction: 'serverWorkerToMain',
				kind: 'health',
				message: `orphan failure ${index.toString()}`,
				requestId: `worker-failure-${index.toString()}`,
				status: 'degraded',
				transferDescriptors: [],
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			});
		}

		const evictedAccepted = harness.client.execute({ kind: 'session.discover' });
		const retainedAccepted = harness.client.execute({ kind: 'session.discover' });
		const evictedFailure = harness.client.execute({ kind: 'session.discover' });
		const retainedFailure = harness.client.execute({ kind: 'session.discover' });

		await expect(retainedAccepted).resolves.toMatchObject({ requestId: 'product-orphan-1' });
		await expect(retainedFailure).rejects.toThrow('orphan failure 1');
		harness.client.dispose();
		await expect(evictedAccepted).rejects.toThrow('Annotation surface client is disposed.');
		await expect(evictedFailure).rejects.toThrow('Annotation surface client is disposed.');
	});
});

function createSurfaceClientHarness(workerRequestIds: readonly string[] = ['worker-save-1']): {
	readonly client: ReturnType<typeof createWorktreeAnnotationSurfaceClient>;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly sentCommands: Array<Parameters<BridgePaneSurfaceClient['send']>[0]>;
} {
	let listener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	let nextWorkerRequestIndex = 0;
	const sentCommands: Parameters<BridgePaneSurfaceClient['send']>[0][] = [];
	const surfaceClient = {
		lifecycle: createBridgeWorkerRpcLifecycleStore(),
		renderFulfillmentCoordinator: createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (): void => {},
			requestAnimationFrame: (): number => 1,
			sendDisposition: (): void => {},
		}),
		renderStore: createBridgeMainRenderSnapshotStore(),
		send: (command): string => {
			sentCommands.push(command);
			const requestId = workerRequestIds[nextWorkerRequestIndex];
			nextWorkerRequestIndex += 1;
			return requestId ?? `worker-save-${nextWorkerRequestIndex.toString()}`;
		},
		subscribeMessages: (
			nextListener: (message: BridgeWorkerServerToMainMessage) => void,
		): (() => void) => {
			listener = nextListener;
			return (): void => {
				listener = null;
			};
		},
		surface: 'fileView',
	} satisfies BridgePaneSurfaceClient;
	return {
		client: createWorktreeAnnotationSurfaceClient(surfaceClient),
		publish: (message): void => {
			listener?.(message);
		},
		sentCommands,
	};
}

function projectionSnapshot(
	projectionRevision: number,
	sourceGeneration: number,
): BridgeWorkerAnnotationProjectionSnapshot {
	return {
		expectedMessageCount: 1,
		expectedSessionCount: 1,
		expectedThreadCount: 1,
		projectionRevision,
		recoveryStatus: 'available',
		sessions: [
			{
				completedAt: null,
				createdAt: 1,
				eligibleMessageCount: 1,
				eligibleWithoutInlinePlacementCount: 0,
				lifecycle: 'living',
				semanticRevision: projectionRevision,
				sessionId,
				sourceRelationship: 'applicable',
				updatedAt: 2,
			},
		],
		sourceGeneration,
		threads: [
			{
				context: {
					diffSide: null,
					endLine: 4,
					path: 'Sources/App.swift',
					placement: 'exact',
					resolution: 'open',
					scope: 'located',
					sourceIdentity: 'source-1',
					sourceRole: 'file',
					startLine: 3,
					threadId,
				},
				messages: [
					{
						authorKind: 'human',
						createdAt: 2,
						draft: null,
						handled: false,
						messageId,
						messageRevision: 1,
						ordinal: 0,
						savedBody: 'Comment',
						savedRevision: 1,
						sessionId,
						sessionRevision: projectionRevision,
						status: 'locked',
						threadId,
					},
				],
			},
		],
		worktreeId: 'worktree-1',
	};
}
