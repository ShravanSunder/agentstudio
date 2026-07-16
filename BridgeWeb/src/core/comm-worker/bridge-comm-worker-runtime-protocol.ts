import { bridgeContentDemandExecutionPolicy } from '../demand/bridge-content-demand-policy.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerDemandExecutionScheduleRequest,
	type BridgeCommWorkerFileMetadataDemand,
	type BridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerReviewRuntimeSource,
	type BridgeCommWorkerReviewMetadataResetScheduleRequest,
	type BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	type BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	planBridgeCommWorkerDemandExecution,
	type BridgeCommWorkerDemandBackoff,
	type BridgeCommWorkerDemandMember,
} from './bridge-comm-worker-executor.js';
import { BridgeCommWorkerFileDisplayEventAuthority } from './bridge-comm-worker-file-display-event-authority.js';
import { BridgeCommWorkerFileMetadataProjection } from './bridge-comm-worker-file-metadata-projection.js';
import {
	applyBridgeCommWorkerFileQueryUpdateCommand,
	BridgeCommWorkerFileQueryProjection,
} from './bridge-comm-worker-file-query-projection.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { BridgeCommWorkerReviewMetadataApplicator } from './bridge-comm-worker-review-metadata-applicator.js';
import {
	enqueueBridgeWorkerReviewContentReadyPreparation,
	enqueueSelectedBridgeWorkerReviewContentReadyPreparation,
	selectedReviewPreparationIdentity,
	type BridgeWorkerReviewContentReadyPreparationTicket,
} from './bridge-comm-worker-review-preparation.js';
import { canRenderBridgeWorkerReviewContentForSemantics } from './bridge-comm-worker-review-runtime.js';
import {
	enqueueBridgeCommWorkerReviewSourceReset,
	type EnqueuedBridgeCommWorkerDemandPreparationTicket,
} from './bridge-comm-worker-review-source-reset.js';
import {
	bridgeCommWorkerTelemetryLaneForMessage,
	bridgeWorkerRuntimeProductControlCommandForMessage,
} from './bridge-comm-worker-runtime-command-routing.js';
import {
	bridgeWorkerRuntimeMessagesContainReadyRequest,
	bridgeWorkerRuntimeMessageIsReadyRequest,
	buildBridgeWorkerFileMetadataFailureHealthEvent,
	buildBridgeWorkerFileMetadataInterestFailureHealthEvent,
	buildBridgeWorkerRuntimeCommandFailedHealthEvent,
	buildBridgeWorkerRuntimeDegradedHealthEvent,
} from './bridge-comm-worker-runtime-health.js';
import {
	bridgeProductMetadataStreamHealthDiagnostic,
	readBridgeCommWorkerRuntimeNowMilliseconds,
	scheduleDefaultBridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-support.js';
import type {
	BridgeCommWorkerStore,
	BridgeCommWorkerStoreState,
} from './bridge-comm-worker-store.js';
import {
	recordBridgeCommWorkerTaskTelemetry,
	type BridgeCommWorkerTelemetryRecorder,
} from './bridge-comm-worker-telemetry.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	createWorkerContentPreparationPump,
	type WorkerContentPreparationPump,
	type WorkerContentPreparationPumpRunResult,
} from './bridge-worker-content-preparation-pump.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerReviewDisplayPatchEventSchema,
	type BridgeWorkerReviewDisplayPatch,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFileViewContentOpen } from './bridge-worker-file-view-content-fetch.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import {
	createSharedBridgeWorkerReviewContentResourceFetch,
	type BridgeWorkerReviewContentOpen,
	type BridgeWorkerReviewContentResourceFetch,
} from './bridge-worker-review-content-fetch.js';

export type BridgeCommWorkerPreparationDrain = () => Promise<WorkerContentPreparationPumpRunResult>;

export interface RegisterBridgeCommWorkerRuntimePortProtocolProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly fileViewBridgeDemandRank?: BridgeWorkerDemandRank;
	readonly fileViewBudget?: BridgeWorkerPierreRenderBudget;
	readonly createSequence?: () => number;
	readonly maxPreparationSliceMs?: number;
	readonly now?: () => number;
	readonly openFileViewContent?: BridgeWorkerFileViewContentOpen;
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
	readonly pump?: WorkerContentPreparationPump;
	readonly productTransport?: BridgeProductTransportSession;
	readonly renderFulfillmentContext?: {
		readonly paneSessionId: string;
		readonly workerInstanceId: string;
	};
	readonly schedulePreparationDrain?: (drain: BridgeCommWorkerPreparationDrain) => void;
	readonly sendProductControl?: BridgeCommWorkerProductControlSender;
	readonly productControlTimeoutMilliseconds?: number;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

const bridgeCommWorkerProductControlTimeoutMilliseconds = 5000;
export type BridgeCommWorkerProductControlSender = (
	command: BridgeProductControlCommand,
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
	let sendProductControl = props.sendProductControl ?? rejectUninstalledBridgeProductControl;
	const productTransport = props.productTransport;
	const openFileViewContent: BridgeWorkerFileViewContentOpen =
		props.openFileViewContent ??
		(productTransport === undefined
			? rejectUninstalledBridgeFileContentOpen
			: (descriptor, abortSignal) => productTransport.openContent(descriptor, abortSignal));
	const openReviewContent: BridgeWorkerReviewContentOpen | undefined =
		props.openReviewContent ??
		(productTransport === undefined
			? undefined
			: (descriptor, abortSignal) => productTransport.openContent(descriptor, abortSignal));
	const productControlTimeoutMilliseconds =
		props.productControlTimeoutMilliseconds ?? bridgeCommWorkerProductControlTimeoutMilliseconds;
	const preparationCompletions: Promise<void>[] = [];
	let drainScheduled = false;
	let shouldRequestDrainAfterMessage = false;
	let reviewRuntimeSource: BridgeCommWorkerReviewRuntimeSource = {
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		rows: [],
	};
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequests: [],
		contentRequestsByItemId: new Map(),
		filePathsByItemId: new Map(),
		rows: [],
		rowIndexByItemId: new Map(),
		rowsByIndex: new Map(),
	};
	const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
		openContent: openReviewContent,
	});
	const demandBackoffByItemId = new Map<string, BridgeCommWorkerDemandBackoff>();
	const fileContentAbortControllersByItemId = new Map<string, AbortController>();
	const fileContentPreparationGenerationByItemId = new Map<string, number>();
	const abortFileContentPreparation = (itemId: string): void => {
		const abortController = fileContentAbortControllersByItemId.get(itemId);
		if (abortController === undefined) {
			return;
		}
		fileContentPreparationGenerationByItemId.set(
			itemId,
			(fileContentPreparationGenerationByItemId.get(itemId) ?? 0) + 1,
		);
		fileContentAbortControllersByItemId.delete(itemId);
		abortController.abort();
	};
	const abortAllFileContentPreparations = (): void => {
		for (const itemId of fileContentAbortControllersByItemId.keys()) {
			abortFileContentPreparation(itemId);
		}
	};
	const demandInFlightItemIds = new Set<string>();
	const pendingVisibleDemandRerunItemIds = new Set<string>();
	const visibleDemandGenerationByItemId = new Map<string, number>();
	const markedVisibleSourceChurnKeys = new Set<string>();
	const activeSelectedReviewPreparationByItemId = new Map<
		string,
		{
			readonly identity: string;
			readonly ticket: BridgeWorkerReviewContentReadyPreparationTicket;
		}
	>();
	let latestDemandExecutionRequest: BridgeCommWorkerDemandExecutionScheduleRequest | null = null;
	let activeReviewSourceResetEpoch: number | null = null;
	let activeReviewWorkerDerivationEpoch: number | null = null;
	let activeFileWorkerDerivationEpoch: number | null = null;
	const fileDisplayEventAuthority = new BridgeCommWorkerFileDisplayEventAuthority({
		createSequence,
	});
	let reviewDisplayProjectionRevision = 0;
	const publishReviewDisplayPatches = (publication: {
		readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
		readonly workerDerivationEpoch: number;
	}): void => {
		reviewDisplayProjectionRevision += 1;
		port.postMessage(
			bridgeWorkerReviewDisplayPatchEventSchema.parse({
				direction: 'serverWorkerToMain',
				epoch: publication.workerDerivationEpoch,
				kind: 'reviewDisplayPatch',
				patches: publication.patches,
				projectionRevision: reviewDisplayProjectionRevision,
				sequence: createSequence(),
				surface: 'review',
				transferDescriptors: [],
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			}),
		);
	};
	const fileQueryProjection = new BridgeCommWorkerFileQueryProjection();
	let updateFileMetadataDemand: ((demand: BridgeCommWorkerFileMetadataDemand) => void) | null =
		null;
	let productController: BridgeCommWorkerProductController | null = null;

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
			const churnKey = `${request.sourceChurnRevision ?? request.epoch}:${itemId}`;
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
			markedVisibleSourceChurnKeys.add(`${request.sourceChurnRevision ?? request.epoch}:${itemId}`);
		}
		return sourceChurnItemIds;
	};

	const enqueueVisibleDemandExecutionFromRequest = (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
		forcedSourceChurnItemIds: ReadonlySet<string> = new Set(),
		shouldMarkSourceChurn = true,
	): boolean => {
		latestDemandExecutionRequest = request;
		const workerDerivationEpoch =
			productTransport === undefined ? request.epoch : activeReviewWorkerDerivationEpoch;
		if (workerDerivationEpoch === null) {
			return false;
		}
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
			...(openReviewContent === undefined ? {} : { openContent: openReviewContent }),
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
			workerDerivationEpoch,
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

	const scheduleSelectedReviewContentReadyPreparation = (
		request: BridgeCommWorkerSelectedReviewContentReadyPreparationRequest,
	): void => {
		const workerDerivationEpoch =
			productTransport === undefined ? request.epoch : activeReviewWorkerDerivationEpoch;
		if (workerDerivationEpoch === null) {
			return;
		}
		const preparationIdentity = selectedReviewPreparationIdentity({
			epoch: request.epoch,
			itemId: request.itemId,
			source: reviewRuntimeSource,
			workerDerivationEpoch,
		});
		const activePreparation = activeSelectedReviewPreparationByItemId.get(request.itemId);
		if (activePreparation?.identity === preparationIdentity) {
			return;
		}
		activePreparation?.ticket.cancel();
		const ticket = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: props.bridgeDemandRank,
			budget: props.budget,
			contentRequestDescriptors: reviewRuntimeSource.contentRequestDescriptors,
			epoch: request.epoch,
			...(openReviewContent === undefined ? {} : { openContent: openReviewContent }),
			fetchReviewContentResource,
			itemId: request.itemId,
			port,
			pump,
			renderSemantics: reviewRuntimeSource.renderSemantics,
			requestPreparationDrain,
			sequence: createSequence(),
			store: request.store,
			workerDerivationEpoch,
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		if (ticket.enqueued) {
			activeSelectedReviewPreparationByItemId.set(request.itemId, {
				identity: preparationIdentity,
				ticket,
			});
			const trackedCompletion = ticket.completion.finally(() => {
				if (activeSelectedReviewPreparationByItemId.get(request.itemId)?.ticket === ticket) {
					activeSelectedReviewPreparationByItemId.delete(request.itemId);
				}
			});
			preparationCompletions.push(trackedCompletion);
			shouldRequestDrainAfterMessage = true;
		}
	};

	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		rows: [],
		createSequence,
		...(props.renderFulfillmentContext === undefined
			? {}
			: { renderFulfillmentContext: props.renderFulfillmentContext }),
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		scheduleSelectedReviewContentReadyPreparation,
		scheduleReviewMetadataReset: (
			request: BridgeCommWorkerReviewMetadataResetScheduleRequest,
		): void => {
			activeReviewSourceResetEpoch = request.epoch;
			markVisibleReviewDemandSourceChurnFromRequest({
				affectedItemIds: request.affectedItemIds,
				cause: request.cause,
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
				scheduleSelectedReviewContentReadyPreparation,
			});
			if (ticket.enqueued) {
				shouldRequestDrainAfterMessage = true;
			}
		},
		scheduleSelectedFileViewContentReadyPreparation: (
			request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
		): void => {
			const workerDerivationEpoch = activeFileWorkerDerivationEpoch;
			if (workerDerivationEpoch === null) {
				return;
			}
			abortAllFileContentPreparations();
			const abortController = new AbortController();
			fileContentAbortControllersByItemId.set(request.itemId, abortController);
			const preparationGeneration =
				(fileContentPreparationGenerationByItemId.get(request.itemId) ?? 0) + 1;
			fileContentPreparationGenerationByItemId.set(request.itemId, preparationGeneration);
			const ticket = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
				bridgeDemandRank: props.fileViewBridgeDemandRank ?? props.bridgeDemandRank,
				budget: props.fileViewBudget ?? props.budget,
				contentRequestsByItemId: fileViewRuntimeSource.contentRequestsByItemId ?? new Map(),
				epoch: request.epoch,
				itemId: request.itemId,
				isPreparationCurrent: () =>
					fileContentPreparationGenerationByItemId.get(request.itemId) === preparationGeneration,
				openContent: openFileViewContent,
				port,
				pump,
				requestPreparationDrain,
				sequence: createSequence(),
				signal: abortController.signal,
				store: request.store,
				workerDerivationEpoch,
			});
			if (ticket.enqueued) {
				const trackedCompletion = ticket.completion.finally((): void => {
					if (fileContentAbortControllersByItemId.get(request.itemId) === abortController) {
						fileContentAbortControllersByItemId.delete(request.itemId);
					}
				});
				preparationCompletions.push(trackedCompletion);
				shouldRequestDrainAfterMessage = true;
			} else {
				fileContentAbortControllersByItemId.delete(request.itemId);
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
		updateFileMetadataDemand: (demand): void => {
			updateFileMetadataDemand?.(demand);
		},
		...(props.productTransport === undefined
			? {}
			: {
					requestFileDisplayResync: () => {
						const workerDerivationEpoch = activeFileWorkerDerivationEpoch;
						return workerDerivationEpoch === null
							? [buildBridgeWorkerFileMetadataFailureHealthEvent()]
							: fileDisplayEventAuthority.publish({
									epoch: workerDerivationEpoch,
									patches: fileQueryProjection.snapshotDisplayPatches(),
								});
					},
					updateFileDisplayQuery: (command) =>
						applyBridgeCommWorkerFileQueryUpdateCommand({
							command,
							eventAuthority: fileDisplayEventAuthority,
							getWorkerDerivationEpoch: () => activeFileWorkerDerivationEpoch ?? 0,
							projection: fileQueryProjection,
							publishMessages: (messages): void => {
								for (const message of messages) port.postMessage(message);
							},
						}),
				}),
	});
	if (productTransport !== undefined) {
		const fileMetadataProjection = new BridgeCommWorkerFileMetadataProjection();
		const reviewMetadataApplicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				for (const message of handler.applyReviewMetadataApplication(application)) {
					port.postMessage(message);
				}
				if (pump.getPendingWorkIds().length > 0) requestPreparationDrain();
			},
			currentWorkerDerivationEpoch: () => productTransport.workerDerivationEpoch('review'),
			publishDisplayPatches: publishReviewDisplayPatches,
		});
		const installedProductController = new BridgeCommWorkerProductController({
			onFileMetadataDemandFailure: (): void => {
				port.postMessage(buildBridgeWorkerFileMetadataInterestFailureHealthEvent());
			},
			onFileMetadataEvent: (event, workerDerivationEpoch): void => {
				activeFileWorkerDerivationEpoch = workerDerivationEpoch;
				const projection = fileMetadataProjection.apply(event);
				if (event.eventKind === 'file.sourceAccepted') {
					abortAllFileContentPreparations();
				} else if (event.eventKind === 'file.invalidated') {
					if (event.fileId === null) {
						abortAllFileContentPreparations();
					} else {
						abortFileContentPreparation(event.fileId);
					}
				} else if (
					event.eventKind === 'file.descriptorReady' &&
					projection.runtimeMutation !== null
				) {
					abortFileContentPreparation(event.fileId);
				}
				const displayProjection = fileQueryProjection.applyDisplayPatches(projection.patches);
				if (displayProjection.patches.length > 0) {
					for (const message of fileDisplayEventAuthority.publish({
						epoch: workerDerivationEpoch,
						patches: displayProjection.patches,
					})) {
						port.postMessage(message);
					}
				}
				if (projection.runtimeMutation !== null) {
					const messages = handler.applyFileViewRuntimeMutation({
						epoch: workerDerivationEpoch,
						mutation: projection.runtimeMutation,
					});
					for (const message of messages) port.postMessage(message);
				}
				if (pump.getPendingWorkIds().length > 0) requestPreparationDrain();
			},
			onFileMetadataFailure: (_error, workerDerivationEpoch): void => {
				activeFileWorkerDerivationEpoch = workerDerivationEpoch;
				abortAllFileContentPreparations();
				const displayProjection = fileQueryProjection.applyDisplayPatches([
					{ operation: 'clear', slice: 'fileTree' },
					{ operation: 'reset', slice: 'fileItem' },
					{ operation: 'reset', slice: 'fileStatus' },
				]);
				for (const message of fileDisplayEventAuthority.publish({
					epoch: workerDerivationEpoch,
					patches: displayProjection.patches,
				})) {
					port.postMessage(message);
				}
				const messages = handler.applyFileViewRuntimeMutation({
					epoch: workerDerivationEpoch,
					mutation: {
						contentRequestUpserts: [],
						contentUpserts: [],
						filePathUpserts: [],
						kind: 'reset',
						rowUpserts: [],
					},
				});
				for (const message of messages) port.postMessage(message);
				port.postMessage(
					buildBridgeWorkerFileMetadataFailureHealthEvent(
						bridgeProductMetadataStreamHealthDiagnostic(productTransport),
					),
				);
			},
			onReviewMetadataEvent: (event, workerDerivationEpoch): void => {
				activeReviewWorkerDerivationEpoch = workerDerivationEpoch;
				reviewMetadataApplicator.apply(event, workerDerivationEpoch);
			},
			onReviewMetadataFailure: (_error, workerDerivationEpoch): void => {
				activeReviewWorkerDerivationEpoch = workerDerivationEpoch;
				publishReviewDisplayPatches({
					patches: [
						{
							operation: 'failed',
							payload: { error: 'metadataUnavailable', status: 'failed' },
							slice: 'reviewSource',
						},
					],
					workerDerivationEpoch,
				});
			},
			productTransport,
		});
		productController = installedProductController;
		try {
			installedProductController.ensureReviewMetadata();
		} catch {
			// The typed failure publication above keeps the runtime alive for repair/resubscription.
		}
		void installedProductController.ensureFileSource().catch((): void => {
			port.postMessage(
				buildBridgeWorkerFileMetadataFailureHealthEvent(
					bridgeProductMetadataStreamHealthDiagnostic(productTransport),
				),
			);
		});
		updateFileMetadataDemand = (demand): void => {
			void installedProductController.updateFileMetadataDemand(demand).catch((): void => {});
		};
		if (props.sendProductControl === undefined) {
			sendProductControl = (command): Promise<unknown> =>
				installedProductController.sendProductControl(command);
		}
	}

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
		const productControlCommand = bridgeWorkerRuntimeProductControlCommandForMessage(
			parsedMessage.data,
		);
		const metadataInterestUpdateCommand =
			parsedMessage.data.command === 'metadataInterestUpdate' ? parsedMessage.data : null;
		const deferredRequestId =
			metadataInterestUpdateCommand?.requestId ?? productControlCommand?.requestId ?? null;
		const shouldSendProductControl =
			productControlCommand !== null &&
			bridgeWorkerRuntimeMessagesContainReadyRequest({
				messages,
				requestId: productControlCommand.requestId,
			});
		const shouldUpdateReviewMetadataInterests =
			metadataInterestUpdateCommand !== null &&
			bridgeWorkerRuntimeMessagesContainReadyRequest({
				messages,
				requestId: metadataInterestUpdateCommand.requestId,
			});
		const shouldDeferReadyMessage = shouldSendProductControl || shouldUpdateReviewMetadataInterests;
		const immediateMessages =
			shouldDeferReadyMessage && deferredRequestId !== null
				? messages.filter(
						(message): boolean =>
							!bridgeWorkerRuntimeMessageIsReadyRequest({
								message,
								requestId: deferredRequestId,
							}),
					)
				: messages;
		for (const message of immediateMessages) {
			port.postMessage(message);
		}
		if (productControlCommand !== null && shouldSendProductControl) {
			void sendBridgeCommWorkerActionWithTimeout({
				send: (): Promise<unknown> => sendProductControl(productControlCommand.command),
				timeoutMilliseconds: productControlTimeoutMilliseconds,
			})
				.then((): void => {
					for (const message of messages) {
						if (
							bridgeWorkerRuntimeMessageIsReadyRequest({
								message,
								requestId: productControlCommand.requestId,
							})
						) {
							port.postMessage(message);
						}
					}
				})
				.catch((_error: unknown): void => {
					port.postMessage(
						buildBridgeWorkerRuntimeCommandFailedHealthEvent({
							requestId: productControlCommand.requestId,
							message: bridgeCommWorkerProductControlFailureMessage({
								command: productControlCommand.command,
							}),
							...(productControlCommand.command.method === 'bridge.activeViewerMode.update'
								? { deliveryStatus: 'unknownAfterDispatch' }
								: {}),
						}),
					);
				});
		}
		if (metadataInterestUpdateCommand !== null && shouldUpdateReviewMetadataInterests) {
			const activeProductController = productController;
			void sendBridgeCommWorkerActionWithTimeout({
				send:
					activeProductController === null
						? rejectUninstalledReviewMetadataInterestUpdate
						: (): Promise<void> =>
								activeProductController.updateReviewMetadataInterests(
									metadataInterestUpdateCommand.request,
								),
				timeoutMilliseconds: productControlTimeoutMilliseconds,
			})
				.then((): void => {
					for (const message of messages) {
						if (
							bridgeWorkerRuntimeMessageIsReadyRequest({
								message,
								requestId: metadataInterestUpdateCommand.requestId,
							})
						) {
							port.postMessage(message);
						}
					}
				})
				.catch((): void => {
					port.postMessage(
						buildBridgeWorkerRuntimeCommandFailedHealthEvent({
							requestId: metadataInterestUpdateCommand.requestId,
							message: 'Bridge comm worker failed to update Review metadata interests.',
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

async function rejectUninstalledBridgeProductControl(
	command: BridgeProductControlCommand,
): Promise<never> {
	throw new Error(`Bridge product-control sender is not installed for ${command.method}.`);
}

async function rejectUninstalledReviewMetadataInterestUpdate(): Promise<never> {
	throw new Error('Bridge Review metadata product subscription is not installed.');
}

function rejectUninstalledBridgeFileContentOpen(): never {
	throw new Error('Bridge File content transport is not installed.');
}

function bridgeCommWorkerProductControlFailureMessage(props: {
	readonly command: BridgeProductControlCommand;
}): string {
	return `Bridge comm worker failed to forward ${props.command.method}.`;
}

function sendBridgeCommWorkerActionWithTimeout(props: {
	readonly send: () => Promise<unknown>;
	readonly timeoutMilliseconds: number;
}): Promise<unknown> {
	return new Promise<unknown>((resolve, reject): void => {
		let didSettle = false;
		const timeoutId = globalThis.setTimeout((): void => {
			if (didSettle) {
				return;
			}
			didSettle = true;
			reject(new Error('Bridge comm worker command action timed out.'));
		}, props.timeoutMilliseconds);
		void props.send().then(
			(actionResult: unknown): void => {
				if (didSettle) {
					return;
				}
				didSettle = true;
				globalThis.clearTimeout(timeoutId);
				resolve(actionResult);
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

interface EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps {
	readonly backoffByItemId: ReadonlyMap<string, BridgeCommWorkerDemandBackoff>;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly createSequence: () => number;
	readonly epoch: number;
	readonly fetchReviewContentResource?: BridgeWorkerReviewContentResourceFetch;
	readonly openContent?: BridgeWorkerReviewContentOpen;
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
	readonly workerDerivationEpoch: number;
}

function enqueueVisibleBridgeCommWorkerReviewDemandExecution(
	props: EnqueueVisibleBridgeCommWorkerReviewDemandExecutionProps,
): readonly EnqueuedBridgeCommWorkerDemandPreparationTicket[] {
	const membership = visibleReviewDemandMembersNeedingExecutionFromState({
		forceExecutionItemIds: props.sourceChurnItemIds,
		store: props.store,
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
			...(props.fetchReviewContentResource === undefined
				? {}
				: { fetchReviewContentResource: props.fetchReviewContentResource }),
			...(props.openContent === undefined ? {} : { openContent: props.openContent }),
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
			workerDerivationEpoch: props.workerDerivationEpoch,
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
	readonly store: BridgeCommWorkerStore;
}): readonly BridgeCommWorkerDemandMember[] {
	const membership: BridgeCommWorkerDemandMember[] = [];
	const state = props.store.getState();
	for (const itemId of visibleReviewDemandItemIdsFromState(state)) {
		if (
			!props.forceExecutionItemIds.has(itemId) &&
			!doesVisibleReviewDemandNeedExecution(props.store, itemId)
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
	store: BridgeCommWorkerStore,
	itemId: string,
): boolean {
	const state = store.getState();
	const availability = state.availabilityByItemId.get(itemId);
	if (availability === 'failed' || availability === 'unavailable') {
		return false;
	}
	const fulfillment = store.renderFulfillmentRegistry.getItemState(itemId);
	if (fulfillment === null) {
		return true;
	}
	return fulfillment.stage === 'desired' || fulfillment.stage === 'retry_wait';
}

function markVisibleReviewDemandSourceChurn(props: {
	readonly affectedItemIds: readonly string[] | undefined;
	readonly cause: BridgeCommWorkerDemandExecutionScheduleRequest['cause'];
	readonly inFlightItemIds: ReadonlySet<string>;
	readonly pendingRerunItemIds: Set<string>;
	readonly store: BridgeCommWorkerStore;
	readonly visibleDemandGenerationByItemId: Map<string, number>;
}): ReadonlySet<string> {
	if (props.cause !== 'reviewInvalidate' && props.cause !== 'reviewMetadata') {
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
