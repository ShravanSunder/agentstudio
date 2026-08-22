import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	buildBridgeWorkerReviewCandidateReadyEvent,
	buildBridgeWorkerReviewPublicationInstallAdmissionEvent,
} from './bridge-comm-worker-protocol.js';
import { makeReviewPublication } from './bridge-main-render-fulfillment-coordinator.test-support.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainReviewPublicationIdentity,
} from './bridge-main-render-snapshot-store.js';
import {
	createBridgeMainReviewPublicationIntegration,
	type BridgeMainReviewPublicationIntegration,
} from './bridge-main-review-publication-integration.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { bridgeWorkerReviewSourceContext } from './bridge-worker-review-display.test-support.js';
import { createBridgeWorkerRpcClient } from './bridge-worker-rpc-client.js';
import { createBridgeWorkerRpcLifecycleStore } from './bridge-worker-rpc-lifecycle-store.js';

const ACTIVE = reviewIdentity(1, '11');
const CANDIDATE = reviewIdentity(2, '12');
const SUCCESSOR = reviewIdentity(3, '13');

describe('Bridge main Review publication integration', () => {
	test('applies exact-active projection patches without staging a successor candidate', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');

		// Act
		harness.receive({
			...reviewDisplayEvent(ACTIVE, 'item-active-query'),
			projectionRevision: 2,
			sequence: 2,
		});

		// Assert
		expect(harness.store.getReviewItemSnapshot('item-active-query')).toBeDefined();
		expect(harness.store.getReviewRefreshPresentation()).toEqual({
			activeIdentity: mainIdentity(ACTIVE),
			candidate: null,
		});
		expect(harness.pendingCommandCount('reviewPublicationInstallAdmit')).toBe(0);
		harness.dispose();
	});

	test('routes render work from a newer exact-active worker derivation epoch', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');
		const activeDisplayEvent = {
			...reviewDisplayEvent(ACTIVE, 'item-active-query'),
			epoch: 2,
			projectionRevision: 2,
			sequence: 2,
		};

		// Act
		harness.receive(activeDisplayEvent);
		harness.receive({
			...reviewRenderPatch(ACTIVE, 'item-active-query'),
			workerDerivationEpoch: 2,
		});
		harness.receive({
			...reviewPierrePublication(ACTIVE, 'item-active-query', 14),
			workerDerivationEpoch: 2,
		});

		// Assert
		expect(harness.store.getReviewCodeViewItemSnapshot('item-active-query')).toBeDefined();
		expect(harness.courierJobs.map((job) => job.itemId)).toContain('item-active-query');
		harness.dispose();
	});

	test('orders real RPC display, ready, admission, promotion, installed, and acknowledgement', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');

		// Act
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
		harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
		const admission = await harness.nextCommand('reviewPublicationInstallAdmit');

		// Assert
		expect(harness.store.getReviewItemSnapshot('item-a')).toBeDefined();
		expect(harness.store.getReviewItemSnapshot('item-b')).toBeUndefined();
		expect(admission).toMatchObject({
			candidatePublicationId: CANDIDATE.publicationId,
			expectedDisplayedPublicationId: ACTIVE.publicationId,
		});

		// Act
		harness.admit(admission, CANDIDATE, 'admitted');
		const installed = await harness.nextCommand('reviewPublicationInstalled');

		// Assert
		expect(harness.store.getReviewRefreshPresentation()).toEqual({
			activeIdentity: mainIdentity(CANDIDATE),
			candidate: null,
		});
		expect(harness.store.getReviewItemSnapshot('item-b')).toBeDefined();
		expect(installed).toMatchObject({
			packageId: CANDIDATE.packageId,
			publicationId: CANDIDATE.publicationId,
			reviewGeneration: CANDIDATE.reviewGeneration,
			revision: CANDIDATE.revision,
			sourceIdentity: CANDIDATE.sourceIdentity,
		});

		// Act
		harness.ack(installed);
		await harness.integration.whenSettled();

		// Assert
		expect(harness.commandKinds.slice(-2)).toEqual([
			'reviewPublicationInstallAdmit',
			'reviewPublicationInstalled',
		]);
		harness.dispose();
	});

	test('allocates install admission and installed receipt from the main command epoch', async () => {
		// Arrange
		const harness = createHarness();
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));

		// Act
		harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
		const admission = await harness.nextCommand('reviewPublicationInstallAdmit');

		// Assert
		expect(admission.epoch).toBe(101);

		// Act
		harness.admit(admission, CANDIDATE, 'admitted');
		const installed = await harness.nextCommand('reviewPublicationInstalled');

		// Assert
		expect(installed.epoch).toBe(102);
		harness.dispose();
	});

	test('accepts one synchronous install-admission response without retaining later responses', async () => {
		// Arrange
		const harness = createHarness({ synchronousAdmissionStatus: 'admitted' });
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));

		// Act
		harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
		const installed = await harness.nextCommand('reviewPublicationInstalled');
		harness.ack(installed);
		await harness.integration.whenSettled();

		// Assert
		expect(harness.store.getReviewRefreshPresentation().activeIdentity).toEqual(
			mainIdentity(CANDIDATE),
		);
		harness.dispose();
	});

	test('holds promoted work with injected attention and Apply now installs the newest candidate', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');
		harness.integration.setSemanticAttention({ stableFileIdentities: ['file-b'] });
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
		harness.receive(candidateReady(CANDIDATE, 'promoted', ['file-b']));
		await harness.integration.whenSettled();

		// Assert
		expect(harness.store.getReviewRefreshPresentation().candidate).toMatchObject({
			identity: mainIdentity(CANDIDATE),
			role: 'updateReady',
		});
		expect(harness.pendingCommandCount('reviewPublicationInstallAdmit')).toBe(0);

		// Arrange successor before action commit
		harness.receive(reviewDisplayEvent(SUCCESSOR, 'item-c'));
		harness.integration.setSemanticAttention({ stableFileIdentities: ['file-c'] });
		harness.receive(candidateReady(SUCCESSOR, 'promoted', ['file-c']));
		await harness.integration.whenSettled();

		// Act
		const apply = harness.integration.applyNow();
		const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
		if (admission.command !== 'reviewPublicationInstallAdmit') {
			throw new Error('Expected Review publication install admission command.');
		}
		expect(admission.candidatePublicationId).toBe(SUCCESSOR.publicationId);
		harness.admit(admission, SUCCESSOR, 'admitted');
		const installed = await harness.nextCommand('reviewPublicationInstalled');
		harness.ack(installed);
		await apply;

		// Assert
		expect(harness.store.getReviewRefreshPresentation().activeIdentity).toEqual(
			mainIdentity(SUCCESSOR),
		);
		harness.dispose();
	});

	test('keeps candidate render and Pierre state off active A, drops B on C, and flushes C on promotion', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));

		// Act
		harness.receive(reviewRenderPatch(CANDIDATE, 'item-b'));
		harness.receive(reviewPierrePublication(CANDIDATE, 'item-b', 21));

		// Assert
		expect(harness.store.getReviewItemSnapshot('item-a')).toBeDefined();
		expect(harness.store.getReviewItemSnapshot('item-b')).toBeUndefined();
		expect(harness.store.getReviewCodeViewItemSnapshot('item-b')).toBeUndefined();
		expect(harness.courierJobs).toEqual([]);

		// Act
		harness.receive(reviewDisplayEvent(SUCCESSOR, 'item-c'));
		harness.receive(reviewRenderPatch(SUCCESSOR, 'item-c'));
		harness.receive(reviewPierrePublication(SUCCESSOR, 'item-c', 22));
		harness.receive(candidateReady(SUCCESSOR, 'ordinary', []));
		const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
		harness.admit(admission, SUCCESSOR, 'admitted');
		const installed = await harness.nextCommand('reviewPublicationInstalled');

		// Assert
		expect(harness.rejectedItemIds).toContain('item-b');
		expect(harness.courierJobs.map((job) => job.itemId)).toEqual(['item-c']);
		expect(harness.store.getReviewCodeViewItemSnapshot('item-c')).toBeDefined();
		expect(harness.store.getReviewAvailabilitySnapshot('item-c')).toEqual({ state: 'ready' });

		// Act
		harness.ack(installed);
		await harness.integration.whenSettled();
		harness.dispose();
	});

	test('worker replacement discards candidate work and a late admission cannot promote it', async () => {
		// Arrange
		const harness = createHarness();
		await installPublication(harness, ACTIVE, 'item-a');
		harness.receive(reviewDisplayEvent(CANDIDATE, 'item-b'));
		harness.receive(reviewPierrePublication(CANDIDATE, 'item-b', 31));
		harness.receive(candidateReady(CANDIDATE, 'ordinary', []));
		const admission = await harness.nextCommand('reviewPublicationInstallAdmit');

		// Act
		harness.store.prepareForWorkerReplacement();
		harness.fail(admission);
		harness.admit(admission, CANDIDATE, 'admitted');
		await harness.integration.whenSettled();

		// Assert
		expect(harness.store.getReviewRefreshPresentation()).toEqual({
			activeIdentity: mainIdentity(ACTIVE),
			candidate: null,
		});
		expect(harness.rejectedItemIds).toContain('item-b');
		expect(harness.pendingCommandCount('reviewPublicationInstalled')).toBe(0);
		expect(
			harness.telemetrySamples.some(
				(sample): boolean =>
					sample.stringAttributes['agentstudio.bridge.phase'] ===
						'review_refresh_cleanup_terminal' &&
					sample.stringAttributes['agentstudio.bridge.result_reason'] === 'worker_replacement',
			),
		).toBe(true);
		harness.dispose();
	});
});

interface ReviewIdentity {
	readonly packageId: string;
	readonly publicationId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly sourceIdentity: string;
}

interface Harness {
	readonly commandKinds: readonly string[];
	readonly courierJobs: Array<BridgeWorkerReviewPierreRenderJobEvent['job']>;
	readonly integration: BridgeMainReviewPublicationIntegration;
	readonly rejectedItemIds: string[];
	readonly store: ReturnType<typeof createBridgeMainRenderSnapshotStore>;
	readonly telemetrySamples: readonly BridgeTelemetrySample[];
	readonly ack: (command: BridgeWorkerMainToServerMessage) => void;
	readonly admit: (
		command: BridgeWorkerMainToServerMessage,
		identity: ReviewIdentity,
		status: 'admitted' | 'rejected',
	) => void;
	readonly dispose: () => void;
	readonly fail: (command: BridgeWorkerMainToServerMessage) => void;
	readonly nextCommand: (
		kind: BridgeWorkerMainToServerMessage['command'],
	) => Promise<BridgeWorkerMainToServerMessage>;
	readonly pendingCommandCount: (kind: BridgeWorkerMainToServerMessage['command']) => number;
	readonly receive: (message: BridgeWorkerServerToMainMessage) => void;
}

function createHarness(
	options: {
		readonly synchronousAdmissionStatus?: 'admitted' | 'rejected';
	} = {},
): Harness {
	let commandEpoch = 100;
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	const commandQueue: BridgeWorkerMainToServerMessage[] = [];
	const commandWaiters = new Map<
		BridgeWorkerMainToServerMessage['command'],
		Array<(command: BridgeWorkerMainToServerMessage) => void>
	>();
	const commandKinds: string[] = [];
	let receiveSynchronousAdmission = (_command: BridgeWorkerMainToServerMessage): void => {};
	const rpcClient = createBridgeWorkerRpcClient({
		dispatch: (command): void => {
			commandKinds.push(command.command);
			const waiter = commandWaiters.get(command.command)?.shift();
			if (waiter === undefined) commandQueue.push(command);
			else waiter(command);
			if (
				command.command === 'reviewPublicationInstallAdmit' &&
				options.synchronousAdmissionStatus !== undefined
			) {
				receiveSynchronousAdmission(command);
			}
		},
		lifecycleStore,
		requestTimeoutMilliseconds: 60_000,
		surface: 'review',
	});
	receiveSynchronousAdmission = (command): void => {
		if (command.command !== 'reviewPublicationInstallAdmit') return;
		rpcClient.receive(
			buildBridgeWorkerReviewPublicationInstallAdmissionEvent({
				candidatePublicationId: command.candidatePublicationId,
				requestId: command.requestId,
				status: options.synchronousAdmissionStatus ?? 'rejected',
			}),
		);
	};
	const store = createBridgeMainRenderSnapshotStore();
	const courierJobs: Array<BridgeWorkerReviewPierreRenderJobEvent['job']> = [];
	const rejectedItemIds: string[] = [];
	const telemetrySamples: BridgeTelemetrySample[] = [];
	const integration = createBridgeMainReviewPublicationIntegration({
		client: {
			lifecycle: {
				getSnapshot: rpcClient.getLifecycleSnapshot,
				subscribe: lifecycleStore.subscribe,
			},
			send: rpcClient.send,
		},
		nextCommandEpoch: (): number => {
			commandEpoch += 1;
			return commandEpoch;
		},
		pierreCourier: {
			submit: (job): void => {
				courierJobs.push(job);
			},
		},
		renderFulfillmentCoordinator: {
			acceptPublication: (): 'accepted' => 'accepted',
			bindPublicationItem: vi.fn(),
			markPublicationQueued: vi.fn(),
			rejectPublication: (publication): void => {
				rejectedItemIds.push(publication.job.itemId);
			},
		},
		store,
		telemetryRecorder: {
			flush: (): boolean => true,
			isEnabled: (): boolean => true,
			measure: <TResult>(props: { readonly operation: () => TResult }): TResult =>
				props.operation(),
			record: (sample): void => {
				telemetrySamples.push(sample);
			},
		},
	});
	integration.start();
	const unsubscribe = rpcClient.subscribe((message): void => {
		integration.handleMessage(message);
	});
	const receive = (message: BridgeWorkerServerToMainMessage): void => {
		rpcClient.receive(message);
	};
	return {
		ack: (command): void => {
			receive({
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: command.requestId,
				status: 'ready',
				transferDescriptors: [],
				wireVersion: 1,
			});
		},
		admit: (command, identity, status): void => {
			receive(
				buildBridgeWorkerReviewPublicationInstallAdmissionEvent({
					candidatePublicationId: identity.publicationId,
					requestId: command.requestId,
					status,
				}),
			);
		},
		commandKinds,
		courierJobs,
		dispose: (): void => {
			integration.dispose();
			unsubscribe();
			rpcClient.dispose();
			store.dispose();
			lifecycleStore.dispose();
		},
		fail: (command): void => {
			receive({
				direction: 'serverWorkerToMain',
				kind: 'health',
				message: 'worker replaced',
				requestId: command.requestId,
				status: 'degraded',
				transferDescriptors: [],
				wireVersion: 1,
			});
		},
		integration,
		nextCommand: (kind): Promise<BridgeWorkerMainToServerMessage> => {
			const queuedIndex = commandQueue.findIndex((command) => command.command === kind);
			if (queuedIndex >= 0) {
				const queuedCommand = commandQueue.splice(queuedIndex, 1)[0];
				if (queuedCommand === undefined) throw new Error('Expected queued Bridge command.');
				return Promise.resolve(queuedCommand);
			}
			return new Promise((resolve) => {
				const waiters = commandWaiters.get(kind) ?? [];
				waiters.push(resolve);
				commandWaiters.set(kind, waiters);
			});
		},
		pendingCommandCount: (kind): number =>
			commandQueue.filter((command) => command.command === kind).length,
		receive,
		rejectedItemIds,
		store,
		telemetrySamples,
	};
}

async function installPublication(
	harness: Harness,
	identity: ReviewIdentity,
	itemId: string,
): Promise<void> {
	harness.receive(reviewDisplayEvent(identity, itemId));
	harness.receive(candidateReady(identity, 'ordinary', []));
	const admission = await harness.nextCommand('reviewPublicationInstallAdmit');
	harness.admit(admission, identity, 'admitted');
	const installed = await harness.nextCommand('reviewPublicationInstalled');
	harness.ack(installed);
	await harness.integration.whenSettled();
}

function reviewIdentity(reviewGeneration: number, suffix: string): ReviewIdentity {
	return {
		packageId: `package-${reviewGeneration}`,
		publicationId: `00000000-0000-7000-8000-${suffix.padStart(12, '0')}`,
		reviewGeneration,
		revision: 1,
		sourceIdentity: 'same-source',
	};
}

function mainIdentity(identity: ReviewIdentity): BridgeMainReviewPublicationIdentity {
	return {
		generation: identity.reviewGeneration,
		packageId: identity.packageId,
		publicationId: identity.publicationId,
		revision: identity.revision,
		sourceIdentity: identity.sourceIdentity,
	};
}

function candidateReady(
	identity: ReviewIdentity,
	presentationClass: 'ordinary' | 'promoted',
	affectedStableFileIdentities: readonly string[],
): ReturnType<typeof buildBridgeWorkerReviewCandidateReadyEvent> {
	return buildBridgeWorkerReviewCandidateReadyEvent({
		affectedStableFileIdentities,
		epoch: identity.reviewGeneration,
		packageId: identity.packageId,
		preDeliveryPresentationClass:
			presentationClass === 'ordinary'
				? { kind: 'ordinary' }
				: { kind: 'promoted', reason: 'files' },
		publicationId: identity.publicationId,
		reviewGeneration: identity.reviewGeneration,
		revision: identity.revision,
		sequence: identity.reviewGeneration,
		sourceIdentity: identity.sourceIdentity,
	});
}

function reviewDisplayEvent(
	identity: ReviewIdentity,
	itemId: string,
): BridgeWorkerReviewDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: identity.reviewGeneration,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					...bridgeWorkerReviewSourceContext(identity.packageId),
					metadataSourceId: identity.sourceIdentity,
					metadataWindowIdentity: `window-${identity.publicationId}`,
					packageId: identity.packageId,
					reviewGeneration: identity.reviewGeneration,
					revision: identity.revision,
					status: 'ready',
					summary: {
						additions: 1,
						deletions: 0,
						filesChanged: 1,
						hiddenFileCount: 0,
						visibleFileCount: 1,
					},
					totalItemCount: 1,
					totalTreeRowCount: 1,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: [reviewItem(itemId)],
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: true,
					windows: [
						{
							rows: [
								{
									depth: 0,
									isDirectory: false,
									itemId,
									path: `${itemId}.ts`,
									rowId: `row-${itemId}`,
								},
							],
							startIndex: 0,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: identity.reviewGeneration,
		reviewPublicationIdentity: identity,
		sequence: identity.reviewGeneration,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function reviewItem(itemId: string): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			additions: 1,
			deletions: 0,
			basePath: `${itemId}.ts`,
			changeKind: 'modified' as const,
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			extension: 'ts',
			fileClass: 'source' as const,
			headPath: `${itemId}.ts`,
			isHiddenByDefault: false,
			itemId,
			language: 'typescript',
			mimeTypes: ['text/typescript'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal' as const,
			reviewState: 'unreviewed' as const,
		},
		metadataWindowIdentity: `window-${itemId}`,
	};
}

function reviewRenderPatch(
	identity: ReviewIdentity,
	itemId: string,
): Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'reviewRenderPatch' }> {
	return {
		direction: 'serverWorkerToMain',
		kind: 'reviewRenderPatch',
		patches: [
			{
				itemId,
				operation: 'upsert',
				payload: { state: 'ready' },
				slice: 'contentAvailability',
			},
		],
		publicationSequence: identity.reviewGeneration,
		reviewPublicationIdentity: identity,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: identity.reviewGeneration,
	};
}

function reviewPierrePublication(
	identity: ReviewIdentity,
	itemId: string,
	publicationSequence: number,
): BridgeWorkerReviewPierreRenderJobEvent {
	const publication = makeReviewPublication({
		itemId,
		publicationSequence,
		reviewPublicationIdentity: identity,
	});
	return {
		...publication,
		publicationSequence,
		renderReceiptIdentity: {
			...publication.renderReceiptIdentity,
			publicationSequence,
			workerDerivationEpoch: identity.reviewGeneration,
		},
		workerDerivationEpoch: identity.reviewGeneration,
	};
}
