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
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import { WorktreeAnnotationProjectionStore } from './worktree-annotation-projection-store.js';
import {
	createWorktreeAnnotationSurfaceClient,
	type WorktreeAnnotationOutputHistorySummary,
} from './worktree-annotation-surface-client.js';

const sessionId = '00000000-0000-7000-8000-000000000011';
const siblingSessionId = '00000000-0000-7000-8000-000000000014';
const threadId = '00000000-0000-7000-8000-000000000012';
const messageId = '00000000-0000-7000-8000-000000000013';

describe('worktree annotation finite projection store', () => {
	test('installs one complete finite snapshot atomically', () => {
		const store = new WorktreeAnnotationProjectionStore();
		stageCatalog(store, 4);
		const listener = vi.fn();
		store.subscribe(listener);

		store.apply(projectionSnapshot(4, 8), 'a'.repeat(64));

		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.getSnapshot()).toMatchObject({
			presentationRevision: 2,
			revision: 4,
			readStatus: { kind: 'ready' },
			worktreeId: 'worktree-1',
		});
		expect(store.getSnapshot().threads[0]?.messages[0]?.messageId).toBe(messageId);
	});

	test('rejects an older semantic revision without publishing', () => {
		const store = new WorktreeAnnotationProjectionStore();
		stageCatalog(store, 5);
		const listener = vi.fn();
		store.subscribe(listener);
		store.apply(projectionSnapshot(5, 9), 'a'.repeat(64));

		store.apply(projectionSnapshot(4, 10), 'a'.repeat(64));

		expect(listener).toHaveBeenCalledTimes(1);
		expect(store.getSnapshot().revision).toBe(5);
	});

	test('preserves exact command outcomes and cold output history across projection replacement', () => {
		const store = new WorktreeAnnotationProjectionStore();
		stageCatalog(store, 6);
		store.recordCommandOutcome({
			requestId: 'annotation-request-1',
			sessionId,
			status: { kind: 'committed' },
			surface: 'file',
		});
		store.replaceOutputHistory([
			{
				attemptId: '00000000-0000-7000-8000-000000000021',
				canMarkNotHandled: true,
				createdAt: 1,
				messageCount: 1,
				outputKind: 'clipboard_markdown',
				repeatedFromAttemptId: null,
				sessionId,
				state: 'succeeded',
				updatedAt: 2,
			},
		]);

		store.apply(projectionSnapshot(6, 11), 'a'.repeat(64));

		expect(store.getSnapshot().commandOutcomes).toHaveLength(1);
		expect(store.getSnapshot().outputHistory).toHaveLength(1);
	});

	test('preserves demanded rich content across an empty-demand control refresh', () => {
		const store = new WorktreeAnnotationProjectionStore();
		stageCatalog(store, 6);
		store.apply(projectionSnapshot(6, 11), 'a'.repeat(64), [sessionId]);

		store.apply(
			{
				...projectionSnapshot(7, 11),
				expectedMessageCount: 0,
				expectedThreadCount: 0,
				threads: [],
			},
			'a'.repeat(64),
			[],
		);

		expect(store.getSnapshot().threads[0]?.messages[0]?.messageId).toBe(messageId);
		expect(store.getSnapshot().readStatus).toEqual({ kind: 'ready' });
	});

	test('retires removed-session rich content and output history at catalog commit', () => {
		const store = new WorktreeAnnotationProjectionStore();
		stageCatalog(store, 6);
		store.apply(projectionSnapshot(6, 11), 'a'.repeat(64), [sessionId]);
		store.replaceOutputHistory([outputHistorySummary(sessionId, '21')]);

		for (const message of catalogStagingMessages(7, 'fileView', false)) {
			store.applyCatalogStaging(message);
		}

		expect(store.getSnapshot().threads).toEqual([]);
		expect(store.getSnapshot().outputHistory).toEqual([]);
		expect(store.getSnapshot().readStatus).toEqual({ kind: 'refreshing' });
	});

	test('merges cold output history by demanded session', () => {
		const store = new WorktreeAnnotationProjectionStore();
		store.replaceOutputHistoryForSession(sessionId, [outputHistorySummary(sessionId, '21')]);

		store.replaceOutputHistoryForSession(siblingSessionId, [
			outputHistorySummary(siblingSessionId, '22'),
		]);

		expect(store.getSnapshot().outputHistory.map((summary) => summary.sessionId)).toEqual([
			sessionId,
			siblingSessionId,
		]);
	});
});

describe('worktree annotation surface command rendezvous', () => {
	test('rejects Review commands asynchronously until a publication is installed', async () => {
		// Arrange
		const harness = createSurfaceClientHarness(['worker-review-command'], 'review', false);

		// Act
		const pending = harness.client.execute({ kind: 'session.discover' });

		// Assert
		await expect(pending).rejects.toThrow('no installed publication identity');
		expect(harness.sentCommands).toEqual([]);
		harness.client.dispose();
	});

	test('stamps every Review command with the exact active publication identity', async () => {
		const harness = createSurfaceClientHarness(['worker-review-command'], 'review');

		const pending = harness.client.execute({ kind: 'session.discover' });

		expect(harness.sentCommands).toContainEqual({
			command: 'annotationCommand',
			epoch: 0,
			operation: { kind: 'session.discover' },
			reviewPublicationIdentity: reviewPublicationIdentity,
			surface: 'review',
		});
		harness.client.dispose();
		await expect(pending).rejects.toThrow('Annotation surface client is disposed.');
	});

	test('records main-thread install with the exact projection correlation', () => {
		const harness = createSurfaceClientHarness();

		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationProjectionConvergence',
			operationCorrelationId: 'a'.repeat(64),
			state: {
				contentSessionIds: [sessionId],
				kind: 'ready',
				snapshot: projectionSnapshot(7, 12),
			},
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		expect(harness.telemetrySamples).toHaveLength(2);
		expect(harness.telemetrySamples[0]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.operation.id': 'a'.repeat(64),
			'agentstudio.bridge.phase': 'projection_store_terminal',
			'agentstudio.bridge.result': 'success',
		});
		expect(harness.telemetrySamples[1]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.operation.id': 'a'.repeat(64),
			'agentstudio.bridge.phase': 'main_thread_install_terminal',
			'agentstudio.bridge.result': 'success',
		});
		harness.client.dispose();
	});

	test('refreshes cold history for every demanded session after projection convergence', () => {
		const harness = createSurfaceClientHarness();
		const releaseSession = harness.client.acquireSession(sessionId);
		harness.sentCommands.length = 0;

		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationProjectionConvergence',
			operationCorrelationId: 'a'.repeat(64),
			state: {
				contentSessionIds: [sessionId],
				kind: 'ready',
				snapshot: projectionSnapshot(7, 12),
			},
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		expect(harness.sentCommands).toContainEqual({
			command: 'annotationCommand',
			epoch: 0,
			operation: { kind: 'output.history', sessionId },
			surface: 'fileView',
		});
		releaseSession();
		harness.client.dispose();
	});

	test('does not refresh rich output history after a control-only projection', () => {
		const harness = createSurfaceClientHarness();
		const releaseSession = harness.client.acquireSession(sessionId);
		harness.sentCommands.length = 0;

		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationProjectionConvergence',
			operationCorrelationId: 'a'.repeat(64),
			state: {
				contentSessionIds: [],
				kind: 'ready',
				snapshot: { ...projectionSnapshot(7, 12), threads: [] },
			},
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		expect(harness.sentCommands).not.toContainEqual(
			expect.objectContaining({ operation: { kind: 'output.history', sessionId } }),
		);
		expect(harness.client.getSnapshot().readStatus).toEqual({ kind: 'refreshing' });
		releaseSession();
		harness.client.dispose();
	});

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
			expectedMessageRevision: 2,
			kind: 'draft.save',
			messageId,
			sessionId,
		});

		harness.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationProjectionConvergence',
			operationCorrelationId: null,
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

function createSurfaceClientHarness(
	workerRequestIds: readonly string[] = ['worker-save-1'],
	surface: 'fileView' | 'review' = 'fileView',
	hasInstalledReviewIdentity = true,
): {
	readonly client: ReturnType<typeof createWorktreeAnnotationSurfaceClient>;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly sentCommands: Array<Parameters<BridgePaneSurfaceClient['send']>[0]>;
	readonly telemetrySamples: BridgeTelemetrySample[];
} {
	let listener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	let nextWorkerRequestIndex = 0;
	let catalogStaged = false;
	const sentCommands: Parameters<BridgePaneSurfaceClient['send']>[0][] = [];
	const telemetrySamples: BridgeTelemetrySample[] = [];
	const renderStore = createBridgeMainRenderSnapshotStore();
	if (surface === 'review' && hasInstalledReviewIdentity) {
		Object.defineProperty(renderStore, 'getReviewRefreshPresentation', {
			value: () => ({ activeIdentity: reviewMainIdentity, candidate: null }),
		});
	}
	const surfaceClient = {
		lifecycle: createBridgeWorkerRpcLifecycleStore(),
		renderFulfillmentCoordinator: createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (): void => {},
			requestAnimationFrame: (): number => 1,
			sendDisposition: (): void => {},
		}),
		renderStore,
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
		surface,
	} satisfies BridgePaneSurfaceClient;
	return {
		client: createWorktreeAnnotationSurfaceClient(surfaceClient, {
			flush: (): boolean => true,
			isEnabled: (): boolean => true,
			measure: (props) => props.operation(),
			record: (sample): void => {
				telemetrySamples.push(sample);
			},
		}),
		publish: (message): void => {
			if (
				!catalogStaged &&
				message.kind === 'annotationProjectionConvergence' &&
				message.state.kind === 'ready'
			) {
				catalogStaged = true;
				for (const catalogMessage of catalogStagingMessages(
					message.state.snapshot.projectionRevision,
					surface,
				)) {
					listener?.(catalogMessage);
				}
			}
			listener?.(message);
		},
		sentCommands,
		telemetrySamples,
	};
}

function stageCatalog(store: WorktreeAnnotationProjectionStore, catalogRevision: number): void {
	for (const message of catalogStagingMessages(catalogRevision, 'fileView')) {
		store.applyCatalogStaging(message);
	}
}

function catalogStagingMessages(
	catalogRevision: number,
	surface: 'fileView' | 'review',
	includeSession = true,
): readonly Extract<
	BridgeWorkerServerToMainMessage,
	{ readonly kind: 'annotationCatalogStaging' }
>[] {
	const authority = {
		subscriptionId: `${surface}-annotation-subscription-1`,
		workerDerivationEpoch: 1,
		worktreeId: 'worktree-1',
	} as const;
	const transferId = `${surface}-annotation-catalog-${catalogRevision}`;
	const entries = includeSession
		? [
				{ kind: 'session' as const, semanticRevision: catalogRevision, sessionId },
				{
					createdOrdinal: 0,
					kind: 'thread' as const,
					scope: 'located' as const,
					sessionId,
					threadId,
				},
				{ kind: 'message' as const, messageId, ordinal: 0, threadId },
			]
		: [];
	const common = {
		authority,
		direction: 'serverWorkerToMain' as const,
		kind: 'annotationCatalogStaging' as const,
		operationCorrelationId: 'a'.repeat(64),
		surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
	return [
		{
			...common,
			transfer: {
				catalogRevision,
				expectedEntryCount: entries.length,
				kind: 'catalog.begin',
				transferId,
			},
		},
		...(entries.length === 0
			? []
			: [
					{
						...common,
						transfer: {
							catalogRevision,
							entries,
							kind: 'catalog.window' as const,
							transferId,
							windowOrdinal: 0,
						},
					},
				]),
		{
			...common,
			transfer: {
				catalogRevision,
				entryCount: entries.length,
				kind: 'catalog.commit',
				transferId,
				windowCount: entries.length === 0 ? 0 : 1,
			},
		},
	];
}

const reviewPublicationIdentity = {
	packageId: 'package-installed',
	publicationId: '00000000-0000-7000-8000-000000000041',
	reviewGeneration: 7,
	revision: 3,
	sourceIdentity: 'source-installed',
} as const;

const reviewMainIdentity = {
	generation: reviewPublicationIdentity.reviewGeneration,
	packageId: reviewPublicationIdentity.packageId,
	publicationId: reviewPublicationIdentity.publicationId,
	revision: reviewPublicationIdentity.revision,
	sourceIdentity: reviewPublicationIdentity.sourceIdentity,
} as const;

function outputHistorySummary(
	outputSessionId: string,
	attemptSuffix: string,
): WorktreeAnnotationOutputHistorySummary {
	return {
		attemptId: `00000000-0000-7000-8000-0000000000${attemptSuffix}`,
		canMarkNotHandled: true,
		createdAt: 1,
		messageCount: 1,
		outputKind: 'clipboard_markdown',
		repeatedFromAttemptId: null,
		sessionId: outputSessionId,
		state: 'succeeded',
		updatedAt: 2,
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
						attentionState: 'not_applicable',
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
						threadRevision: 1,
					},
				],
			},
		],
		worktreeId: 'worktree-1',
	};
}
