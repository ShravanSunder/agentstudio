import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerFileDisplayResyncCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import { parseBridgeWorkerFileDisplayPatchEvent } from './bridge-worker-contract-parsers.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerFilePierreRenderJobEvent,
	BridgeWorkerFileRenderPatchEvent,
} from './bridge-worker-contracts.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge comm worker File product runtime', () => {
	test('default scheduler opens selected File content after sustained viewport churn', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const openedDescriptorIds: string[] = [];
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-default-scheduler',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			fileViewBudget: {
				className: 'interactive',
				maxBytes: 2 * 1024 * 1024,
				maxWindowLines: 10_000,
			},
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (descriptorId): void => {
					openedDescriptorIds.push(descriptorId);
				},
				subscription,
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		events.push(makeDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();
		expect(openedDescriptorIds).toEqual([]);

		// Act
		for (let viewportIndex = 0; viewportIndex < 64; viewportIndex += 1) {
			dispatch.message(
				encodeBridgeWorkerViewportCommand({
					epoch: viewportIndex + 1,
					firstVisibleIndex: 0,
					lastVisibleIndex: 0,
					phase: viewportIndex === 63 ? 'settled' : 'momentum',
					requestId: `request-default-scheduler-viewport-${viewportIndex}`,
					surface: 'fileView',
					visibleItemIds: ['file-1'],
				}),
			);
		}
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 65,
				requestId: 'request-default-scheduler-select',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(openedDescriptorIds).toEqual(['descriptor-file-1']);
	});

	test('keeps File content demand eligible after concurrent Review source acceptance', async () => {
		// Arrange
		const fileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const reviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const openedDescriptorIds: string[] = [];
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const fileSubscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events: fileEvents,
			subscriptionId: 'file-subscription-cross-surface-store-isolation',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			fileViewBudget: {
				className: 'interactive',
				maxBytes: 2 * 1024 * 1024,
				maxWindowLines: 10_000,
			},
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (descriptorId): void => {
					openedDescriptorIds.push(descriptorId);
				},
				reviewEvents,
				subscription: fileSubscription,
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		await flushBridgeWorkerRuntimeContinuations();
		fileEvents.push({ eventKind: 'file.sourceAccepted', source });
		fileEvents.push(makeTreeWindowEvent());
		fileEvents.push(makeDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();
		reviewEvents.push({
			eventKind: 'review.sourceAccepted',
			generation: 1,
			packageId: 'review-package-cross-surface-store-isolation',
			publicationId: '00000000-0000-7000-8000-000000000001',
			revision: 1,
			sourceIdentity: 'review-source-cross-surface-store-isolation',
		});
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(0);

		// Act
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 1,
				requestId: 'request-select-file-after-review-source-acceptance',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const pendingDrainCompletions: ReturnType<BridgeCommWorkerPreparationDrain>[] = [];
		while (scheduledDrains.length > 0) {
			const drain = scheduledDrains.shift();
			if (drain === undefined) break;
			pendingDrainCompletions.push(drain());
			await flushBridgeWorkerRuntimeContinuations();
		}
		await Promise.all(pendingDrainCompletions);

		// Assert
		expect(
			openedDescriptorIds,
			'FILE_REVIEW_STORE_ISOLATION_FAILED: Review source acceptance removed demand-eligible File metadata.',
		).toEqual(['descriptor-file-1']);
	});

	test('projects File subscription events and opens demanded content without a main relay', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const updatedInterests: unknown[] = [];
		const openedDescriptorIds: string[] = [];
		let sourceDiscoveryCount = 0;
		const createdSequences: number[] = [];
		let nextSequence = 100;
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				updatedInterests.push(options);
			},
		};
		const productTransport = makeProductTransport({
			onDiscoverSource: (): void => {
				sourceDiscoveryCount += 1;
			},
			onOpenDescriptor: (descriptorId): void => {
				openedDescriptorIds.push(descriptorId);
			},
			subscription,
		});
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			createSequence: (): number => {
				const sequence = nextSequence;
				nextSequence += 1;
				createdSequences.push(sequence);
				return sequence;
			},
			fileViewBudget: {
				className: 'interactive',
				maxBytes: 2 * 1024 * 1024,
				maxWindowLines: 10_000,
			},
			productTransport,
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});

		// Act
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 1,
				requestId: 'request-select-file-1',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		await flushBridgeWorkerRuntimeContinuations();
		events.push(makeDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();
		const firstDrain = scheduledDrains.shift();
		if (firstDrain === undefined) throw new Error('Expected selected File preparation drain.');
		const firstDrainCompletion = firstDrain();
		await flushBridgeWorkerRuntimeContinuations();
		const secondDrain = scheduledDrains.shift();
		if (secondDrain === undefined) throw new Error('Expected resumed File preparation drain.');
		await secondDrain();
		await firstDrainCompletion;

		// Assert
		expect(updatedInterests).toEqual([
			{
				interests: [{ lane: 'foreground', paths: ['Sources/File.swift'] }],
				pathScope: [],
			},
		]);
		expect(openedDescriptorIds).toEqual(['descriptor-file-1']);
		expect(sourceDiscoveryCount).toBe(1);
		expect(postedMessages.map(({ message }) => message.kind)).toContain('filePierreRenderJob');
		expect(postedMessages.map(({ message }) => message.kind)).toContain('fileRenderPatch');
		const fileRenderPublications = postedMessages
			.map(({ message }) => message)
			.filter(
				(
					message,
				): message is BridgeWorkerFilePierreRenderJobEvent | BridgeWorkerFileRenderPatchEvent =>
					message.kind === 'filePierreRenderJob' ||
					(message.kind === 'fileRenderPatch' &&
						message.patches.some((patch): boolean => patch.slice !== 'panelChrome')),
			);
		expect(fileRenderPublications).toHaveLength(2);
		expect(
			fileRenderPublications.map((publication) => ({
				surface: publication.surface,
				workerDerivationEpoch: publication.workerDerivationEpoch,
			})),
		).toEqual([
			{ surface: 'file', workerDerivationEpoch: 1 },
			{ surface: 'file', workerDerivationEpoch: 1 },
		]);
		const fileRenderPublicationSequences = fileRenderPublications.map(
			(publication) => publication.publicationSequence,
		);
		expect(new Set(fileRenderPublicationSequences).size).toBe(1);
		expect(createdSequences).toContain(fileRenderPublicationSequences[0]);
		const fileDisplayPatchEvents = postedMessages
			.filter(
				(
					posted,
				): posted is typeof posted & { readonly message: BridgeWorkerFileDisplayPatchEvent } =>
					posted.message.kind === 'fileDisplayPatch',
			)
			.map(({ message }) => parseBridgeWorkerFileDisplayPatchEvent(message));
		expect(fileDisplayPatchEvents).toHaveLength(4);
		expect(fileDisplayPatchEvents.map((event) => event.epoch)).toEqual([1, 1, 1, 1]);
		expect(fileDisplayPatchEvents.map((event) => event.projectionRevision)).toEqual([1, 2, 3, 4]);
		const fileDisplaySequences = fileDisplayPatchEvents.map((event) => event.sequence);
		expect(fileDisplaySequences).toEqual(
			fileDisplaySequences.toSorted((left, right) => left - right),
		);
		expect(fileDisplaySequences.every((sequence) => createdSequences.includes(sequence))).toBe(
			true,
		);
		expect(fileDisplayPatchEvents[0]).toMatchObject({
			kind: 'fileDisplayPatch',
			patches: [
				{
					operation: 'reset',
					payload: { sourceGeneration: 3, sourceId: 'file-source-1' },
					slice: 'fileTree',
				},
				{ operation: 'reset', slice: 'fileItem' },
				{ operation: 'reset', slice: 'fileStatus' },
				{ operation: 'upsert', slice: 'fileQuery' },
			],
			surface: 'fileView',
		});
		expect(JSON.stringify(fileDisplayPatchEvents[2])).not.toMatch(
			/contentDescriptor|descriptorId|expectedSha256|sourceCursor|leaseId/,
		);
		expect(
			postedMessages.find(({ message }) => message.kind === 'filePierreRenderJob')?.message,
		).toMatchObject({
			job: {
				itemId: 'file-1',
				payload: { item: { file: { contents: 'file body\n' } }, kind: 'codeViewFileItem' },
				renderKind: 'fileText',
			},
			kind: 'filePierreRenderJob',
			surface: 'file',
			workerDerivationEpoch: 1,
		});
	});

	test('does not replay completed File preparation when native foreground returns to Review', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const openedDescriptorIds: string[] = [];
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8 });
		let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			fileViewBudget: {
				className: 'interactive',
				maxBytes: 2 * 1024 * 1024,
				maxWindowLines: 10_000,
			},
			pump,
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (descriptorId): void => {
					openedDescriptorIds.push(descriptorId);
				},
				onPanePresentationSink: (sink): void => {
					panePresentationSink = sink;
				},
				subscription: {
					cancel: async (): Promise<void> => {},
					events,
					subscriptionId: 'file-subscription-completed-foreground-return',
					subscriptionKind: 'file.metadata',
					update: async (): Promise<void> => {},
				},
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		events.push(makeDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 1,
				requestId: 'request-file-mode-before-completed-preparation',
				update: {
					activeSource: null,
					mode: 'file',
					sequence: 1,
					sessionId: 'file-completed-foreground-return-session',
				},
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 2,
				requestId: 'request-file-completed-foreground-return-selection',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await drainFilePreparationUntilIdle(scheduledDrains);
		expect(openedDescriptorIds).toEqual(['descriptor-file-1']);

		// Act
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 3,
				requestId: 'request-review-mode-before-file-foreground-return',
				update: {
					activeSource: null,
					mode: 'review',
					sequence: 2,
					sessionId: 'file-completed-foreground-return-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const messageCountBeforeNativeCycle = postedMessages.length;
		requireFilePanePresentationSink(panePresentationSink)(
			makeFilePanePresentationFrame(2, 'loadedHidden'),
		);
		requireFilePanePresentationSink(panePresentationSink)(
			makeFilePanePresentationFrame(3, 'foreground'),
		);
		const pendingWorkIdsAfterNativeCycle = pump.getPendingWorkIds();
		pump.runUntilBudget();
		await flushBridgeWorkerRuntimeContinuations();
		await drainFilePreparationUntilIdle(scheduledDrains);

		// Assert
		expect(pendingWorkIdsAfterNativeCycle).toEqual([]);
		expect(openedDescriptorIds).toEqual(['descriptor-file-1']);
		expect(
			postedMessages
				.slice(messageCountBeforeNativeCycle)
				.map(({ message }) => message)
				.filter(
					(message) =>
						message.kind === 'filePierreRenderJob' ||
						(message.kind === 'fileRenderPatch' &&
							message.patches.some((patch): boolean => patch.slice !== 'panelChrome')),
				),
		).toEqual([]);
	});

	test('reports File interest failure without resetting the stream and retries on later source progress', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const updatedInterests: unknown[] = [];
		let updateAttemptCount = 0;
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-interest-failure',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				updateAttemptCount += 1;
				if (updateAttemptCount === 1) throw new Error('interest update failed');
				updatedInterests.push(options);
			},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (): void => {},
				subscription,
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 2,
				requestId: 'request-select-interest-failure',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(updateAttemptCount).toBe(1);

		events.push(makeTreeWindowEvent());
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge File metadata interest update failed.',
				status: 'degraded',
			}),
		);
		expect(updateAttemptCount).toBe(2);
		expect(updatedInterests).toEqual([
			{
				interests: [{ lane: 'foreground', paths: ['Sources/File.swift'] }],
				pathScope: [],
			},
		]);
		expect(postedMessages.map(({ message }) => message)).not.toContainEqual(
			expect.objectContaining({
				message: 'Bridge File metadata subscription failed.',
			}),
		);
		const fileDisplayEvents = postedMessages
			.map(({ message }) => message)
			.filter(
				(message): message is BridgeWorkerFileDisplayPatchEvent =>
					message.kind === 'fileDisplayPatch',
			);
		expect(fileDisplayEvents).toHaveLength(4);
		const fileDisplaySequences = fileDisplayEvents.map((event) => event.sequence);
		expect(new Set(fileDisplaySequences).size).toBe(fileDisplaySequences.length);
		expect(fileDisplaySequences).toEqual(
			fileDisplaySequences.toSorted((left, right) => left - right),
		);
		expect(fileDisplayEvents.map((event) => event.projectionRevision)).toEqual([1, 2, 3, 4]);
		expect(fileDisplayEvents[2]?.patches).toContainEqual(
			expect.objectContaining({ operation: 'upsert', slice: 'fileQuery' }),
		);
		expect(fileDisplayEvents[2]?.patches).toContainEqual(
			expect.objectContaining({ operation: 'replacementCommit', slice: 'fileTree' }),
		);
		expect(fileDisplaySequences[2]).toBeGreaterThan(fileDisplaySequences[1] ?? -1);
		expect(fileDisplayEvents[3]?.patches).toContainEqual(
			expect.objectContaining({ operation: 'replacementCommit', slice: 'fileTree' }),
		);
	});

	test('replays authoritative File display state at the active worker derivation epoch', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-resync',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (): void => {},
				subscription,
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		events.push(makeDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();
		const messagesBeforeResync = postedMessages.length;
		const lastProjectionRevision = Math.max(
			...postedMessages.flatMap(({ message }): readonly number[] =>
				message.kind === 'fileDisplayPatch' ? [message.projectionRevision] : [],
			),
		);

		dispatch.message(
			encodeBridgeWorkerFileDisplayResyncCommand({
				epoch: 99,
				reason: 'acknowledgementTimeout',
				requestId: 'request-file-display-resync',
				transactionId: 'file-query-7',
			}),
		);

		const resyncEvents = postedMessages
			.slice(messagesBeforeResync)
			.map(({ message }) => message)
			.filter(
				(message): message is BridgeWorkerFileDisplayPatchEvent =>
					message.kind === 'fileDisplayPatch',
			);
		expect(resyncEvents.length).toBeGreaterThan(0);
		expect(resyncEvents.every((event) => event.epoch === 1)).toBe(true);
		expect(resyncEvents[0]?.projectionRevision).toBeGreaterThan(lastProjectionRevision);
		const patches = resyncEvents.flatMap((event) => event.patches);
		expect(patches.slice(0, 3)).toEqual([
			{
				operation: 'reset',
				payload: { sourceGeneration: 3, sourceId: 'file-source-1' },
				slice: 'fileTree',
			},
			{ operation: 'reset', slice: 'fileItem' },
			{ operation: 'reset', slice: 'fileStatus' },
		]);
		expect(patches).toContainEqual(
			expect.objectContaining({ itemId: 'file-1', slice: 'fileItem' }),
		);
		expect(patches).toContainEqual(expect.objectContaining({ slice: 'fileQuery' }));
		expect(patches).toContainEqual(expect.objectContaining({ slice: 'fileTree' }));
	});

	test('reports File source discovery transport failure without synthesizing unavailable', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		let subscriptionCount = 0;
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({
				discoveryError: new Error('current File source call failed'),
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (): void => {},
				onSubscribe: (): void => {
					subscriptionCount += 1;
				},
				subscription: {
					cancel: async (): Promise<void> => {},
					events,
					subscriptionId: 'file-subscription-discovery-failure',
					subscriptionKind: 'file.metadata',
					update: async (): Promise<void> => {},
				},
			}),
		});

		await flushBridgeWorkerRuntimeContinuations();

		expect(subscriptionCount).toBe(0);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge File metadata subscription failed.',
				status: 'degraded',
			}),
		);
	});

	test('publishes a source-clearing display reset when File metadata fails', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({
				onDiscoverSource: (): void => {},
				onOpenDescriptor: (): void => {},
				subscription: {
					cancel: async (): Promise<void> => {},
					events,
					subscriptionId: 'file-subscription-runtime-failure',
					subscriptionKind: 'file.metadata',
					update: async (): Promise<void> => {},
				},
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push({ eventKind: 'file.sourceAccepted', source });
		events.push(makeTreeWindowEvent());
		await flushBridgeWorkerRuntimeContinuations();

		events.fail(new Error('metadata stream failed'), true);
		await flushBridgeWorkerRuntimeContinuations();

		const fileDisplayEvents = postedMessages
			.map(({ message }) => message)
			.filter((message) => message.kind === 'fileDisplayPatch');
		expect(fileDisplayEvents.at(-1)).toMatchObject({
			epoch: 1,
			patches: [
				{ operation: 'clear', slice: 'fileTree' },
				{ operation: 'reset', slice: 'fileItem' },
				{ operation: 'reset', slice: 'fileStatus' },
				{
					operation: 'upsert',
					payload: {
						filterMode: 'all',
						projectedRowCount: 0,
						searchError: null,
						searchMode: 'text',
						searchText: '',
						totalRowCount: 0,
					},
					slice: 'fileQuery',
				},
			],
		});
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge File metadata subscription failed.',
				status: 'degraded',
			}),
		);
	});
});

function makeProductTransport(props: {
	readonly discoveryError?: Error;
	readonly onDiscoverSource: () => void;
	readonly onOpenDescriptor: (descriptorId: string) => void;
	readonly onPanePresentationSink?: (
		sink: (frame: BridgeProductPanePresentationFrame) => void,
	) => void;
	readonly onSubscribe?: () => void;
	readonly reviewEvents?: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>;
	readonly subscription: BridgeProductSubscription<'file.metadata'>;
}): BridgeProductTransportSession {
	let fileEpoch = 0;
	let reviewEpoch = 0;
	const reviewEvents =
		props.reviewEvents ??
		new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'review.metadata'>>(64);
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: reviewEvents,
		subscriptionId: 'review-subscription-for-file-runtime-test',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'file' ? fileEpoch : reviewEpoch;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method !== 'file.source.current') throw new Error('Unexpected product call.');
			if (props.discoveryError !== undefined) throw props.discoveryError;
			props.onDiscoverSource();
			return {
				source: currentFileSourceConfiguration,
				status: 'available',
			} as never;
		},
		openContent: (descriptor): never => {
			props.onOpenDescriptor(descriptor.descriptorId);
			const bytes = new TextEncoder().encode('file body\n').buffer;
			return {
				contentKind: 'file.content',
				contentRequestId: 'content-request-1',
				frames: emptyFrames(),
				terminal: Promise.resolve({
					bytes,
					contentKind: 'file.content',
					descriptorId: descriptor.descriptorId,
					kind: 'complete',
					observedSha256: 'a'.repeat(64),
				}),
			} as never;
		},
		setPanePresentationFrameSink: (
			sink: (frame: BridgeProductPanePresentationFrame) => void,
		): void => {
			props.onPanePresentationSink?.(sink);
			sink(makeFilePanePresentationFrame(1, 'foreground'));
		},
		subscribe: ((subscriptionKind: string): never => {
			if (subscriptionKind === 'review.metadata') return reviewSubscription as never;
			props.onSubscribe?.();
			return props.subscription as never;
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
}

function requireFilePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge File pane presentation sink registration.');
	return sink;
}

function makeFilePanePresentationFrame(
	activityRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		activityRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'file-product-test-metadata-stream',
		nativeActivity,
		paneSessionId: 'file-product-test-pane-session',
		refreshingLanes: [],
		streamSequence: activityRevision,
		wireVersion: 2,
		workerInstanceId: 'file-product-test-worker-instance',
	};
}

async function drainFilePreparationUntilIdle(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
): Promise<void> {
	const drainCompletions: Array<ReturnType<BridgeCommWorkerPreparationDrain>> = [];
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = scheduledDrains.splice(0);
		if (drainsForRound.length > 0) {
			drainCompletions.push(...drainsForRound.map((drain) => drain()));
		}
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes event-scheduled continuation drains.
		await flushBridgeWorkerRuntimeContinuations();
		if (scheduledDrains.length === 0) break;
	}
	expect(scheduledDrains).toEqual([]);
	await Promise.all(drainCompletions);
	await flushBridgeWorkerRuntimeContinuations();
}

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: source.repoId,
	rootPathToken: 'root-token-1',
	worktreeId: source.worktreeId,
} as const;

function makeTreeWindowEvent(): BridgeProductSubscriptionEvent<'file.metadata'> {
	return {
		eventKind: 'file.treeWindow',
		finalWindow: true,
		lineage: { lane: 'visible', loadedBy: 'startup_window' },
		pathScope: [],
		rows: [
			{
				changeStatus: 'modified',
				depth: 0,
				fileId: 'file-1',
				isDirectory: false,
				lineCount: 1,
				name: 'File.swift',
				parentPath: null,
				path: 'Sources/File.swift',
				rowId: 'row-file-1',
				sizeBytes: 10,
			},
		],
		source,
		startIndex: 0,
		totalRowCount: 1,
	};
}

function makeDescriptorReadyEvent(): BridgeProductSubscriptionEvent<'file.metadata'> {
	return {
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: 10,
				descriptorId: 'descriptor-file-1',
				encoding: 'utf-8',
				expectedSha256: 'a'.repeat(64),
				fileId: 'file-1',
				maximumBytes: 10,
				source,
				window: {
					kind: 'prefix',
					maximumBytes: 10,
					maximumLines: 1,
					startByte: 0,
				},
			},
		},
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		estimatedContentHeightPixels: null,
		eventKind: 'file.descriptorReady',
		fileExtension: 'swift',
		fileId: 'file-1',
		language: 'swift',
		modifiedAtUnixMilliseconds: 1,
		path: 'Sources/File.swift',
		payloadByteCount: 10,
		payloadLineCount: 1,
		rowId: 'row-file-1',
		sizeBytes: 10,
		source,
		totalLineCount: 1,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}

async function* emptyFrames(): AsyncIterable<never> {}
