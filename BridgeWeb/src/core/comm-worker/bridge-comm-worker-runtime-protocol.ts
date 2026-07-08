import { z } from 'zod';

import { sendBridgeRPCRequest, type BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import { worktreeFileSurfaceOpenSourceOutcomeSchema } from '../../features/worktree-file/models/worktree-file-protocol-models.js';
import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerDemandExecutionScheduleRequest,
	type BridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerReviewRuntimeSource,
	type BridgeCommWorkerReviewSourceUpdateScheduleRequest,
	type BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	type BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	planBridgeCommWorkerDemandExecution,
	type BridgeCommWorkerDemandBackoff,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-executor.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import {
	enqueueBridgeWorkerReviewContentReadyPreparation,
	enqueueSelectedBridgeWorkerReviewContentReadyPreparation,
} from './bridge-comm-worker-review-preparation.js';
import {
	canRenderBridgeWorkerReviewContentForSemantics,
	type BridgeWorkerReviewContentResourceFetch,
} from './bridge-comm-worker-review-runtime.js';
import {
	bridgeCommWorkerTelemetryLaneForMessage,
	bridgeWorkerRuntimeSchemeRpcCommandForMessage,
} from './bridge-comm-worker-runtime-command-routing.js';
import type {
	BridgeCommWorkerRow,
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';
import {
	recordBridgeCommWorkerTaskTelemetry,
	readBridgeCommWorkerAbsoluteNowMilliseconds,
	type BridgeCommWorkerTelemetryRecorder,
} from './bridge-comm-worker-telemetry.js';
import {
	createWorkerContentPreparationPump,
	type WorkerContentPreparationPump,
	type WorkerContentPreparationPumpRunResult,
} from './bridge-worker-content-preparation-pump.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerReviewContentRequestDescriptor,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	fetchBridgeWorkerReviewContentResource,
	type BridgeWorkerContentFetch,
} from './bridge-worker-review-content-fetch.js';

export type BridgeCommWorkerPreparationDrain = () => Promise<WorkerContentPreparationPumpRunResult>;

export interface RegisterBridgeCommWorkerRuntimePortProtocolProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly createSequence?: () => number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly maxPreparationSliceMs?: number;
	readonly now?: () => number;
	readonly pump?: WorkerContentPreparationPump;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly schedulePreparationDrain?: (drain: BridgeCommWorkerPreparationDrain) => void;
	readonly sendSchemeRpcCommand?: BridgeCommWorkerSchemeRpcCommandSender;
	readonly schemeRpcTimeoutMilliseconds?: number;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

const bridgeCommWorkerReviewSourceResetChunkItemCount = 64;
const bridgeCommWorkerSchemeRpcTimeoutMilliseconds = 5000;
const bridgeCommWorkerSchemeRpcEmptyResultSchema = z.object({}).strict();

export type BridgeCommWorkerSchemeRpcCommandSender = (
	command: BridgeRPCCommand,
) => Promise<unknown>;

export function registerBridgeCommWorkerRuntimePortProtocol(
	port: BridgeCommWorkerPort,
	props: RegisterBridgeCommWorkerRuntimePortProtocolProps,
): void {
	const createSequence = props.createSequence ?? createBridgeWorkerRuntimeSequenceCounter();
	const pump =
		props.pump ??
		createWorkerContentPreparationPump({
			maxSliceMs: props.maxPreparationSliceMs ?? 8,
			...(props.now === undefined ? {} : { now: props.now }),
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
	const schedulePreparationDrain =
		props.schedulePreparationDrain ?? scheduleDefaultBridgeCommWorkerPreparationDrain;
	const sendSchemeRpcCommand = props.sendSchemeRpcCommand ?? sendBridgeCommWorkerSchemeRpcCommand;
	const schemeRpcTimeoutMilliseconds =
		props.schemeRpcTimeoutMilliseconds ?? bridgeCommWorkerSchemeRpcTimeoutMilliseconds;
	const preparationCompletions: Promise<void>[] = [];
	let drainScheduled = false;
	let shouldRequestDrainAfterMessage = false;
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics,
		rows: props.rows,
	};
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		rows: [],
	};
	const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
		fetchContent: props.fetchContent,
	});
	const demandBackoffByItemId = new Map<string, BridgeCommWorkerDemandBackoff>();
	const demandInFlightItemIds = new Set<string>();
	const pendingVisibleDemandRerunItemIds = new Set<string>();
	const visibleDemandGenerationByItemId = new Map<string, number>();
	const markedVisibleSourceChurnKeys = new Set<string>();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;
	let activeReviewSourceResetEpoch: number | null = null;

	const drainPreparation: BridgeCommWorkerPreparationDrain = async () => {
		drainScheduled = false;
		const completions = preparationCompletions.splice(0, preparationCompletions.length);
		const runResult = pump.runUntilBudget();
		const completionResults = await Promise.allSettled(completions);
		const rejectedCompletion = completionResults.find(
			(result): result is PromiseRejectedResult => result.status === 'rejected',
		);
		if (rejectedCompletion !== undefined) {
			throw rejectedCompletion.reason;
		}
		if (pump.getPendingWorkIds().length > 0) {
			requestPreparationDrain();
		}
		return runResult;
	};

	const requestPreparationDrain = (): void => {
		if (drainScheduled) {
			return;
		}
		drainScheduled = true;
		schedulePreparationDrain(drainPreparation);
	};

	const markVisibleReviewDemandSourceChurnFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	): ReadonlySet<string> => {
		const unmarkedAffectedItemIds = request.affectedItemIds?.filter((itemId) => {
			const churnKey = `${request.epoch}:${itemId}`;
			return !markedVisibleSourceChurnKeys.has(churnKey);
		});
		const sourceChurnItemIds = markVisibleReviewDemandSourceChurn({
			affectedItemIds: unmarkedAffectedItemIds,
			cause: request.cause,
			inFlightItemIds: demandInFlightItemIds,
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		for (const itemId of sourceChurnItemIds) {
			markedVisibleSourceChurnKeys.add(`${request.epoch}:${itemId}`);
		}
		return sourceChurnItemIds;
	};

	const enqueueVisibleDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
		shouldMarkSourceChurn = true,
	): boolean => {
		latestDemandExecutionRequest = request;
		const sourceChurnItemIds = shouldMarkSourceChurn
			? markVisibleReviewDemandSourceChurnFromRequest(request)
			: new Set<string>();
		const forceExecutionItemIds = new Set([
			...sourceChurnItemIds,
			...(request.forceExecutionItemIds ?? []),
			...forcedSourceChurnItemIds,
		]);
		const tickets = enqueueVisibleBridgeCommWorkerReviewDemandExecution({
			backoffByItemId: demandBackoffByItemId,
			budget: props.budget,
			createSequence,
			epoch: request.epoch,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
			fetchReviewContentResource,
			inFlightItemIds: demandInFlightItemIds,
			nowMilliseconds: readBridgeCommWorkerRuntimeNowMilliseconds(props.now),
			pendingRerunItemIds: pendingVisibleDemandRerunItemIds,
			port,
			pump,
			requestPreparationDrain,
			requestVisibleDemandRerun: (itemId: string): void => {
				if (latestDemandExecutionRequest === null) {
					return;
				}
				if (
					enqueueVisibleDemandExecutionFromRequest(latestDemandExecutionRequest, new Set([itemId]))
				) {
					requestPreparationDrain();
				}
			},
			reviewRuntimeSource,
			sourceChurnItemIds: forceExecutionItemIds,
			store: request.store,
			visibleDemandGenerationByItemId,
		});
		let enqueued = false;
		let startedItemCount = 0;
		for (const ticket of tickets) {
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				enqueued = true;
				startedItemCount += 1;
			}
		}
		if (startedItemCount > 0) {
			void Promise.allSettled(tickets.map((ticket) => ticket.completion)).then(() => {
				if (
					enqueueVisibleDemandExecutionFromRequest(
						{ ...request, forceExecutionItemIds: [] },
						new Set(),
						false,
					)
				) {
					requestPreparationDrain();
				}
			});
		}
		return enqueued;
	};

	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics,
		rows: props.rows,
		createSequence,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		scheduleSelectedReviewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
		): void => {
			const ticket = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
				bridgeDemandRank: props.bridgeDemandRank,
				budget: props.budget,
				contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
				epoch: request.epoch,
				...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				fetchReviewContentResource,
				itemId: request.itemId,
				port,
				pump,
				renderSemantics: reviewRuntimeSource.renderSemantics,
				requestPreparationDrain,
				sequence: createSequence(),
				store: request.store,
			});
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleReviewSourceUpdate: (
			request: BridgeCommWorkerReviewSourceUpdateScheduleRequest,
		): void => {
			activeReviewSourceResetEpoch = request.epoch;
			markVisibleReviewDemandSourceChurnFromRequest({
				affectedItemIds: request.affectedItemIds,
				cause: 'reviewSourceUpdate',
				epoch: request.epoch,
				store: request.store,
			});
			const ticket = enqueueBridgeCommWorkerReviewSourceReset({
				createSequence,
				isCurrentResetEpoch: () => activeReviewSourceResetEpoch === request.epoch,
				onResetComplete: () => {
					if (activeReviewSourceResetEpoch === request.epoch) {
						activeReviewSourceResetEpoch = null;
					}
				},
				pump,
				request,
				requestPreparationDrain,
				scheduleDemandExecution: enqueueVisibleDemandExecutionFromRequest,
			});
			if (ticket.enqueued) {
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleSelectedFileViewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
		): void => {
			const ticket = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
				bridgeDemandRank: props.bridgeDemandRank,
				budget: props.budget,
				contentRequestDescriptors: fileViewRuntimeSource.contentRequestDescriptors,
				epoch: request.epoch,
				...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
				itemId: request.itemId,
				port,
				pump,
				requestPreparationDrain,
				sequence: createSequence(),
				store: request.store,
			});
			if (ticket.enqueued) {
				preparationCompletions.push(ticket.completion);
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleDemandExecution: (request: BridgeCommWorkerDemandExecutionScheduleRequest): void => {
			shouldRequestDrainAfterMessage =
				enqueueVisibleDemandExecutionFromRequest(request) || shouldRequestDrainAfterMessage;
		},
		updateReviewRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource): void => {
			reviewRuntimeSource = source;
		},
		updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource): void => {
			fileViewRuntimeSource = source;
		},
	});

	port.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const parsedMessage = bridgeWorkerMainToServerMessageSchema.safeParse(event.data);
		if (!parsedMessage.success) {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
			return;
		}

		shouldRequestDrainAfterMessage = false;
		const handlerStartedAtMilliseconds = readBridgeCommWorkerRuntimeNowMilliseconds(props.now);
		const queueWaitMilliseconds =
			handlerStartedAtMilliseconds -
			(parsedMessage.data.issuedAtMilliseconds ?? handlerStartedAtMilliseconds);
		const messages = handler.handleMessage(parsedMessage.data);
		const handlerDurationMilliseconds =
			readBridgeCommWorkerRuntimeNowMilliseconds(props.now) - handlerStartedAtMilliseconds;
		recordBridgeCommWorkerTaskTelemetry({
			command: parsedMessage.data.command,
			durationMilliseconds: handlerDurationMilliseconds,
			lane: bridgeCommWorkerTelemetryLaneForMessage(parsedMessage.data),
			queueWaitMilliseconds,
			taskKind: 'message_handler',
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		const ordinarySchemeRpcCommand = bridgeWorkerRuntimeSchemeRpcCommandForMessage(
			parsedMessage.data,
		);
		const shouldForwardOrdinarySchemeRpcCommand =
			ordinarySchemeRpcCommand !== null &&
			bridgeWorkerRuntimeMessagesContainReadyRequest({
				messages,
				requestId: ordinarySchemeRpcCommand.requestId,
			});
		const immediateMessages = shouldForwardOrdinarySchemeRpcCommand
			? messages.filter(
					(message): boolean =>
						!bridgeWorkerRuntimeMessageIsReadyRequest({
							message,
							requestId: ordinarySchemeRpcCommand.requestId,
						}),
				)
			: messages;
		for (const message of immediateMessages) {
			port.postMessage(message);
		}
		if (ordinarySchemeRpcCommand !== null && shouldForwardOrdinarySchemeRpcCommand) {
			void sendBridgeCommWorkerSchemeRpcCommandWithTimeout({
				command: ordinarySchemeRpcCommand.command,
				sendSchemeRpcCommand,
				timeoutMilliseconds: schemeRpcTimeoutMilliseconds,
			})
				.then((schemeRpcResult): void => {
					const resultEvent = buildBridgeWorkerRuntimeSchemeRpcResultEvent({
						command: ordinarySchemeRpcCommand.command,
						requestId: ordinarySchemeRpcCommand.requestId,
						schemeRpcResult,
					});
					if (resultEvent !== null) {
						port.postMessage(resultEvent);
					}
					for (const message of messages) {
						if (
							bridgeWorkerRuntimeMessageIsReadyRequest({
								message,
								requestId: ordinarySchemeRpcCommand.requestId,
							})
						) {
							port.postMessage(message);
						}
					}
				})
				.catch((error: unknown): void => {
					port.postMessage(
						buildBridgeWorkerRuntimeCommandFailedHealthEvent({
							requestId: ordinarySchemeRpcCommand.requestId,
							message: bridgeCommWorkerSchemeRpcFailureMessage({
								command: ordinarySchemeRpcCommand.command,
								error,
							}),
							...(ordinarySchemeRpcCommand.command.method === 'bridge.activeViewerMode.update'
								? { deliveryStatus: 'unknownAfterDispatch' }
								: {}),
						}),
					);
				});
		}
		if (shouldRequestDrainAfterMessage) {
			requestPreparationDrain();
		}
	});
	port.start?.();
}

function bridgeWorkerRuntimeMessagesContainReadyRequest(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly requestId: string;
}): boolean {
	return props.messages.some((message): boolean =>
		bridgeWorkerRuntimeMessageIsReadyRequest({
			message,
			requestId: props.requestId,
		}),
	);
}

function bridgeWorkerRuntimeMessageIsReadyRequest(props: {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly requestId: string;
}): boolean {
	return (
		props.message.kind === 'health' &&
		props.message.requestId === props.requestId &&
		props.message.status === 'ready'
	);
}

function buildBridgeWorkerRuntimeDegradedHealthEvent(): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		status: 'degraded',
		message: 'Bridge comm worker received invalid message.',
	};
}

function buildBridgeWorkerRuntimeCommandFailedHealthEvent(props: {
	readonly deliveryStatus?: 'unknownAfterDispatch';
	readonly message: string;
	readonly requestId: string;
}): BridgeWorkerServerToMainMessage {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		requestId: props.requestId,
		status: 'degraded',
		message: props.message,
		...(props.deliveryStatus === undefined ? {} : { deliveryStatus: props.deliveryStatus }),
	};
}

async function sendBridgeCommWorkerSchemeRpcCommand(command: BridgeRPCCommand): Promise<unknown> {
	return await sendBridgeRPCRequest({
		command,
		timeoutMilliseconds: bridgeCommWorkerSchemeRpcTimeoutMilliseconds,
	});
}

function bridgeCommWorkerSchemeRpcFailureMessage(props: {
	readonly command: BridgeRPCCommand;
	readonly error: unknown;
}): string {
	const baseMessage = `Bridge comm worker failed to forward ${props.command.method}`;
	if (
		props.command.method !== 'worktreeFileSurface.requestFileDescriptor' ||
		!(props.error instanceof Error) ||
		!bridgeCommWorkerDescriptorErrorRequiresForwardedDetail(props.error.message)
	) {
		return `${baseMessage}.`;
	}
	return `${baseMessage}: ${props.error.message}`;
}

function bridgeCommWorkerDescriptorErrorRequiresForwardedDetail(errorMessage: string): boolean {
	return (
		errorMessage.endsWith('worktree_file.source_identity_mismatch') ||
		errorMessage.endsWith('worktree_file.stale_source_generation')
	);
}

function buildBridgeWorkerRuntimeSchemeRpcResultEvent(props: {
	readonly command: BridgeRPCCommand;
	readonly requestId: string;
	readonly schemeRpcResult: unknown;
}): BridgeWorkerServerToMainMessage | null {
	if (props.command.method !== 'worktreeFileSurface.openSourceStream') {
		if (props.command.method === 'worktreeFileSurface.requestFileDescriptor') {
			bridgeCommWorkerSchemeRpcEmptyResultSchema.parse(props.schemeRpcResult);
		}
		return null;
	}
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'worktreeFileOpenSourceStreamResult',
		requestId: props.requestId,
		outcome: worktreeFileSurfaceOpenSourceOutcomeSchema.parse(props.schemeRpcResult),
	};
}

function sendBridgeCommWorkerSchemeRpcCommandWithTimeout(props: {
	readonly command: BridgeRPCCommand;
	readonly sendSchemeRpcCommand: BridgeCommWorkerSchemeRpcCommandSender;
	readonly timeoutMilliseconds: number;
}): Promise<unknown> {
	return new Promise<unknown>((resolve, reject): void => {
		let didSettle = false;
		const timeoutId = globalThis.setTimeout((): void => {
			if (didSettle) {
				return;
			}
			didSettle = true;
			reject(new Error('Bridge comm worker scheme RPC timed out.'));
		}, props.timeoutMilliseconds);
		void props.sendSchemeRpcCommand(props.command).then(
			(schemeRpcResult: unknown): void => {
				if (didSettle) {
					return;
				}
				didSettle = true;
				globalThis.clearTimeout(timeoutId);
				resolve(schemeRpcResult);
			},
			(error: unknown): void => {
				if (didSettle) {
					return;
				}
				didSettle = true;
				globalThis.clearTimeout(timeoutId);
				reject(error);
			},
		);
	});
}

function createBridgeWorkerRuntimeSequenceCounter(): () => number {
	let nextSequence = 1;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

function createSharedBridgeWorkerReviewContentResourceFetch(props: {
	readonly fetchContent: BridgeWorkerContentFetch | undefined;
}): BridgeWorkerReviewContentResourceFetch {
	const inFlightResourcesByUrl = new Map<
		string,
		ReturnType<BridgeWorkerReviewContentResourceFetch>
	>();
	return async (descriptor: BridgeWorkerReviewContentRequestDescriptor) => {
		const resourceKey = sharedBridgeWorkerReviewContentResourceKey(descriptor);
		const existingResource = inFlightResourcesByUrl.get(resourceKey);
		if (existingResource !== undefined) {
			return await existingResource;
		}
		const resourcePromise = fetchBridgeWorkerReviewContentResource({
			descriptor,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
		});
		inFlightResourcesByUrl.set(resourceKey, resourcePromise);
		try {
			return await resourcePromise;
		} finally {
			inFlightResourcesByUrl.delete(resourceKey);
		}
	};
}

function sharedBridgeWorkerReviewContentResourceKey(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): string {
	return [
		descriptor.resourceUrl,
		descriptor.itemId,
		descriptor.role,
		descriptor.contentHashAlgorithm,
		descriptor.contentHash,
		descriptor.language ?? '',
		descriptor.sizeBytes,
		descriptor.expectedBytes ?? '',
		descriptor.maxBytes,
		descriptor.isBinary,
	].join('\u0000');
}

interface EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps {
	readonly backoffByItemId: ReadonlyMap<string, BridgeCommWorkerDemandBackoff>;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly epoch: number;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
	readonly inFlightItemIds: Set<string>;
	readonly nowMilliseconds: number;
	readonly pendingRerunItemIds: Set<string>;
	readonly port: BridgeCommWorkerPort;
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain: () => void;
	readonly requestVisibleDemandRerun: (itemId: string) => void;
	readonly reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource;
	readonly sourceChurnItemIds: ReadonlySet<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: ReadonlyMap<string, number>;
}

interface EnqueuedBridgeCommWorkerDemandPreparationTicket {
	readonly completion: Promise<void>;
	readonly enqueued: boolean;
}

interface EnqueueBridgeCommWorkerReviewSourceResetProps {
	readonly createSequence: () => number;
	readonly isCurrentResetEpoch: () => boolean;
	readonly onResetComplete: () => void;
	readonly pump: WorkerContentPreparationPump;
	readonly request: BridgeCommWorkerReviewSourceUpdateScheduleRequest;
	readonly requestPreparationDrain: () => void;
	readonly scheduleDemandExecution: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => boolean;
}

function enqueueBridgeCommWorkerReviewSourceReset(
	props: EnqueueBridgeCommWorkerReviewSourceResetProps,
): EnqueuedBridgeCommWorkerDemandPreparationTicket {
	let processedItemCount = 0;
	const completion = createBridgeCommWorkerCompletion();
	const orderedItemIds = props.request.nextReviewRuntimeSource.rows.map((row) => row.id);
	const affectedItemIds = new Set(props.request.affectedItemIds);
	const work = {
		id: `review-source-reset:${props.request.epoch}`,
		rank: 'background' as const,
		telemetry: {
			payloadClass: 'source_reset',
			sourceEpoch: props.request.epoch,
			workKind: 'review_source_reset',
		},
		runSlice: (): { readonly complete: boolean; readonly continuation?: 'external' } => {
			if (!props.isCurrentResetEpoch()) {
				completion.resolve();
				return { complete: true };
			}
			processedItemCount = Math.min(
				processedItemCount + bridgeCommWorkerReviewSourceResetChunkItemCount,
				orderedItemIds.length,
			);
			const previousProcessedItemCount = Math.max(
				0,
				processedItemCount - bridgeCommWorkerReviewSourceResetChunkItemCount,
			);
			const chunkItemIds = new Set(
				orderedItemIds.slice(previousProcessedItemCount, processedItemCount),
			);
			const chunkAffectedItemIds = [...chunkItemIds].filter((itemId) =>
				affectedItemIds.has(itemId),
			);
			const resetComplete = processedItemCount >= orderedItemIds.length;
			props.request.store.actions.applyReviewSourceUpdateFact({
				contentItems: props.request.nextReviewRuntimeSource.contentItems.filter((metadata) =>
					chunkItemIds.has(metadata.itemId),
				),
				...(resetComplete ? { completeItemIds: orderedItemIds } : {}),
				resetComplete: false,
				rows: props.request.nextReviewRuntimeSource.rows.filter((row) => chunkItemIds.has(row.id)),
			});
			if (chunkAffectedItemIds.length > 0) {
				props.scheduleDemandExecution({
					affectedItemIds: chunkAffectedItemIds,
					cause: 'reviewSourceUpdate',
					epoch: props.request.epoch,
					forceExecutionItemIds: chunkAffectedItemIds,
					store: props.request.store,
				});
			}
			if (!resetComplete) {
				scheduleBridgeCommWorkerTaskBoundary(() => {
					props.pump.enqueueOrPromote(work);
					props.requestPreparationDrain();
				});
				return { complete: false, continuation: 'external' };
			}
			props.onResetComplete();
			completion.resolve();
			return { complete: true };
		},
	};
	props.pump.enqueueOrPromote(work);
	return { completion: completion.promise, enqueued: true };
}

function scheduleBridgeCommWorkerTaskBoundary(callback: () => void): void {
	setTimeout(callback, 0);
}

function createBridgeCommWorkerCompletion(): {
	readonly promise: Promise<void>;
	readonly reject: (reason: unknown) => void;
	readonly resolve: () => void;
} {
	let resolveCompletion: () => void = noopBridgeCommWorkerCompletionResolve;
	let rejectCompletion: (reason: unknown) => void = noopBridgeCommWorkerCompletionReject;
	const promise = new Promise<void>((resolve, reject) => {
		resolveCompletion = resolve;
		rejectCompletion = reject;
	});
	return {
		promise,
		reject: rejectCompletion,
		resolve: resolveCompletion,
	};
}

function noopBridgeCommWorkerCompletionResolve(): void {}

function noopBridgeCommWorkerCompletionReject(_reason: unknown): void {}

function enqueueVisibleBridgeCommWorkerReviewDemandExecution(
	props: EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps,
): readonly EnqueuedBridgeCommWorkerDemandPreparationTicket[] {
	const membership = visibleReviewDemandMembersNeedingExecutionFromState({
		forceExecutionItemIds: props.sourceChurnItemIds,
		state: props.store.getState(),
	});
	if (membership.length === 0) {
		return [];
	}
	const executionPlan = planBridgeCommWorkerDemandExecution({
		backoffByItemId: props.backoffByItemId,
		inFlightItemIds: props.inFlightItemIds,
		maxStartCount: bridgeContentDemandExecutionPolicy.immediateStartConcurrency,
		membership,
		nowMilliseconds: props.nowMilliseconds,
	});
	const tickets: EnqueuedBridgeCommWorkerDemandPreparationTicket[] = [];
	for (const itemId of executionPlan.startItemIds) {
		if (!hasReviewRuntimeSourceContent(props.reviewRuntimeSource, itemId)) {
			continue;
		}
		const visibleDemandGeneration = props.visibleDemandGenerationByItemId.get(itemId) ?? 0;
		props.inFlightItemIds.add(itemId);
		const ticket = enqueueBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: { lane: 'visible', priority: 1 },
			budget: {
				className: 'visible',
				maxBytes: props.budget.maxBytes,
				maxWindowLines: props.budget.maxWindowLines,
			},
			contentRequestDescriptors: props.reviewRuntimeSource.contentRequestDescriptors,
			demandKey: 'visible',
			epoch: props.epoch,
			...(props.fetchContent === undefined ? {} : { fetchContent: props.fetchContent }),
			...(props.fetchReviewContentResource === undefined
				? {}
				: { fetchReviewContentResource: props.fetchReviewContentResource }),
			isDemandCurrent: (): boolean =>
				(props.visibleDemandGenerationByItemId.get(itemId) ?? 0) === visibleDemandGeneration,
			itemId,
			port: props.port,
			preparationRank: 'visible',
			pump: props.pump,
			renderSemantics: props.reviewRuntimeSource.renderSemantics,
			requestPreparationDrain: props.requestPreparationDrain,
			sequence: props.createSequence(),
			store: props.store,
		});
		const completion = ticket.completion.finally(() => {
			props.inFlightItemIds.delete(itemId);
			if (props.pendingRerunItemIds.delete(itemId)) {
				props.requestVisibleDemandRerun(itemId);
			}
		});
		if (!ticket.enqueued) {
			props.inFlightItemIds.delete(itemId);
			tickets.push({ completion, enqueued: false });
			continue;
		}
		tickets.push({ completion, enqueued: true });
	}
	return tickets;
}

function visibleReviewDemandMembersNeedingExecutionFromState(props: {
	readonly forceExecutionItemIds: ReadonlySet<string>;
	readonly state: BridgeCommWorkerStoreState;
}): readonly BridgeCommWorkerDemandMember[] {
	const membership: BridgeCommWorkerDemandMember[] = [];
	for (const itemId of visibleReviewDemandItemIdsFromState(props.state)) {
		if (
			!props.forceExecutionItemIds.has(itemId) &&
			!doesVisibleReviewDemandNeedExecution(props.state, itemId)
		) {
			continue;
		}
		membership.push({ itemId, role: 'visible' });
	}
	return membership;
}

function visibleReviewDemandItemIdsFromState(state: BridgeCommWorkerStoreState): readonly string[] {
	const itemIds: string[] = [];
	for (const [itemId, demandKey] of state.demandByKey) {
		if (demandKey !== 'visible') {
			continue;
		}
		const metadata = state.contentMetadataByItemId.get(itemId) ?? null;
		if (metadata === null || !('availableContentRoles' in metadata)) {
			continue;
		}
		itemIds.push(itemId);
	}
	return itemIds;
}

function doesVisibleReviewDemandNeedExecution(
	state: BridgeCommWorkerStoreState,
	itemId: string,
): boolean {
	const availability = state.availabilityByItemId.get(itemId);
	return availability !== 'ready' && availability !== 'failed' && availability !== 'unavailable';
}

function markVisibleReviewDemandSourceChurn(props: {
	readonly affectedItemIds: readonly string[] | undefined;
	readonly cause: BridgeCommWorkerDemandExecutionScheduleRequest['cause'];
	readonly inFlightItemIds: ReadonlySet<string>;
	readonly pendingRerunItemIds: Set<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: Map<string, number>;
}): ReadonlySet<string> {
	if (props.cause !== 'reviewInvalidate' && props.cause !== 'reviewSourceUpdate') {
		return new Set();
	}
	const affectedItemIds =
		props.affectedItemIds === undefined
			? visibleReviewDemandItemIdsFromState(props.store.getState())
			: props.affectedItemIds;
	const affectedItemIdSet = new Set(affectedItemIds);
	const churnedVisibleItemIds = new Set<string>();
	for (const itemId of visibleReviewDemandItemIdsFromState(props.store.getState())) {
		if (!affectedItemIdSet.has(itemId)) {
			continue;
		}
		churnedVisibleItemIds.add(itemId);
		props.visibleDemandGenerationByItemId.set(
			itemId,
			(props.visibleDemandGenerationByItemId.get(itemId) ?? 0) + 1,
		);
		if (props.inFlightItemIds.has(itemId)) {
			props.pendingRerunItemIds.add(itemId);
		}
	}
	return churnedVisibleItemIds;
}

function hasReviewRuntimeSourceContent(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): boolean {
	const semantics = source.renderSemantics.find((candidate) => candidate.itemId === itemId) ?? null;
	return (
		source.contentItems.some((metadata) => metadata.itemId === itemId) &&
		semantics !== null &&
		canRenderBridgeWorkerReviewContentForSemantics({
			descriptors: source.contentRequestDescriptors,
			semantics,
		})
	);
}

function readBridgeCommWorkerRuntimeNowMilliseconds(now: (() => number) | undefined): number {
	if (now !== undefined) {
		return now();
	}
	return readBridgeCommWorkerAbsoluteNowMilliseconds();
}

function scheduleDefaultBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain,
): void {
	queueMicrotask(() => {
		void drain();
	});
}
