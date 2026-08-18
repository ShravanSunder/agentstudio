import { describe, expect, test } from 'vitest';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from '../core/comm-worker/bridge-product-content-contracts.js';
import type { BridgeProductWorktreeAnnotationEvent } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import {
	createWorktreeAnnotationSurfaceClient,
	WorktreeAnnotationProjectionStore,
	type WorktreeAnnotationMessageEntry,
	type WorktreeAnnotationOutputInspection,
} from './worktree-annotation-surface-client.js';

const sessionId = '00000000-0000-7000-8000-000000000011';
const threadId = '00000000-0000-7000-8000-000000000012';
const firstMessageId = '00000000-0000-7000-8000-000000000013';
const secondMessageId = '00000000-0000-7000-8000-000000000014';

describe('WorktreeAnnotationProjectionStore', () => {
	test('retains the last complete snapshot until every expected thread is terminal', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const notifications: number[] = [];
		store.subscribe((): void => {
			notifications.push(store.getSnapshot().presentationRevision);
		});
		store.apply(projectionState(5), 'producer-a');
		expect(store.getSnapshot().presentationRevision).toBe(0);
		store.apply(messageBatch(5, false, [messageEntry(secondMessageId, 1)]), 'producer-a');

		expect(store.getSnapshot().threads).toEqual([]);
		expect(store.getSnapshot().presentationRevision).toBe(0);
		expect(notifications).toEqual([]);

		store.apply(messageBatch(5, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot().threads).toEqual([
			expect.objectContaining({
				context: expect.objectContaining({ threadId }),
				messages: [
					expect.objectContaining({ messageId: firstMessageId }),
					expect.objectContaining({ messageId: secondMessageId }),
				],
			}),
		]);
		expect(store.getSnapshot().presentationRevision).toBe(1);
		expect(notifications).toEqual([1]);

		store.apply(projectionState(6), 'producer-a');
		store.apply(messageBatch(5, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot()).toMatchObject({ revision: 5 });
		expect(store.getSnapshot().threads).toHaveLength(1);
		expect(notifications).toEqual([1]);

		store.apply(messageBatch(6, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot()).toMatchObject({ revision: 6 });
		expect(notifications).toEqual([1, 2]);
	});

	test('publishes zero-thread revisions immediately and multi-thread revisions once', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const notifications: number[] = [];
		store.subscribe((): void => {
			notifications.push(store.getSnapshot().presentationRevision);
		});
		store.apply(projectionState(1, [], 0), 'producer-a');
		expect(store.getSnapshot()).toMatchObject({ revision: 1, threads: [] });

		store.apply(projectionState(2, [], 2), 'producer-a');
		store.apply(messageBatch(2, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot().revision).toBe(1);
		store.apply(
			messageBatch(2, true, [messageEntry(secondMessageId, 0, 'thread-2')], 'thread-2'),
			'producer-a',
		);
		expect(store.getSnapshot()).toMatchObject({ revision: 2 });
		expect(store.getSnapshot().threads).toHaveLength(2);
		expect(notifications).toEqual([1, 2]);
	});

	test('resets equal active revisions and suppresses equal published replay', () => {
		const store = new WorktreeAnnotationProjectionStore();
		const notifications: number[] = [];
		store.subscribe((): void => {
			notifications.push(store.getSnapshot().presentationRevision);
		});
		store.apply(projectionState(7), 'producer-a');
		store.apply(messageBatch(7, false, [messageEntry(firstMessageId, 0)]), 'producer-a');
		store.apply(projectionState(7), 'producer-a');
		store.apply(messageBatch(7, true, [messageEntry(secondMessageId, 1)]), 'producer-a');

		expect(store.getSnapshot().threads[0]?.messages.map((message) => message.messageId)).toEqual([
			secondMessageId,
		]);
		expect(notifications).toEqual([1]);
		store.apply(projectionState(7), 'producer-a');
		store.apply(messageBatch(7, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(notifications).toEqual([1]);
	});

	test('never merges batches across replacement producers at an equal revision', () => {
		const store = new WorktreeAnnotationProjectionStore();
		store.apply(projectionState(8), 'producer-a');
		store.apply(messageBatch(8, false, [messageEntry(firstMessageId, 0)]), 'producer-a');
		store.apply(projectionState(8), 'producer-b');
		store.apply(messageBatch(8, true, [messageEntry(secondMessageId, 1)]), 'producer-a');
		expect(store.getSnapshot().revision).toBeNull();

		store.apply(messageBatch(8, true, [messageEntry(secondMessageId, 1)]), 'producer-b');
		expect(store.getSnapshot().revision).toBe(8);
		expect(store.getSnapshot().threads[0]?.messages.map((message) => message.messageId)).toEqual([
			secondMessageId,
		]);
	});

	test('abandons invalid duplicate, post-terminal, excess, and mismatched assemblies', () => {
		const invalidSequences = [
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1), 'producer-a');
				store.apply(
					messageBatch(1, true, [messageEntry(firstMessageId, 0), messageEntry(firstMessageId, 1)]),
					'producer-a',
				);
			},
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1), 'producer-a');
				store.apply(
					messageBatch(1, true, [
						messageEntry(firstMessageId, 0),
						messageEntry(secondMessageId, 0),
					]),
					'producer-a',
				);
			},
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1, [], 2), 'producer-a');
				store.apply(messageBatch(1, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
				store.apply(messageBatch(1, true, [messageEntry(secondMessageId, 1)]), 'producer-a');
			},
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1), 'producer-a');
				store.apply(
					messageBatch(1, true, [messageEntry(firstMessageId, 0, 'wrong-thread')]),
					'producer-a',
				);
			},
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1), 'producer-a');
				store.apply(messageBatch(1, false, [messageEntry(firstMessageId, 0)]), 'producer-a');
				const changedContextBatch = messageBatch(1, true, [messageEntry(secondMessageId, 1)]);
				store.apply(
					{
						...changedContextBatch,
						payload: {
							...changedContextBatch.payload,
							context: { ...changedContextBatch.payload.context, endLine: 4 },
						},
					},
					'producer-a',
				);
			},
			(store: WorktreeAnnotationProjectionStore): void => {
				store.apply(projectionState(1), 'producer-a');
				store.apply(messageBatch(1, false, [messageEntry(firstMessageId, 0)]), 'producer-a');
				store.apply(
					messageBatch(1, true, [messageEntry(secondMessageId, 1, 'thread-2')], 'thread-2'),
					'producer-a',
				);
			},
		];

		for (const applyInvalidSequence of invalidSequences) {
			const store = new WorktreeAnnotationProjectionStore();
			applyInvalidSequence(store);
			expect(store.getSnapshot().revision).toBeNull();
		}
	});

	test('classifies every semantic assembly failure and requests recovery once', () => {
		const cases: readonly {
			readonly applyFailure: (store: WorktreeAnnotationProjectionStore) => void;
			readonly expectedFailureClass:
				| 'duplicateTerminal'
				| 'excessThreadCount'
				| 'messageIdentityViolation'
				| 'postTerminalBatch';
		}[] = [
			{
				applyFailure: (store): void => {
					store.apply(projectionState(1, [], 1), 'producer-a');
					store.apply(messageBatch(1, false, [messageEntry(firstMessageId, 0)]), 'producer-a');
					store.apply(
						messageBatch(1, true, [messageEntry(secondMessageId, 0, 'thread-2')], 'thread-2'),
						'producer-a',
					);
				},
				expectedFailureClass: 'excessThreadCount',
			},
			{
				applyFailure: (store): void => {
					store.apply(projectionState(1, [], 2), 'producer-a');
					store.apply(messageBatch(1, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
					store.apply(messageBatch(1, true, [messageEntry(secondMessageId, 1)]), 'producer-a');
				},
				expectedFailureClass: 'duplicateTerminal',
			},
			{
				applyFailure: (store): void => {
					store.apply(projectionState(1, [], 2), 'producer-a');
					store.apply(messageBatch(1, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
					store.apply(messageBatch(1, false, [messageEntry(secondMessageId, 1)]), 'producer-a');
				},
				expectedFailureClass: 'postTerminalBatch',
			},
			{
				applyFailure: (store): void => {
					store.apply(projectionState(1), 'producer-a');
					store.apply(
						messageBatch(1, true, [messageEntry(firstMessageId, 0, 'wrong-thread')]),
						'producer-a',
					);
				},
				expectedFailureClass: 'messageIdentityViolation',
			},
		];

		for (const fixtureCase of cases) {
			const failures: string[] = [];
			const store = new WorktreeAnnotationProjectionStore((failure) => {
				failures.push(failure.failureClass);
				return 'requested';
			});
			fixtureCase.applyFailure(store);
			expect(failures).toEqual([fixtureCase.expectedFailureClass]);
			expect(store.getSnapshot().transportStatus).toMatchObject({
				failureClass: fixtureCase.expectedFailureClass,
				recovery: 'requested',
			});
		}
	});

	test('retains complete threads, exposes unavailable, and accepts a later resync after failure', () => {
		const failures: Array<{
			readonly failureClass: string;
			readonly revision: number;
			readonly subscriptionId: string;
		}> = [];
		const store = new WorktreeAnnotationProjectionStore((failure) => {
			failures.push(failure);
			return failures.length === 1 ? 'requested' : 'blocked';
		});
		store.apply(projectionState(1), 'producer-a');
		store.apply(messageBatch(1, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		store.apply(projectionState(2), 'producer-a');
		store.apply(
			messageBatch(2, true, [messageEntry(secondMessageId, 1, 'wrong-thread')]),
			'producer-a',
		);

		expect(store.getSnapshot()).toMatchObject({
			recoveryStatus: 'available',
			revision: 1,
			transportStatus: {
				failedRevision: 2,
				failureClass: 'messageIdentityViolation',
				kind: 'unavailable',
				recovery: 'requested',
			},
		});
		expect(store.getSnapshot().threads[0]?.messages[0]?.messageId).toBe(firstMessageId);
		expect(failures).toEqual([
			{
				failureClass: 'messageIdentityViolation',
				revision: 2,
				subscriptionId: 'producer-a',
			},
		]);

		store.apply(projectionState(2), 'producer-a');
		store.apply(messageBatch(2, true, [messageEntry(secondMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot().revision).toBe(1);
		store.apply(projectionState(2), 'producer-b');
		store.apply(messageBatch(2, true, [messageEntry(firstMessageId, 0)]), 'producer-a');
		expect(store.getSnapshot().revision).toBe(1);
		store.apply(messageBatch(2, true, [messageEntry(secondMessageId, 0)]), 'producer-b');
		expect(store.getSnapshot()).toMatchObject({
			recoveryStatus: 'available',
			revision: 2,
			transportStatus: { kind: 'available' },
		});
	});

	test('keeps the failed producer barred through stale replacement traffic until complete replay', () => {
		const failures: string[] = [];
		const store = new WorktreeAnnotationProjectionStore((failure) => {
			failures.push(`${failure.subscriptionId}:${failure.revision}`);
			return 'requested';
		});
		store.apply(projectionState(5), 'producer-old');
		store.apply(messageBatch(5, true, [messageEntry(firstMessageId, 0)]), 'producer-old');
		store.apply(projectionState(6), 'producer-old');
		store.apply(
			messageBatch(6, true, [messageEntry(secondMessageId, 0, 'wrong-thread')]),
			'producer-old',
		);

		store.apply(projectionState(4), 'producer-new');
		store.apply(projectionState(7), 'producer-old');
		store.apply(messageBatch(7, true, [messageEntry(secondMessageId, 0)]), 'producer-old');
		expect(store.getSnapshot()).toMatchObject({
			revision: 5,
			transportStatus: { kind: 'unavailable', recovery: 'requested' },
		});
		expect(failures).toEqual(['producer-old:6']);

		store.apply(projectionState(6), 'producer-new');
		store.apply(messageBatch(6, true, [messageEntry(secondMessageId, 0)]), 'producer-new');
		expect(store.getSnapshot()).toMatchObject({
			revision: 6,
			transportStatus: { kind: 'available' },
		});
		store.apply(projectionState(7), 'producer-new');
		store.apply(messageBatch(7, true, [messageEntry(firstMessageId, 0)]), 'producer-new');
		expect(store.getSnapshot()).toMatchObject({ revision: 7 });
		expect(failures).toEqual(['producer-old:6']);
	});
});

describe('WorktreeAnnotationSurfaceClient', () => {
	test('returns candidate pages directly without retaining them in the projection snapshot', async () => {
		const surface = new RecordingSurfaceClient('review');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		const query = {
			cursor: { kind: 'start' as const },
			expectedSessionRevision: 4,
			limit: 16,
			sessionId: '00000000-0000-7000-8000-000000000011',
		};
		const page = {
			candidates: [],
			eligibleMessageCount: 0,
			eligibleWithoutInlinePlacementCount: 0,
			nextCursor: null,
			sessionId: query.sessionId,
			sessionRevision: 4,
		} as const;
		const pending = client.queryOutputCandidates(query);
		surface.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationOutputCandidatesPage',
			page,
			requestId: 'worker-request-1',
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
		});

		await expect(pending).resolves.toEqual(page);
		expect(surface.sentCandidateQueryCommands).toEqual([
			{
				command: 'annotationOutputCandidatesQuery',
				epoch: 1,
				query,
				surface: 'review',
			},
		]);
		expect(JSON.stringify(client.getSnapshot())).not.toContain('candidates');
	});

	test('inspects one output as exact bytes and releases pending ownership after correlation', async () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client) as ReturnType<
			typeof createWorktreeAnnotationSurfaceClient
		> & {
			readonly inspectOutput: (attemptId: string) => Promise<WorktreeAnnotationOutputInspection>;
		};
		const exactBytes = new TextEncoder().encode('# Exact annotation output\n').buffer;
		const descriptor = annotationOutputDescriptor(exactBytes.byteLength);

		const inspection = client.inspectOutput(descriptor.attemptId);
		surface.publish({
			descriptor,
			direction: 'serverWorkerToMain',
			exactBytes,
			kind: 'annotationOutputInspection',
			requestId: 'worker-request-1',
			surface: 'fileView',
			transferDescriptors: [
				{
					byteLength: exactBytes.byteLength,
					fieldPath: ['exactBytes'],
					messageKind: 'annotationOutputInspection',
					mode: 'transfer',
				},
			],
			wireVersion: 1,
		} as BridgeWorkerServerToMainMessage);

		await expect(inspection).resolves.toEqual({
			descriptor,
			exactBytes: new Uint8Array(exactBytes),
		});
		expect(JSON.stringify(client.getSnapshot())).not.toContain('Exact annotation output');
		expect(surface.sentInspectionCommands).toEqual([
			{
				attemptId: descriptor.attemptId,
				command: 'annotationOutputInspect',
				epoch: 1,
				surface: 'fileView',
			},
		]);
	});

	test('rejects pending output inspection through existing degraded and disposal lifecycle', async () => {
		const surface = new RecordingSurfaceClient('review');
		const client = createWorktreeAnnotationSurfaceClient(surface.client) as ReturnType<
			typeof createWorktreeAnnotationSurfaceClient
		> & {
			readonly inspectOutput: (attemptId: string) => Promise<WorktreeAnnotationOutputInspection>;
		};

		const failedInspection = client.inspectOutput('00000000-0000-7000-8000-000000000031');
		surface.publish({
			direction: 'serverWorkerToMain',
			kind: 'health',
			message: 'annotation output unavailable',
			requestId: 'worker-request-1',
			status: 'degraded',
			transferDescriptors: [],
			wireVersion: 1,
		});
		await expect(failedInspection).rejects.toThrow('annotation output unavailable');

		const disposedInspection = client.inspectOutput('00000000-0000-7000-8000-000000000032');
		client.dispose();
		await expect(disposedInspection).rejects.toThrow('disposed');
		await expect(client.inspectOutput('00000000-0000-7000-8000-000000000033')).rejects.toThrow(
			'disposed',
		);
	});

	test('waits for the exact native product request outcome', async () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);

		const outcome = client.execute({ kind: 'session.discover' });
		surface.publish({
			direction: 'serverWorkerToMain',
			kind: 'annotationCommandAccepted',
			productRequestId: 'product-request-1',
			requestId: 'worker-request-1',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});
		surface.publish({
			direction: 'serverWorkerToMain',
			event: projectionState(1, [
				{
					requestId: 'product-request-1',
					sessionId,
					status: { kind: 'committed' },
					surface: 'file',
				},
			]),
			kind: 'annotationProjection',
			subscriptionId: 'producer-a',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});

		await expect(outcome).resolves.toEqual({
			requestId: 'product-request-1',
			sessionId,
			status: { kind: 'committed' },
			surface: 'file',
		});
		expect(surface.sentCommands).toEqual([
			{
				command: 'annotationCommand',
				epoch: 1,
				operation: { kind: 'session.discover' },
				surface: 'fileView',
			},
		]);
	});

	test('reference-counts demand, refreshes placement at the current source epoch, and releases only after the final consumer', () => {
		const surface = new RecordingSurfaceClient('review');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);

		const releaseFirst = client.acquireSession(sessionId);
		const releaseSecond = client.acquireSession(sessionId);
		releaseFirst();
		releaseSecond();
		releaseSecond();

		expect(surface.sentCommands.map((command) => command.operation)).toEqual([
			{ kind: 'demand.acquire', sessionId },
			{ kind: 'source.refresh', sessionId, sourceEpoch: 1 },
			{ kind: 'output.history', sessionId },
			{ kind: 'demand.release', sessionId },
		]);
	});

	test('refreshes each demanded session once when the source epoch advances', () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		const release = client.acquireSession(sessionId);

		surface.publishSourceEpoch(2);
		surface.publishSourceEpoch(2);
		release();
		surface.publishSourceEpoch(3);

		expect(surface.sentCommands.map((command) => command.operation)).toEqual([
			{ kind: 'demand.acquire', sessionId },
			{ kind: 'source.refresh', sessionId, sourceEpoch: 1 },
			{ kind: 'output.history', sessionId },
			{ kind: 'source.refresh', sessionId, sourceEpoch: 2 },
			{ kind: 'demand.release', sessionId },
		]);
	});

	test('waits event-by-event for committed message detail and rejects waiters on disposal', async () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		const detail = client.waitForSnapshot((snapshot) => snapshot.threads[0] ?? null);

		surface.publish({
			direction: 'serverWorkerToMain',
			event: projectionState(1),
			kind: 'annotationProjection',
			subscriptionId: 'producer-a',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});
		surface.publish({
			direction: 'serverWorkerToMain',
			event: messageBatch(1, true, [messageEntry(firstMessageId, 0)]),
			kind: 'annotationProjection',
			subscriptionId: 'producer-a',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});

		await expect(detail).resolves.toMatchObject({ context: { threadId } });
		const neverPublished = client.waitForSnapshot(() => null);
		client.dispose();
		await expect(neverPublished).rejects.toThrow('disposed');
	});

	test('correlates one resync request and restores availability only after complete replay', () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		surface.publishAnnotation(projectionState(1), 'producer-old');
		surface.publishAnnotation(
			messageBatch(1, true, [messageEntry(firstMessageId, 0)]),
			'producer-old',
		);

		surface.publishAnnotation(projectionState(2), 'producer-old');
		surface.publishAnnotation(
			messageBatch(2, true, [messageEntry(secondMessageId, 1, 'wrong-thread')]),
			'producer-old',
		);
		expect(client.getSnapshot()).toMatchObject({
			recoveryStatus: 'available',
			revision: 1,
			transportStatus: { kind: 'unavailable', recovery: 'requested' },
		});
		expect(surface.sentProjectionResyncCommands).toEqual([
			{
				command: 'annotationProjectionResync',
				epoch: 1,
				failureClass: 'messageIdentityViolation',
				revision: 2,
				subscriptionId: 'producer-old',
				surface: 'fileView',
			},
		]);
		expect(surface.sentCommands).toEqual([]);

		surface.publishHealth('worker-request-1', 'ready');
		expect(client.getSnapshot().transportStatus).toMatchObject({ recovery: 'awaitingReplay' });
		surface.publishAnnotation(projectionState(2), 'producer-new');
		expect(client.getSnapshot().transportStatus).toMatchObject({ recovery: 'awaitingReplay' });
		surface.publishAnnotation(
			messageBatch(2, true, [messageEntry(secondMessageId, 0)]),
			'producer-new',
		);
		expect(client.getSnapshot()).toMatchObject({
			revision: 2,
			transportStatus: { kind: 'available' },
		});
	});

	test('does not regress zero-thread completion on late ready and ignores resync after disposal', () => {
		const surface = new RecordingSurfaceClient('review');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		surface.publishAnnotation(projectionState(1), 'review-old');
		surface.publishAnnotation(
			messageBatch(1, true, [messageEntry(firstMessageId, 0, 'wrong-thread')]),
			'review-old',
		);
		surface.publishAnnotation(projectionState(1, [], 0), 'review-new');
		expect(client.getSnapshot().transportStatus).toEqual({ kind: 'available' });
		surface.publishHealth('worker-request-1', 'ready');
		expect(client.getSnapshot().transportStatus).toEqual({ kind: 'available' });

		surface.publishAnnotation(projectionState(2), 'review-new');
		surface.publishAnnotation(
			messageBatch(2, true, [messageEntry(secondMessageId, 0, 'wrong-thread')]),
			'review-new',
		);
		const snapshotAtDisposal = client.getSnapshot();
		client.dispose();
		surface.publishHealth('worker-request-2', 'ready');
		surface.publishAnnotation(projectionState(2, [], 0), 'review-newer');
		expect(client.getSnapshot()).toBe(snapshotAtDisposal);
	});

	test('suppresses same-revision recovery loops and admits one newer attempt', () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		surface.publishAnnotation(projectionState(0, [], 0), 'producer-0');
		for (const producer of ['producer-1', 'producer-2']) {
			surface.publishAnnotation(projectionState(1), producer);
			surface.publishAnnotation(
				messageBatch(1, true, [messageEntry(firstMessageId, 0, 'wrong-thread')]),
				producer,
			);
		}
		expect(surface.sentProjectionResyncCommands).toHaveLength(1);
		expect(client.getSnapshot().transportStatus).toMatchObject({ recovery: 'blocked' });

		surface.publishAnnotation(projectionState(2, [], 0), 'producer-3');
		surface.publishAnnotation(projectionState(3), 'producer-3');
		surface.publishAnnotation(
			messageBatch(3, true, [messageEntry(secondMessageId, 0, 'wrong-thread')]),
			'producer-3',
		);
		expect(surface.sentProjectionResyncCommands).toHaveLength(2);
		surface.publishHealth('worker-request-2', 'degraded');
		expect(client.getSnapshot().transportStatus).toMatchObject({ recovery: 'blocked' });
	});

	test('bars canonical mutations while transport is unavailable', async () => {
		const surface = new RecordingSurfaceClient('fileView');
		const client = createWorktreeAnnotationSurfaceClient(surface.client);
		surface.publishAnnotation(projectionState(1), 'producer-a');
		surface.publishAnnotation(
			messageBatch(1, true, [messageEntry(firstMessageId, 0, 'wrong-thread')]),
			'producer-a',
		);

		await expect(client.execute({ kind: 'recovery.acknowledge' })).rejects.toThrow(
			'projection transport is unavailable',
		);
		expect(surface.sentCommands).toEqual([]);
	});
});

function projectionState(
	revision: number,
	commandOutcomes: readonly {
		readonly requestId: string;
		readonly sessionId: string | null;
		readonly status:
			| { readonly kind: 'committed' }
			| { readonly code: 'conflict'; readonly kind: 'failed' };
		readonly surface: 'file' | 'review';
	}[] = [],
	expectedThreadCount = 1,
): Extract<BridgeProductWorktreeAnnotationEvent, { readonly eventKind: 'projection.state' }> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes,
			expectedThreadCount,
			outputHistory: [],
			recoveryStatus: 'available',
			revision,
			sessions: [],
			worktreeId: 'worktree-1',
		},
	} as const;
}

function messageBatch(
	revision: number,
	isLastBatchForThread: boolean,
	messages: readonly WorktreeAnnotationMessageEntry[],
	contextThreadId = threadId,
): Extract<BridgeProductWorktreeAnnotationEvent, { readonly eventKind: 'message.batch' }> {
	return {
		eventKind: 'message.batch',
		payload: {
			context: {
				diffSide: null,
				endLine: 3,
				path: 'Sources/App.swift',
				placement: 'exact',
				resolution: 'open',
				scope: 'located',
				sourceIdentity: 'source-1',
				sourceRole: 'file',
				startLine: 2,
				threadId: contextThreadId,
			},
			isLastBatchForThread,
			messages,
			revision,
		},
	} as const;
}

function messageEntry(
	messageId: string,
	ordinal: number,
	messageThreadId = threadId,
): WorktreeAnnotationMessageEntry {
	return {
		authorKind: 'human',
		createdAt: ordinal,
		draft: null,
		messageId,
		messageRevision: 1,
		ordinal,
		savedBody: `Message ${ordinal}`,
		savedRevision: 1,
		sessionId,
		sessionRevision: 1,
		status: 'editable',
		threadId: messageThreadId,
	} as const;
}

class RecordingSurfaceClient {
	readonly #listeners = new Set<(message: BridgeWorkerServerToMainMessage) => void>();
	readonly #renderListeners = new Set<() => void>();
	readonly sentCommands: Array<{
		readonly command: 'annotationCommand';
		readonly epoch: number;
		readonly operation: BridgeProductWorktreeAnnotationOperation;
		readonly surface: 'fileView' | 'review';
	}> = [];
	readonly sentInspectionCommands: Array<{
		readonly attemptId: string;
		readonly command: 'annotationOutputInspect';
		readonly epoch: number;
		readonly surface: 'fileView' | 'review';
	}> = [];
	readonly sentCandidateQueryCommands: Array<{
		readonly command: 'annotationOutputCandidatesQuery';
		readonly epoch: number;
		readonly query: {
			readonly cursor:
				| { readonly kind: 'start' }
				| { readonly flatOrdinal: number; readonly kind: 'after'; readonly messageId: string };
			readonly expectedSessionRevision: number;
			readonly limit: number;
			readonly sessionId: string;
		};
		readonly surface: 'fileView' | 'review';
	}> = [];
	readonly sentProjectionResyncCommands: Array<{
		readonly command: 'annotationProjectionResync';
		readonly epoch: number;
		readonly failureClass:
			| 'duplicateTerminal'
			| 'excessThreadCount'
			| 'messageIdentityViolation'
			| 'postTerminalBatch';
		readonly revision: number;
		readonly subscriptionId: string;
		readonly surface: 'fileView' | 'review';
	}> = [];
	readonly client: BridgePaneSurfaceClient;
	#nextRequest = 0;
	#sourceEpoch = 1;

	constructor(surface: 'fileView' | 'review') {
		this.client = {
			lifecycle: {
				getServerSnapshot: () => ({ requestsById: {} }),
				getSnapshot: () => ({ requestsById: {} }),
				subscribe: () => (): void => {},
			},
			renderFulfillmentCoordinator: {} as BridgePaneSurfaceClient['renderFulfillmentCoordinator'],
			renderStore: {
				getSnapshot: () => ({
					fileDisplayFreshness: { epoch: this.#sourceEpoch },
					reviewDisplayFreshness: { epoch: this.#sourceEpoch },
				}),
				subscribe: (listener: () => void): (() => void) => {
					this.#renderListeners.add(listener);
					return (): void => {
						this.#renderListeners.delete(listener);
					};
				},
			} as BridgePaneSurfaceClient['renderStore'],
			send: (command): string => {
				this.#nextRequest += 1;
				if (command.command === 'annotationOutputInspect') {
					this.sentInspectionCommands.push(command);
					return `worker-request-${this.#nextRequest}`;
				}
				if (command.command === 'annotationOutputCandidatesQuery') {
					this.sentCandidateQueryCommands.push(command);
					return `worker-request-${this.#nextRequest}`;
				}
				if (command.command === 'annotationProjectionResync') {
					this.sentProjectionResyncCommands.push(command);
					return `worker-request-${this.#nextRequest}`;
				}
				if (command.command !== 'annotationCommand') {
					throw new Error(`Unexpected command ${command.command}.`);
				}
				this.sentCommands.push(command);
				return `worker-request-${this.#nextRequest}`;
			},
			subscribeMessages: (listener): (() => void) => {
				this.#listeners.add(listener);
				return (): void => {
					this.#listeners.delete(listener);
				};
			},
			surface,
		};
	}

	publish(message: BridgeWorkerServerToMainMessage): void {
		for (const listener of this.#listeners) listener(message);
	}

	publishAnnotation(event: BridgeProductWorktreeAnnotationEvent, subscriptionId: string): void {
		this.publish({
			direction: 'serverWorkerToMain',
			event,
			kind: 'annotationProjection',
			subscriptionId,
			surface: this.client.surface,
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	publishHealth(requestId: string, status: 'degraded' | 'ready'): void {
		this.publish({
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId,
			status,
			transferDescriptors: [],
			wireVersion: 1,
		});
	}

	publishSourceEpoch(sourceEpoch: number): void {
		this.#sourceEpoch = sourceEpoch;
		for (const listener of this.#renderListeners) listener();
	}
}

function annotationOutputDescriptor(
	byteLength: number,
): BridgeProductAnnotationOutputContentDescriptor {
	return {
		attemptId: '00000000-0000-7000-8000-000000000031',
		contentKind: 'annotation.output',
		contentType: 'text/markdown; charset=utf-8',
		declaredByteLength: byteLength,
		descriptorId: 'annotation-output-descriptor-1',
		encoding: 'utf-8',
		expectedSha256: 'a'.repeat(64),
		formatVersion: 1,
		maximumBytes: byteLength,
		outputKind: 'clipboard_markdown',
		surface: 'file',
	};
}
