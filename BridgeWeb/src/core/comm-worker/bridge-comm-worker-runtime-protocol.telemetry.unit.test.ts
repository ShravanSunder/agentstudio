import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createDeferredReviewContentStream,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	type DeferredReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';

describe('Bridge comm worker runtime protocol telemetry', () => {
	test('records command queue wait and handler duration from typed dispatch timestamp', () => {
		const clockReadings = [18, 22];
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const { dispatch } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			now: () => {
				const value = clockReadings.shift();
				if (value === undefined) {
					throw new Error('Unexpected runtime clock read.');
				}
				return value;
			},
			schedulePreparationDrain: (): void => {},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 3,
				issuedAtMilliseconds: 10,
				requestId: 'request-select',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.worker.task',
				durationMilliseconds: 4,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.worker.command': 'select',
					'agentstudio.bridge.worker.lane': 'selected',
					'agentstudio.bridge.worker.task_kind': 'message_handler',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.worker.handler_duration_ms': 4,
					'agentstudio.bridge.worker.queue_wait_ms': 8,
				}),
			}),
		);
	});

	test('threads runtime telemetry client into stale selected review preparation drops', async () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(8);
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		const deferredStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();
		const baseDescriptor = makeContentRequestDescriptor({
			itemId: 'item-1',
			role: 'base',
			text: 'base content\n',
		});
		const headDescriptor = makeContentRequestDescriptor({
			itemId: 'item-1',
			role: 'head',
			text: 'head content\n',
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport: makeTelemetryReviewProductTransport({
				deferredStreamsByDescriptorId,
				reviewMetadataEvents,
			}),
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});
		await flushBridgeWorkerRuntimeContinuations();
		reviewMetadataEvents.push(telemetryReviewSnapshotEvent([baseDescriptor, headDescriptor]));
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 7,
				requestId: 'request-select-item-1',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const firstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains.shift())();

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 8,
				requestId: 'request-select-item-2',
				selectedItemId: 'item-2',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		deferredStreamsByDescriptorId.get(baseDescriptor.descriptorId)?.resolve('base content\n');
		deferredStreamsByDescriptorId.get(headDescriptor.descriptorId)?.resolve('head content\n');
		await flushBridgeWorkerRuntimeContinuations();
		await drainScheduledPreparation(scheduledDrains);
		await firstDrain;

		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.selected_content_dropped',
				durationMilliseconds: null,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.drop_reason': 'stale_after_fetch',
					'agentstudio.bridge.phase': 'selected_content_dropped',
					'agentstudio.bridge.result': 'dropped',
					'agentstudio.bridge.viewer': 'review',
				}),
			}),
		);
	});
});

function makeTelemetryReviewProductTransport(props: {
	readonly deferredStreamsByDescriptorId: Map<string, DeferredReviewContentStream>;
	readonly reviewMetadataEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>;
}): BridgeProductTransportSession {
	let reviewWorkerDerivationEpoch = 0;
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: props.reviewMetadataEvents,
		subscriptionId: 'telemetry-review-subscription',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewWorkerDerivationEpoch += 1;
			return surface === 'review' ? reviewWorkerDerivationEpoch : 0;
		},
		call: async (): Promise<never> => {
			throw new Error('Unexpected product call in Review telemetry test.');
		},
		openContent: (descriptor) => {
			if (descriptor.contentKind !== 'review.content') {
				throw new Error(`Unexpected product content kind ${descriptor.contentKind}.`);
			}
			const deferredStream = createDeferredReviewContentStream(descriptor);
			props.deferredStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The content-kind guard above closes this test transport to Review streams.
			return deferredStream.stream as never;
		},
		setPanePresentationFrameSink: (
			sink: (frame: BridgeProductPanePresentationFrame) => void,
		): void => {
			sink({
				activityRevision: 1,
				kind: 'pane.presentation',
				metadataStreamId: 'telemetry-review-metadata-stream',
				nativeActivity: 'foreground',
				paneSessionId: 'telemetry-review-pane-session',
				refreshingLanes: [],
				streamSequence: 1,
				wireVersion: 2,
				workerInstanceId: 'telemetry-review-worker-instance',
			});
		},
		subscribe: (...arguments_): never => {
			const [subscriptionKind] = arguments_;
			if (subscriptionKind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${subscriptionKind}.`);
			}
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This closed test transport rejects every non-Review subscription above.
			return reviewSubscription as never;
		},
		workerDerivationEpoch: (surface): number =>
			surface === 'review' ? reviewWorkerDerivationEpoch : 0,
	};
}

function telemetryReviewSnapshotEvent(
	descriptors: readonly BridgeWorkerReviewContentRequestDescriptor[],
): BridgeProductSubscriptionEvent<'review.metadata'> {
	const descriptorByRole = new Map(descriptors.map((descriptor) => [descriptor.role, descriptor]));
	const baseDescriptor = requireReviewDescriptor(descriptorByRole.get('base'));
	const headDescriptor = requireReviewDescriptor(descriptorByRole.get('head'));
	return {
		baseEndpoint: {
			createdAtUnixMilliseconds: 1,
			endpointId: 'base-endpoint',
			kind: 'gitRef',
			label: 'base',
			providerIdentity: 'base-provider',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
		},
		contentSources: descriptors.map((descriptor) => ({
			contentDigest: descriptor.contentDigest,
			contentKind: descriptor.contentKind,
			descriptorId: descriptor.descriptorId,
			encoding: descriptor.encoding,
			endpointId: descriptor.endpointId,
			handleId: descriptor.handleId,
			isBinary: descriptor.isBinary,
			itemId: descriptor.itemId,
			language: descriptor.language,
			mimeType: descriptor.mimeType,
			packageId: descriptor.packageId,
			reviewGeneration: descriptor.reviewGeneration,
			role: descriptor.role,
			sourceIdentity: descriptor.sourceIdentity,
			wholeByteLength: descriptor.wholeByteLength,
		})),
		eventKind: 'review.snapshot',
		extentFacts: [
			{ contentRole: 'base', itemId: 'item-1', lineCount: 1 },
			{ contentRole: 'head', itemId: 'item-1', lineCount: 1 },
		],
		generation: baseDescriptor.reviewGeneration,
		headEndpoint: {
			createdAtUnixMilliseconds: 1,
			endpointId: 'head-endpoint',
			kind: 'workingTree',
			label: 'head',
			providerIdentity: 'head-provider',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
		},
		itemMetadata: [
			{
				basePath: 'Sources/App/item-1.swift',
				changeKind: 'modified',
				contentDescriptorIdsByRole: {
					base: baseDescriptor.descriptorId,
					head: headDescriptor.descriptorId,
				},
				contentHashesByRole: {
					base: baseDescriptor.contentDigest.value,
					head: headDescriptor.contentDigest.value,
				},
				contentRoles: ['base', 'head'],
				extension: 'swift',
				fileClass: 'source',
				headPath: 'Sources/App/item-1.swift',
				isHiddenByDefault: false,
				itemId: 'item-1',
				language: 'swift',
				mimeTypes: ['text/plain'],
				provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
				reviewPriority: 'normal',
				reviewState: 'unreviewed',
			},
			{
				basePath: 'Sources/App/item-2.swift',
				changeKind: 'modified',
				contentDescriptorIdsByRole: {},
				contentHashesByRole: {},
				contentRoles: [],
				extension: 'swift',
				fileClass: 'source',
				headPath: 'Sources/App/item-2.swift',
				isHiddenByDefault: false,
				itemId: 'item-2',
				language: 'swift',
				mimeTypes: ['text/plain'],
				provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
				reviewPriority: 'normal',
				reviewState: 'unreviewed',
			},
		],
		itemWindow: { finalWindow: true, itemCount: 2, startIndex: 0, totalItemCount: 2 },
		packageId: baseDescriptor.packageId,
		publicationId: '00000000-0000-7000-8000-000000000001',
		query: {
			baseEndpointId: 'base-endpoint',
			comparisonSemantics: 'threeDot',
			fileTarget: null,
			grouping: { kind: 'folder' },
			headEndpointId: 'head-endpoint',
			pathScope: [],
			provenanceFilter: {
				agentSessionIds: [],
				operationIds: [],
				paneIds: [],
				promptIds: [],
				sourceKinds: [],
			},
			queryId: 'query-1',
			queryKind: 'compare',
			repoId: 'repo-1',
			viewFilter: {
				changeKinds: [],
				excludedExtensions: [],
				excludedFileClasses: [],
				excludedPathGlobs: [],
				includedExtensions: [],
				includedFileClasses: [],
				includedPathGlobs: [],
				reviewStates: [],
				showBinaryFiles: true,
				showHiddenFiles: false,
				showLargeFiles: true,
			},
			worktreeId: 'worktree-1',
		},
		revision: 1,
		sourceIdentity: baseDescriptor.sourceIdentity,
		summary: {
			additions: 1,
			deletions: 1,
			filesChanged: 1,
			hiddenFileCount: 0,
			visibleFileCount: 1,
		},
		treeRows: [
			{
				depth: 0,
				isDirectory: false,
				itemId: 'item-1',
				path: 'Sources/App/item-1.swift',
				rowId: 'row-item-1',
			},
			{
				depth: 0,
				isDirectory: false,
				itemId: 'item-2',
				path: 'Sources/App/item-2.swift',
				rowId: 'row-item-2',
			},
		],
		treeWindow: { finalWindow: true, rowCount: 2, startIndex: 0, totalRowCount: 2 },
	};
}

function requireReviewDescriptor(
	descriptor: BridgeWorkerReviewContentRequestDescriptor | undefined,
): BridgeWorkerReviewContentRequestDescriptor {
	if (descriptor === undefined) throw new Error('Expected Review content descriptor.');
	return descriptor;
}

async function drainScheduledPreparation(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
): Promise<void> {
	for (let round = 0; round < 8; round += 1) {
		const drain = scheduledDrains.shift();
		if (drain === undefined) return;
		// oxlint-disable-next-line no-await-in-loop -- Each drain may schedule the next bounded preparation slice.
		await drain();
		// oxlint-disable-next-line no-await-in-loop -- Continuations expose any next preparation slice deterministically.
		await flushBridgeWorkerRuntimeContinuations();
	}
	throw new Error('Expected Review preparation drains to settle within eight rounds.');
}
