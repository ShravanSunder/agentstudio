import { describe, expect, test } from 'vitest';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
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
	test('publishes only complete thread batches and resets detail at the next revision', () => {
		const store = new WorktreeAnnotationProjectionStore();
		store.apply(projectionState(5));
		expect(store.getSnapshot().presentationRevision).toBe(1);
		store.apply(messageBatch(5, false, [messageEntry(secondMessageId, 1)]));

		expect(store.getSnapshot().threads).toEqual([]);
		expect(store.getSnapshot().presentationRevision).toBe(1);

		store.apply(messageBatch(5, true, [messageEntry(firstMessageId, 0)]));
		expect(store.getSnapshot().threads).toEqual([
			expect.objectContaining({
				context: expect.objectContaining({ threadId }),
				messages: [
					expect.objectContaining({ messageId: firstMessageId }),
					expect.objectContaining({ messageId: secondMessageId }),
				],
			}),
		]);
		expect(store.getSnapshot().presentationRevision).toBe(2);

		store.apply(projectionState(6));
		store.apply(messageBatch(5, true, [messageEntry(firstMessageId, 0)]));
		expect(store.getSnapshot()).toMatchObject({ revision: 6, threads: [] });
	});
});

describe('WorktreeAnnotationSurfaceClient', () => {
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
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});
		surface.publish({
			direction: 'serverWorkerToMain',
			event: messageBatch(1, true, [messageEntry(firstMessageId, 0)]),
			kind: 'annotationProjection',
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: 1,
		});

		await expect(detail).resolves.toMatchObject({ context: { threadId } });
		const neverPublished = client.waitForSnapshot(() => null);
		client.dispose();
		await expect(neverPublished).rejects.toThrow('disposed');
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
): Extract<BridgeProductWorktreeAnnotationEvent, { readonly eventKind: 'projection.state' }> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes,
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
				threadId,
			},
			isLastBatchForThread,
			messages,
			revision,
		},
	} as const;
}

function messageEntry(messageId: string, ordinal: number): WorktreeAnnotationMessageEntry {
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
		threadId,
	} as const;
}

class RecordingSurfaceClient {
	readonly #listeners = new Set<(message: BridgeWorkerServerToMainMessage) => void>();
	readonly #renderListeners = new Set<() => void>();
	readonly sentCommands: Array<{
		readonly command: 'annotationCommand';
		readonly epoch: number;
		readonly operation: unknown;
		readonly surface: 'fileView' | 'review';
	}> = [];
	readonly sentInspectionCommands: Array<{
		readonly attemptId: string;
		readonly command: 'annotationOutputInspect';
		readonly epoch: number;
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
