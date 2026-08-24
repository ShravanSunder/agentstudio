import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerRenderDispositionCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	activateBridgeCommWorkerFileViewerModeAndFlush,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	type PostedBridgeWorkerRuntimeMessage,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeWorkerFilePierreRenderJobEvent } from './bridge-worker-contracts.js';
import { bridgeWorkerRenderDispositionReceiptSchema } from './bridge-worker-render-fulfillment.js';
import {
	drainFilePreparationUntilIdle,
	fileProductTestSource,
	fileViewProductTestBudget,
	makeDescriptorReadyEvent,
	makeFileProductTestTransport,
	makeTreeWindowEvent,
} from './comm-runtime-protocol.file-product.test-support.js';

describe('Bridge comm worker existing File owner backpressure', () => {
	test('keeps B waiting through A queued and applied, then starts B after A painted', async () => {
		const harness = await createFileBackpressureHarness();
		const publicationA = requireFilePublication(harness.postedMessages, 0);

		selectFile(harness, 2, 'selection-b');
		await flushBridgeWorkerRuntimeContinuations();
		expect(filePublications(harness.postedMessages)).toHaveLength(1);

		dispatchFileDisposition(harness, publicationA, 'queued', 'a-queued');
		dispatchFileDisposition(harness, publicationA, 'applied', 'a-applied');
		await drainFilePreparationUntilIdle(harness.scheduledDrains);
		expect(filePublications(harness.postedMessages)).toHaveLength(1);

		dispatchFileDisposition(harness, publicationA, 'painted', 'a-painted');
		await drainFilePreparationUntilIdle(harness.scheduledDrains);

		const publicationB = requireFilePublication(harness.postedMessages, 1);
		expect(publicationB.renderReceiptIdentity.operationCorrelationId).not.toBe(
			publicationA.renderReceiptIdentity.operationCorrelationId,
		);
	});

	test('applies no File owner effect when the correlated response post throws', async () => {
		const harness = await createFileBackpressureHarness('throw-response');
		const publicationA = requireFilePublication(harness.postedMessages, 0);
		selectFile(harness, 2, 'selection-b-after-throw');
		await flushBridgeWorkerRuntimeContinuations();

		expect((): void => {
			dispatchFileDisposition(harness, publicationA, 'painted', 'throw-response');
		}).toThrow('injected correlated response failure');
		await drainFilePreparationUntilIdle(harness.scheduledDrains);

		expect(filePublications(harness.postedMessages)).toHaveLength(1);
	});

	test.each(['rejected', 'superseded'] as const)(
		'starts waiting File B after A is terminally %s',
		async (disposition) => {
			const harness = await createFileBackpressureHarness();
			const publicationA = requireFilePublication(harness.postedMessages, 0);
			selectFile(harness, 2, `selection-b-after-${disposition}`);
			await flushBridgeWorkerRuntimeContinuations();

			dispatchTerminalFileDisposition(harness, publicationA, disposition);
			await drainFilePreparationUntilIdle(harness.scheduledDrains);

			expect(filePublications(harness.postedMessages)).toHaveLength(2);
		},
	);
});

interface FileBackpressureHarness {
	readonly dispatch: ReturnType<typeof createRecordingBridgeCommWorkerPort>['dispatch'];
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
}

async function createFileBackpressureHarness(
	throwForRequestId?: string,
): Promise<FileBackpressureHarness> {
	const events = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'file.metadata'>
	>(64);
	const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
	const subscription: BridgeProductSubscription<'file.metadata'> = {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: 'file-subscription-existing-owner-backpressure',
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
	const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort({
		beforePostMessage: (message): void => {
			if (message.kind === 'health' && message.requestId === throwForRequestId) {
				throw new Error('injected correlated response failure');
			}
		},
	});
	registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		fileViewBudget: fileViewProductTestBudget,
		productTransport: makeFileProductTestTransport({
			onDiscoverSource: (): void => {},
			onOpenDescriptor: (): void => {},
			subscription,
		}),
		schedulePreparationDrain: (drain): void => {
			scheduledDrains.push(drain);
		},
	});
	await activateBridgeCommWorkerFileViewerModeAndFlush(dispatch, 'existing-owner-backpressure');
	events.push({ eventKind: 'file.sourceAccepted', source: fileProductTestSource });
	events.push(makeTreeWindowEvent());
	events.push(makeDescriptorReadyEvent());
	await flushBridgeWorkerRuntimeContinuations();
	const harness = { dispatch, postedMessages, scheduledDrains };
	selectFile(harness, 1, 'selection-a');
	await drainFilePreparationUntilIdle(scheduledDrains);
	requireFilePublication(postedMessages, 0);
	return harness;
}

function selectFile(harness: FileBackpressureHarness, epoch: number, requestLabel: string): void {
	harness.dispatch.message(
		encodeBridgeWorkerSelectCommand({
			epoch,
			requestId: `request-${requestLabel}`,
			selectedItemId: 'file-1',
			selectedSource: 'user',
			surface: 'fileView',
		}),
	);
}

function dispatchFileDisposition(
	harness: FileBackpressureHarness,
	publication: BridgeWorkerFilePierreRenderJobEvent,
	disposition: 'queued' | 'applied' | 'painted',
	requestId: string,
): void {
	harness.dispatch.message(
		encodeBridgeWorkerRenderDispositionCommand({
			epoch: publication.workerDerivationEpoch,
			receipts: [
				bridgeWorkerRenderDispositionReceiptSchema.parse({
					...publication.renderReceiptIdentity,
					disposition,
					kind: 'render.disposition',
					receivedAtMilliseconds: 0,
				}),
			],
			requestId,
		}),
	);
}

function dispatchTerminalFileDisposition(
	harness: FileBackpressureHarness,
	publication: BridgeWorkerFilePierreRenderJobEvent,
	disposition: 'rejected' | 'superseded',
): void {
	harness.dispatch.message(
		encodeBridgeWorkerRenderDispositionCommand({
			epoch: publication.workerDerivationEpoch,
			receipts: [
				bridgeWorkerRenderDispositionReceiptSchema.parse({
					...publication.renderReceiptIdentity,
					disposition,
					kind: 'render.disposition',
					reason: 'stale_attempt',
					receivedAtMilliseconds: 0,
					retryAtMilliseconds: 0,
				}),
			],
			requestId: `request-a-${disposition}`,
		}),
	);
}

function filePublications(
	postedMessages: readonly PostedBridgeWorkerRuntimeMessage[],
): readonly BridgeWorkerFilePierreRenderJobEvent[] {
	return postedMessages.flatMap(({ message }) =>
		message.kind === 'filePierreRenderJob' ? [message] : [],
	);
}

function requireFilePublication(
	postedMessages: readonly PostedBridgeWorkerRuntimeMessage[],
	index: number,
): BridgeWorkerFilePierreRenderJobEvent {
	const publication = filePublications(postedMessages)[index];
	if (publication === undefined) throw new Error(`Expected File publication ${index + 1}.`);
	return publication;
}
