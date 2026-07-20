import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	activateBridgeCommWorkerFileViewerMode,
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
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

interface PendingContentAttempt {
	readonly descriptorId: string;
	readonly resolve: (terminal: unknown) => void;
}

describe('Bridge comm worker selected File preparation cancellation', () => {
	test('keeps the selected load alive across identity-equivalent descriptor replay', async () => {
		const harness = await createPendingFilePreparationHarness();

		harness.events.push(fileDescriptorReadyEvent());
		await flushBridgeWorkerRuntimeContinuations();

		expect(harness.abortCount()).toBe(0);
		expect(harness.attempts).toHaveLength(1);
		await completeAttempt(harness, 0, 'descriptor-file-1');
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(1);
		expect(fileAvailabilityPatches(harness.postedMessages)).not.toContainEqual(
			expect.objectContaining({
				payload: expect.objectContaining({ reason: 'load_failed', state: 'failed' }),
			}),
		);
	});

	test('keeps the selected load alive across an unrelated descriptor delta', async () => {
		const harness = await createPendingFilePreparationHarness();

		harness.events.push(
			fileDescriptorReadyEvent({
				descriptorId: 'descriptor-file-2',
				fileId: 'file-2',
				path: 'Sources/Unrelated.swift',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(harness.abortCount()).toBe(0);
		expect(harness.attempts).toHaveLength(1);
		expect(fileAvailabilityPatches(harness.postedMessages)).not.toContainEqual(
			expect.objectContaining({
				payload: expect.objectContaining({ reason: 'load_failed', state: 'failed' }),
			}),
		);
		await completeAttempt(harness, 0, 'descriptor-file-1');
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(1);
	});

	test('cancels once and reopens when the selected descriptor is replaced', async () => {
		const harness = await createPendingFilePreparationHarness();

		harness.events.push(
			fileDescriptorReadyEvent({
				descriptorId: 'descriptor-file-1-replacement',
				expectedSha256: 'b'.repeat(64),
				modifiedAtUnixMilliseconds: 2,
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		await drainUntilAttemptCount(harness, 2);

		expect(harness.abortCount()).toBe(1);
		expect(harness.attempts.map(({ descriptorId }) => descriptorId)).toEqual([
			'descriptor-file-1',
			'descriptor-file-1-replacement',
		]);
		await completeAttempt(harness, 1, 'descriptor-file-1-replacement');
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(1);
		expect(fileAvailabilityPatches(harness.postedMessages)).not.toContainEqual(
			expect.objectContaining({
				payload: expect.objectContaining({ reason: 'load_failed', state: 'failed' }),
			}),
		);
	});

	test('suppresses an in-flight selected load until one newer native foreground frame', async () => {
		// Arrange
		const harness = await createPendingFilePreparationHarness();
		expect(harness.attempts).toHaveLength(1);

		// Act
		harness.publishPresentation(2, 'loadedHidden');
		await flushBridgeWorkerRuntimeContinuations();
		harness.dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 2,
				requestId: 'request-hidden-file-active-viewer-mode',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'hidden-file-session',
				},
			}),
		);
		harness.dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 4,
				requestId: 'request-hidden-file-selection',
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(harness.abortCount()).toBe(1);
		expect(harness.attempts).toHaveLength(1);
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(0);

		// Act
		harness.publishPresentation(3, 'foreground');
		await drainUntilAttemptCount(harness, 2);
		harness.publishPresentation(3, 'foreground');
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(harness.attempts.map(({ descriptorId }) => descriptorId)).toEqual([
			'descriptor-file-1',
			'descriptor-file-1',
		]);
		expect(harness.abortCount()).toBe(1);
	});

	test('aborts an in-flight selected File load when Review becomes accepted', async () => {
		// Arrange
		const harness = await createPendingFilePreparationHarness();
		expect(harness.attempts).toHaveLength(1);

		// Act
		harness.dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 2,
				requestId: 'request-review-mode-aborts-selected-file',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'review-mode-aborts-selected-file-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(harness.abortCount()).toBe(1);
		expect(harness.attempts).toHaveLength(1);
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(0);
	});
});

interface PendingFilePreparationHarness {
	readonly abortCount: () => number;
	readonly attempts: PendingContentAttempt[];
	readonly dispatch: ReturnType<typeof createRecordingBridgeCommWorkerPort>['dispatch'];
	readonly events: BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'file.metadata'>>;
	readonly postedMessages: readonly { readonly message: BridgeWorkerServerToMainMessage }[];
	readonly publishPresentation: (
		activityRevision: number,
		nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
	) => void;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
}

async function createPendingFilePreparationHarness(): Promise<PendingFilePreparationHarness> {
	const events = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'file.metadata'>
	>(64);
	const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
	const attempts: PendingContentAttempt[] = [];
	let observedAbortCount = 0;
	const fileSubscription: BridgeProductSubscription<'file.metadata'> = {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: 'file-subscription-preparation-cancellation',
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'review.metadata'>>(
			64,
		),
		subscriptionId: 'review-subscription-for-file-preparation-cancellation',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	let fileEpoch = 0;
	let reviewEpoch = 0;
	let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
	const productTransport: BridgeProductTransportSession = {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'file' ? fileEpoch : reviewEpoch;
		},
		call: async (): Promise<never> =>
			({
				source: {
					cwdScope: null,
					freshness: 'live',
					includeStatuses: true,
					repoId: source.repoId,
					rootPathToken: 'root-token-1',
					worktreeId: source.worktreeId,
				},
				status: 'available',
			}) as never,
		openContent: ((descriptor: { readonly descriptorId: string }, abortSignal: AbortSignal) => {
			let rejectAttempt!: (reason?: unknown) => void;
			let resolveAttempt!: (terminal: unknown) => void;
			const terminal = new Promise<unknown>((resolve, reject): void => {
				rejectAttempt = reject;
				resolveAttempt = resolve;
			});
			const attempt = {
				descriptorId: descriptor.descriptorId,
				resolve: resolveAttempt,
			} satisfies PendingContentAttempt;
			attempts.push(attempt);
			abortSignal.addEventListener(
				'abort',
				(): void => {
					observedAbortCount += 1;
					rejectAttempt(abortSignal.reason);
				},
				{ once: true },
			);
			return {
				contentKind: 'file.content',
				contentRequestId: `content-request-${attempts.length}`,
				descriptorId: descriptor.descriptorId,
				frames: emptyFrames(),
				terminal,
			} as never;
		}) as BridgeProductTransportSession['openContent'],
		setPanePresentationFrameSink: (sink): void => {
			panePresentationSink = sink;
		},
		subscribe: ((subscriptionKind: string): never =>
			(subscriptionKind === 'file.metadata'
				? fileSubscription
				: reviewSubscription) as never) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
	const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
	registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
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
	activateBridgeCommWorkerFileViewerMode(dispatch, 'preparation-cancellation');
	const publishPresentation = (
		activityRevision: number,
		nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
	): void => {
		if (panePresentationSink === null) {
			throw new Error('Expected Bridge pane presentation sink registration.');
		}
		panePresentationSink(makePanePresentationFrame(activityRevision, nativeActivity));
	};
	publishPresentation(1, 'foreground');
	dispatch.message(
		encodeBridgeWorkerSelectCommand({
			epoch: 1,
			requestId: 'request-select-file-preparation-cancellation',
			selectedItemId: 'file-1',
			selectedSource: 'user',
			surface: 'fileView',
		}),
	);
	await flushBridgeWorkerRuntimeContinuations();
	events.push({ eventKind: 'file.sourceAccepted', source });
	events.push(fileTreeWindowEvent());
	events.push(fileDescriptorReadyEvent());
	await flushBridgeWorkerRuntimeContinuations();
	const harness = {
		abortCount: (): number => observedAbortCount,
		attempts,
		dispatch,
		events,
		postedMessages,
		publishPresentation,
		scheduledDrains,
	} satisfies PendingFilePreparationHarness;
	await drainUntilAttemptCount(harness, 1);
	return harness;
}

async function drainUntilAttemptCount(
	harness: PendingFilePreparationHarness,
	expectedAttemptCount: number,
): Promise<void> {
	while (harness.scheduledDrains.length > 0 && harness.attempts.length < expectedAttemptCount) {
		const drain = harness.scheduledDrains.shift();
		if (drain === undefined) break;
		void drain();
		await flushBridgeWorkerRuntimeContinuations();
	}
	expect(harness.attempts).toHaveLength(expectedAttemptCount);
}

async function completeAttempt(
	harness: PendingFilePreparationHarness,
	attemptIndex: number,
	descriptorId: string,
): Promise<void> {
	harness.attempts[attemptIndex]?.resolve({
		bytes: new TextEncoder().encode('file body\n').buffer,
		contentKind: 'file.content',
		descriptorId,
		endOfSource: true,
		kind: 'complete',
		observedSha256: descriptorId.endsWith('replacement') ? 'b'.repeat(64) : 'a'.repeat(64),
	});
	await flushBridgeWorkerRuntimeContinuations();
	while (harness.scheduledDrains.length > 0) {
		const drain = harness.scheduledDrains.shift();
		if (drain !== undefined) await drain();
		await flushBridgeWorkerRuntimeContinuations();
	}
}

function fileRenderJobs(
	messages: readonly { readonly message: BridgeWorkerServerToMainMessage }[],
): readonly BridgeWorkerServerToMainMessage[] {
	return messages
		.map(({ message }) => message)
		.filter((message) => message.kind === 'filePierreRenderJob');
}

function fileAvailabilityPatches(
	messages: readonly { readonly message: BridgeWorkerServerToMainMessage }[],
): readonly unknown[] {
	return messages
		.map(({ message }) => message)
		.filter((message) => message.kind === 'fileRenderPatch')
		.flatMap((message) => message.patches)
		.filter((patch) => patch.slice === 'contentAvailability');
}

function fileTreeWindowEvent(): BridgeProductSubscriptionEvent<'file.metadata'> {
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

function fileDescriptorReadyEvent(
	props: {
		readonly descriptorId?: string;
		readonly expectedSha256?: string;
		readonly fileId?: string;
		readonly modifiedAtUnixMilliseconds?: number;
		readonly path?: string;
	} = {},
): BridgeProductSubscriptionEvent<'file.metadata'> {
	const fileId = props.fileId ?? 'file-1';
	const path = props.path ?? 'Sources/File.swift';
	return {
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: 10,
				descriptorId: props.descriptorId ?? 'descriptor-file-1',
				encoding: 'utf-8',
				expectedSha256: props.expectedSha256 ?? 'a'.repeat(64),
				fileId,
				maximumBytes: 10,
				source,
				window: {
					kind: 'prefix',
					maximumBytes: 10,
					maximumLines: 10_000,
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
		fileId,
		language: 'swift',
		modifiedAtUnixMilliseconds: props.modifiedAtUnixMilliseconds ?? 1,
		path,
		payloadByteCount: 10,
		payloadLineCount: 1,
		rowId: `row-${fileId}`,
		sizeBytes: 10,
		source,
		totalLineCount: 1,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}

async function* emptyFrames(): AsyncIterable<never> {}

function makePanePresentationFrame(
	activityRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		activityRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-file-preparation-cancellation',
		nativeActivity,
		paneSessionId: 'pane-session-file-preparation-cancellation',
		refreshingLanes: [],
		streamSequence: activityRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-file-preparation-cancellation',
	};
}
