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
	makeReviewMetadataDataFrame,
	type ReviewMetadataSubscription,
} from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	activateBridgeCommWorkerFileViewerMode,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeFileMetadataDataFrame,
	type FileMetadataDataFrame,
	type FileMetadataSubscription,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationProtocolIdentity } from './bridge-product-metadata-application-protocol.js';
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
	test('reissues the selected File publication after its receipt lease expires', async () => {
		// Arrange
		let nowMilliseconds = 0;
		const scheduledWakes: TestScheduledRenderFulfillmentWake[] = [];
		const harness = await createPendingFilePreparationHarness({
			now: (): number => nowMilliseconds,
			scheduleRenderFulfillmentWake: (delayMilliseconds, wake): (() => void) => {
				const scheduledWake = { active: true, delayMilliseconds, wake };
				scheduledWakes.push(scheduledWake);
				return (): void => {
					scheduledWake.active = false;
				};
			},
		});
		await completeAttempt(harness, 0, 'descriptor-file-1');
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(1);

		// Act
		nowMilliseconds = 5_000;
		runScheduledRenderFulfillmentWake(scheduledWakes[0]);
		nowMilliseconds = 5_025;
		runScheduledRenderFulfillmentWake(scheduledWakes[1]);
		await drainUntilAttemptCount(harness, 2);
		await completeAttempt(harness, 1, 'descriptor-file-1');

		// Assert
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(2);
	});

	test('settles descriptor preparation unavailable when the current File refresh ends without a descriptor', async () => {
		// Arrange
		const harness = await createPendingFilePreparationHarness({
			includeDescriptor: false,
			initialRefreshingLanes: ['file'],
		});
		expect(harness.attempts).toHaveLength(0);

		// Act
		harness.publishPresentation(2, 'foreground', []);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(fileAvailabilityPatches(harness.postedMessages)).toContainEqual(
			expect.objectContaining({
				itemId: 'file-1',
				payload: { reason: 'descriptor_missing', state: 'unavailable' },
			}),
		);
	});

	test('keeps the selected load alive across identity-equivalent descriptor replay', async () => {
		const harness = await createPendingFilePreparationHarness();

		harness.events.push(makeFileMetadataDataFrame(fileDescriptorReadyEvent()));
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
			makeFileMetadataDataFrame(
				fileDescriptorReadyEvent({
					descriptorId: 'descriptor-file-2',
					fileId: 'file-2',
					path: 'Sources/Unrelated.swift',
				}),
			),
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

	test('reissues selected File load once after an unexpected EOF terminal failure', async () => {
		const harness = await createPendingFilePreparationHarness();

		await failAttempt(harness, 0, 'descriptor-file-1');

		expect(harness.attempts).toHaveLength(2);
		if (harness.attempts.length < 2) return;

		await completeAttempt(harness, 1, 'descriptor-file-1');
		expect(fileRenderJobs(harness.postedMessages)).toHaveLength(1);
		expect(fileAvailabilityPatches(harness.postedMessages)).toContainEqual(
			expect.objectContaining({ payload: expect.objectContaining({ state: 'ready' }) }),
		);

		const persistentFailureHarness = await createPendingFilePreparationHarness();
		await failAttempt(persistentFailureHarness, 0, 'descriptor-file-1');
		expect(persistentFailureHarness.attempts).toHaveLength(2);
		if (persistentFailureHarness.attempts.length < 2) return;
		await failAttempt(persistentFailureHarness, 1, 'descriptor-file-1', false);
		expect(persistentFailureHarness.attempts).toHaveLength(2);
	});

	test('cancels once and reopens when the selected descriptor is replaced', async () => {
		const harness = await createPendingFilePreparationHarness();

		harness.events.push(
			makeFileMetadataDataFrame(
				fileDescriptorReadyEvent({
					descriptorId: 'descriptor-file-1-replacement',
					expectedSha256: 'b'.repeat(64),
					modifiedAtUnixMilliseconds: 2,
				}),
			),
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

	test('resumes the retained selected File request after Review returns to File', async () => {
		// Arrange
		const harness = await createPendingFilePreparationHarness();
		expect(harness.attempts).toHaveLength(1);

		// Act: switch away while content is in flight, then return without reselecting.
		harness.dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 2,
				requestId: 'request-review-mode-suspends-selected-file',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'review-mode-suspends-selected-file-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		harness.dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 3,
				requestId: 'request-file-mode-resumes-selected-file',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 3,
					sessionId: 'review-mode-suspends-selected-file-session',
				},
			}),
		);
		await drainUntilAttemptCount(harness, 2);

		// Assert
		expect(harness.abortCount()).toBe(1);
		expect(harness.attempts.map(({ descriptorId }) => descriptorId)).toEqual([
			'descriptor-file-1',
			'descriptor-file-1',
		]);
	});
});

interface PendingFilePreparationHarness {
	readonly abortCount: () => number;
	readonly attempts: PendingContentAttempt[];
	readonly dispatch: ReturnType<typeof createRecordingBridgeCommWorkerPort>['dispatch'];
	readonly events: BridgeProductBoundedAsyncQueue<FileMetadataDataFrame>;
	readonly postedMessages: readonly { readonly message: BridgeWorkerServerToMainMessage }[];
	readonly publishPresentation: (
		presentationRevision: number,
		nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
		refreshingLanes?: BridgeProductPanePresentationFrame['refreshingLanes'],
	) => void;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
}

interface TestScheduledRenderFulfillmentWake {
	active: boolean;
	readonly delayMilliseconds: number;
	readonly wake: () => void;
}

async function createPendingFilePreparationHarness(
	props: {
		readonly includeDescriptor?: boolean;
		readonly initialRefreshingLanes?: BridgeProductPanePresentationFrame['refreshingLanes'];
		readonly now?: () => number;
		readonly scheduleRenderFulfillmentWake?: (
			delayMilliseconds: number,
			wake: () => void,
		) => () => void;
	} = {},
): Promise<PendingFilePreparationHarness> {
	const events = new BridgeProductBoundedAsyncQueue<FileMetadataDataFrame>(64);
	const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
	const attempts: PendingContentAttempt[] = [];
	let observedAbortCount = 0;
	const fileSubscription: FileMetadataSubscription = {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: 'file-subscription-preparation-cancellation',
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
	const reviewSubscription: ReviewMetadataSubscription = {
		cancel: async (): Promise<void> => {},
		events: new BridgeProductBoundedAsyncQueue<ReturnType<typeof makeReviewMetadataDataFrame>>(64),
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
		subscribe: ((protocol: BridgeProductMetadataApplicationProtocolIdentity): never =>
			(protocol.kind === 'file.metadata'
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
		...(props.now === undefined ? {} : { now: props.now }),
		...(props.scheduleRenderFulfillmentWake === undefined
			? {}
			: { scheduleRenderFulfillmentWake: props.scheduleRenderFulfillmentWake }),
		schedulePreparationDrain: (drain): void => {
			scheduledDrains.push(drain);
		},
	});
	activateBridgeCommWorkerFileViewerMode(dispatch, 'preparation-cancellation');
	const publishPresentation = (
		presentationRevision: number,
		nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
		refreshingLanes: BridgeProductPanePresentationFrame['refreshingLanes'] = [],
	): void => {
		if (panePresentationSink === null) {
			throw new Error('Expected Bridge pane presentation sink registration.');
		}
		panePresentationSink(
			makePanePresentationFrame(presentationRevision, nativeActivity, refreshingLanes),
		);
	};
	publishPresentation(1, 'foreground', props.initialRefreshingLanes ?? []);
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
	events.push(makeFileMetadataDataFrame({ eventKind: 'file.sourceAccepted', source }));
	events.push(makeFileMetadataDataFrame(fileTreeWindowEvent()));
	if (props.includeDescriptor !== false) {
		events.push(makeFileMetadataDataFrame(fileDescriptorReadyEvent()));
	}
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
	if (props.includeDescriptor !== false) await drainUntilAttemptCount(harness, 1);
	return harness;
}

function runScheduledRenderFulfillmentWake(
	scheduledWake: TestScheduledRenderFulfillmentWake | undefined,
): void {
	if (scheduledWake === undefined || !scheduledWake.active) {
		throw new Error('Expected an active File render-fulfillment wake.');
	}
	scheduledWake.active = false;
	scheduledWake.wake();
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

async function failAttempt(
	harness: PendingFilePreparationHarness,
	attemptIndex: number,
	descriptorId: string,
	expectRetry = true,
): Promise<void> {
	harness.attempts[attemptIndex]?.resolve({
		code: 'unexpected_eof',
		contentKind: 'file.content',
		descriptorId,
		kind: 'error',
		safeMessage: 'Unexpected EOF while reading File content.',
	});
	await flushBridgeWorkerRuntimeContinuations();
	if (expectRetry) {
		await drainUntilAttemptCount(harness, attemptIndex + 2);
		return;
	}
	while (harness.scheduledDrains.length > 0) {
		const drain = harness.scheduledDrains.shift();
		if (drain !== undefined) await drain().catch(() => undefined);
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

function fileTreeWindowEvent(): Parameters<typeof makeFileMetadataDataFrame>[0] {
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
				fileClass: 'source',
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
): Parameters<typeof makeFileMetadataDataFrame>[0] {
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
	presentationRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
	refreshingLanes: BridgeProductPanePresentationFrame['refreshingLanes'],
): BridgeProductPanePresentationFrame {
	return {
		fileRefreshFailure: null,
		presentationRevision,
		kind: 'pane.presentation',

		operationCorrelationId: null,
		metadataStreamId: 'metadata-stream-file-preparation-cancellation',
		nativeActivity,
		paneSessionId: 'pane-session-file-preparation-cancellation',
		refreshingLanes,
		reviewComparison: null,
		streamSequence: presentationRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-file-preparation-cancellation',
	};
}
