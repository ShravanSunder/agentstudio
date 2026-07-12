import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerReviewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createRecordingBridgeCommWorkerPort,
	descriptorByUrl,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeImmediateTextResponse,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime protocol Review preparation', () => {
	test('selected Review demand preempts an in-progress source reset and uses the newest generation only', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const sourceRows = Array.from({ length: 130 }, (_unused, index) => ({
			id: `item-${index + 1}`,
			parentId: null,
			index,
		}));
		const sourceContentItems = sourceRows.map((row) =>
			makeWorkerReviewContentMetadata({ itemId: row.id }),
		);
		const sourceDescriptors = sourceRows.flatMap((row) => [
			makeContentRequestDescriptor({
				generation: 6,
				itemId: row.id,
				role: 'base',
				text: `old ${row.id}\n`,
			}),
			makeContentRequestDescriptor({
				generation: 6,
				itemId: row.id,
				role: 'head',
				text: `new ${row.id}\n`,
			}),
		]);
		const sourceSemantics = sourceRows.map((row) => makeRenderSemantics({ itemId: row.id }));

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [
				{
					...makeWorkerReviewContentMetadata({ itemId: 'item-130' }),
					availableContentRoles: [],
				},
			],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(901),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [],
			rows: [{ id: 'item-130', parentId: null, index: 129 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-chunked-source-reset',
				epoch: 6,
				contentItems: sourceContentItems,
				contentRequestDescriptors: sourceDescriptors,
				renderSemantics: sourceSemantics,
				rows: sourceRows,
			}),
		);

		expect(scheduledDrains).toHaveLength(1);
		const firstResetDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await firstResetDrain;
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-during-source-reset',
				epoch: 7,
				selectedItemId: 'item-130',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const selectedStartDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await selectedStartDrain;

		const pierreJobs = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message.job] : [],
		);
		expect(pierreJobs).toHaveLength(1);
		expect(pierreJobs[0]?.itemId).toBe('item-130');
		expect(pierreJobs[0]?.contentHash).toContain('generation-6');
	});

	test('newer Review source reset prevents older continuation from overwriting later chunks', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const sourceRows = Array.from({ length: 130 }, (_unused, index) => ({
			id: `item-${index + 1}`,
			parentId: null,
			index,
		}));
		const sourceSemantics = sourceRows.map((row) => makeRenderSemantics({ itemId: row.id }));
		const staleContentItems = sourceRows.map((row) =>
			row.id === 'item-130'
				? {
						...makeWorkerReviewContentMetadata({ itemId: row.id }),
						availableContentRoles: [],
					}
				: makeWorkerReviewContentMetadata({ itemId: row.id }),
		);
		const freshContentItems = sourceRows.map((row) =>
			makeWorkerReviewContentMetadata({ itemId: row.id }),
		);

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(951),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-stale-source-reset',
				epoch: 6,
				contentItems: staleContentItems,
				contentRequestDescriptors: sourceRows.flatMap((row) => [
					makeContentRequestDescriptor({
						generation: 6,
						itemId: row.id,
						role: 'base',
						text: `stale base ${row.id}\n`,
					}),
					makeContentRequestDescriptor({
						generation: 6,
						itemId: row.id,
						role: 'head',
						text: `stale head ${row.id}\n`,
					}),
				]),
				renderSemantics: sourceSemantics,
				rows: sourceRows,
			}),
		);
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-fresh-source-reset',
				epoch: 7,
				contentItems: freshContentItems,
				contentRequestDescriptors: sourceRows.flatMap((row) => [
					makeContentRequestDescriptor({
						generation: 7,
						itemId: row.id,
						role: 'base',
						text: `fresh base ${row.id}\n`,
					}),
					makeContentRequestDescriptor({
						generation: 7,
						itemId: row.id,
						role: 'head',
						text: `fresh head ${row.id}\n`,
					}),
				]),
				renderSemantics: sourceSemantics,
				rows: sourceRows,
			}),
		);
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await waitBridgeWorkerRuntimeTaskBoundary();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-after-overlap',
				epoch: 8,
				selectedItemId: 'item-130',
				selectedSource: 'user',
			}),
		);
		const selectedFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[4])();
		await selectedFirstDrain;

		const pierreJobs = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message.job] : [],
		);
		expect(pierreJobs).toHaveLength(1);
		expect(pierreJobs[0]?.itemId).toBe('item-130');
		expect(pierreJobs[0]?.contentHash).toContain('generation-7');
	});

	test('later source reset chunks schedule visible demand for newly eligible visible rows', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const sourceRows = Array.from({ length: 130 }, (_unused, index) => ({
			id: `item-${index + 1}`,
			parentId: null,
			index,
		}));
		const sourceContentItems = sourceRows.map((row) =>
			makeWorkerReviewContentMetadata({ itemId: row.id }),
		);

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'old base item-1\n',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'old head item-1\n',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(981),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-late-source-row',
				epoch: 5,
				visibleItemIds: ['item-1', 'item-130'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 129,
				phase: 'settled',
			}),
		);
		const oldVisibleDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await oldVisibleDrain;

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-late-visible-source-reset',
				epoch: 6,
				contentItems: sourceContentItems,
				contentRequestDescriptors: sourceRows.flatMap((row) => [
					makeContentRequestDescriptor({
						generation: 6,
						itemId: row.id,
						role: 'base',
						text: `fresh base ${row.id}\n`,
					}),
					makeContentRequestDescriptor({
						generation: 6,
						itemId: row.id,
						role: 'head',
						text: `fresh head ${row.id}\n`,
					}),
				]),
				renderSemantics: sourceRows.map((row) => makeRenderSemantics({ itemId: row.id })),
				rows: sourceRows,
			}),
		);
		const firstResetDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		await firstResetDrain;
		await drainBridgeWorkerRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) =>
						postedMessage.message.kind === 'pierreRenderJob' &&
						postedMessage.message.job.itemId === 'item-130',
				),
			scheduledDrains,
			startIndex: 3,
		});

		const pierreJobItemIds = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message.job.itemId] : [],
		);
		expect(pierreJobItemIds).toContain('item-1');
		expect(pierreJobItemIds).toContain('item-130');
	});

	test('drains selected review content prep through the worker port after local select slices', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata()],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
			],
			createSequence: createBridgeWorkerSequenceCounter(41),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [makeRenderSemantics()],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(scheduledDrains).toHaveLength(1);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
		]);
		expect(postedMessages[0]?.transferList).toBeUndefined();
		expect(postedMessages[1]?.transferList).toBeUndefined();
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(firstDrainResult.yielded).toBe(false);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:7:42']);
		expect(secondDrainResult.yielded).toBe(false);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[2]?.transferList).toEqual([]);
		expect(postedMessages[2]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		const pierreJobMessage = postedMessages[2]?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected Pierre render job message.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: pierreJobMessage.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 42,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('applies source update before first select when the runtime boots empty', () => {
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(11),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-source-update',
				epoch: 1,
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
					makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 2,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
		]);
		expect(postedMessages[1]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 2,
			sequence: 11,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-1' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'loading' },
				},
			],
		});
		expect(scheduledDrains).toHaveLength(1);
	});
});

async function waitBridgeWorkerRuntimeTaskBoundary(): Promise<void> {
	await new Promise<void>((resolve) => {
		setTimeout(resolve, 0);
	});
}

async function drainBridgeWorkerRuntimeUntil(props: {
	readonly hasExpectedEvent: () => boolean;
	readonly scheduledDrains: readonly BridgeCommWorkerPreparationDrain[];
	readonly startIndex: number;
}): Promise<void> {
	return drainBridgeWorkerRuntimeUntilAttempt({ ...props, attempt: 0 });
}

async function drainBridgeWorkerRuntimeUntilAttempt(props: {
	readonly attempt: number;
	readonly hasExpectedEvent: () => boolean;
	readonly scheduledDrains: readonly BridgeCommWorkerPreparationDrain[];
	readonly startIndex: number;
}): Promise<void> {
	if (props.hasExpectedEvent() || props.attempt >= 8) {
		return;
	}
	await flushBridgeWorkerRuntimeContinuations();
	if (props.startIndex >= props.scheduledDrains.length) {
		await waitBridgeWorkerRuntimeTaskBoundary();
		return drainBridgeWorkerRuntimeUntilAttempt({
			...props,
			attempt: props.attempt + 1,
		});
	}
	void assertBridgeCommWorkerPreparationDrain(props.scheduledDrains[props.startIndex])();
	return drainBridgeWorkerRuntimeUntilAttempt({
		...props,
		attempt: props.attempt + 1,
		startIndex: props.startIndex + 1,
	});
}
