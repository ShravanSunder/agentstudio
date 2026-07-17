import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerFileMetadataDemand,
	type BridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { BridgeCommWorkerFileDisplayEventAuthority } from './bridge-comm-worker-file-display-event-authority.js';
import { BridgeCommWorkerFileMetadataProjection } from './bridge-comm-worker-file-metadata-projection.js';
import {
	applyBridgeCommWorkerFileQueryUpdateCommand,
	BridgeCommWorkerFileQueryProjection,
} from './bridge-comm-worker-file-query-projection.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import { bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame } from './bridge-comm-worker-native-surface-selection.js';
import {
	BridgeCommWorkerPanePresentationAuthority,
	type BridgeCommWorkerPanePresentationSnapshot,
} from './bridge-comm-worker-pane-presentation.js';
import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { createBridgeCommWorkerReviewDemandScheduling } from './bridge-comm-worker-review-demand-scheduling.js';
import { BridgeCommWorkerReviewMetadataApplicator } from './bridge-comm-worker-review-metadata-applicator.js';
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
	bridgeWorkerFileRenderPatchEventSchema,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerReviewDisplayPatchEventSchema,
	bridgeWorkerReviewRenderPatchEventSchema,
	type BridgeWorkerReviewDisplayPatch,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFileViewContentOpen } from './bridge-worker-file-view-content-fetch.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerReviewContentOpen } from './bridge-worker-review-content-fetch.js';

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
	const panePresentationAuthority = new BridgeCommWorkerPanePresentationAuthority();
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource = {
		contentItems: [],
		contentRequests: [],
		contentRequestsByItemId: new Map(),
		filePathsByItemId: new Map(),
		rows: [],
		rowIndexByItemId: new Map(),
		rowsByIndex: new Map(),
	};
	const fileContentAbortControllersByItemId = new Map<string, AbortController>();
	const fileContentPreparationGenerationByItemId = new Map<string, number>();
	let latestSelectedFilePreparationRequest: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest | null =
		null;
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
	let activeFileWorkerDerivationEpoch: number | null = null;
	let activeReviewWorkerDerivationEpoch: number | null = null;
	let activeViewerMode: 'file' | 'review' | null = null;
	const publishedUpdatingChromeIdentityBySurface = new Map<'file' | 'review', string>();
	const publishUpdatingChromeForSurface = (
		surface: 'file' | 'review',
		presentation: BridgeCommWorkerPanePresentationSnapshot,
	): void => {
		const workerDerivationEpoch =
			surface === 'file' ? activeFileWorkerDerivationEpoch : activeReviewWorkerDerivationEpoch;
		if (workerDerivationEpoch === null) return;
		const refreshingLane = surface === 'file' ? 'file' : 'review';
		const isUpdating =
			presentation.nativeActivity === 'foreground' &&
			activeViewerMode === surface &&
			presentation.refreshingLanes.includes(refreshingLane);
		const publicationIdentity = `${workerDerivationEpoch}:${isUpdating ? 'updating' : 'idle'}`;
		if (publishedUpdatingChromeIdentityBySurface.get(surface) === publicationIdentity) return;
		const patch = isUpdating
			? {
					operation: 'upsert' as const,
					payload: {
						isLoading: true,
						message: surface === 'file' ? 'Updating files…' : 'Updating review…',
					},
					slice: 'panelChrome' as const,
				}
			: { operation: 'reset' as const, slice: 'panelChrome' as const };
		const commonEvent = {
			direction: 'serverWorkerToMain' as const,
			patches: [patch],
			publicationSequence: createSequence(),
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			workerDerivationEpoch,
		};
		port.postMessage(
			surface === 'file'
				? bridgeWorkerFileRenderPatchEventSchema.parse({
						...commonEvent,
						kind: 'fileRenderPatch',
						surface: 'file',
					})
				: bridgeWorkerReviewRenderPatchEventSchema.parse({
						...commonEvent,
						kind: 'reviewRenderPatch',
						surface: 'review',
					}),
		);
		publishedUpdatingChromeIdentityBySurface.set(surface, publicationIdentity);
	};
	const publishUpdatingChrome = (): void => {
		const presentation = panePresentationAuthority.snapshot;
		publishUpdatingChromeForSurface('file', presentation);
		publishUpdatingChromeForSurface('review', presentation);
	};
	const fileDisplayEventAuthority = new BridgeCommWorkerFileDisplayEventAuthority({
		createSequence,
	});
	let reviewDisplayProjectionRevision = 0;
	const publishReviewDisplayPatches = (publication: {
		readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
		readonly workerDerivationEpoch: number;
	}): void => {
		const nextProjectionRevision = reviewDisplayProjectionRevision + 1;
		const message = bridgeWorkerReviewDisplayPatchEventSchema.parse({
			direction: 'serverWorkerToMain',
			epoch: publication.workerDerivationEpoch,
			kind: 'reviewDisplayPatch',
			patches: publication.patches,
			projectionRevision: nextProjectionRevision,
			sequence: createSequence(),
			surface: 'review',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});
		port.postMessage(message);
		reviewDisplayProjectionRevision = nextProjectionRevision;
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

	const reviewDemandScheduling = createBridgeCommWorkerReviewDemandScheduling({
		bridgeDemandRank: props.bridgeDemandRank,
		budget: props.budget,
		createSequence,
		isWorkAdmitted: (): boolean => panePresentationAuthority.admitsWork,
		markPreparationDrainRequired: (): void => {
			shouldRequestDrainAfterMessage = true;
		},
		...(props.now === undefined ? {} : { now: props.now }),
		...(openReviewContent === undefined ? {} : { openReviewContent }),
		port,
		pump,
		recordPreparationCompletion: (completion: Promise<void>): void => {
			preparationCompletions.push(completion);
		},
		requestPreparationDrain,
		...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		usesProductTransport: productTransport !== undefined,
		workSignal: (): AbortSignal => panePresentationAuthority.workSignal,
	});

	const publishReviewMetadataPostCommitFailure = (): void => {
		try {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
		} catch {
			// A closed main port cannot invalidate committed worker metadata authority.
		}
	};
	const scheduleSelectedFileViewContentReadyPreparation = (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	): void => {
		latestSelectedFilePreparationRequest = request;
		if (!panePresentationAuthority.admitsWork) return;
		const workerDerivationEpoch = activeFileWorkerDerivationEpoch;
		if (workerDerivationEpoch === null) return;
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
				panePresentationAuthority.admitsWork &&
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
					if (!abortController.signal.aborted && latestSelectedFilePreparationRequest === request) {
						latestSelectedFilePreparationRequest = null;
					}
				}
			});
			preparationCompletions.push(trackedCompletion);
			shouldRequestDrainAfterMessage = true;
		} else {
			fileContentAbortControllersByItemId.delete(request.itemId);
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
		onReviewMetadataPostCommitFailure: publishReviewMetadataPostCommitFailure,
		scheduleSelectedReviewContentReadyPreparation:
			reviewDemandScheduling.scheduleSelectedContentReadyPreparation,
		scheduleReviewMetadataReset: reviewDemandScheduling.scheduleMetadataReset,
		scheduleSelectedFileViewContentReadyPreparation,
		scheduleDemandExecution: (request): void => {
			shouldRequestDrainAfterMessage =
				reviewDemandScheduling.scheduleDemandExecution(request) || shouldRequestDrainAfterMessage;
		},
		updateReviewRuntimeSource: reviewDemandScheduling.updateRuntimeSource,
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
		productTransport.setPaneSurfaceSelectionFrameSink?.((frame): void => {
			port.postMessage(bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame(frame));
		});
		productTransport.setPanePresentationFrameSink?.((frame): void => {
			const application = panePresentationAuthority.apply(frame);
			if (application.leftForeground) {
				abortAllFileContentPreparations();
				reviewDemandScheduling.suspend();
			}
			if (application.enteredForeground) {
				reviewDemandScheduling.resume();
				const latestFileRequest = latestSelectedFilePreparationRequest;
				if (
					latestFileRequest !== null &&
					latestFileRequest.store.getState().selectedId === latestFileRequest.itemId
				) {
					scheduleSelectedFileViewContentReadyPreparation(latestFileRequest);
				}
			}
			publishUpdatingChrome();
		});
		const fileMetadataProjection = new BridgeCommWorkerFileMetadataProjection();
		const reviewMetadataApplicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application) => {
				const transaction = handler.prepareReviewMetadataApplication(application);
				return {
					commit: transaction.commit,
					rollback: transaction.rollback,
					runPostCommitEffects: (): void => {
						transaction.runPostCommitEffects();
						for (const message of transaction.messages) {
							try {
								port.postMessage(message);
							} catch {
								publishReviewMetadataPostCommitFailure();
							}
						}
						try {
							if (pump.getPendingWorkIds().length > 0) requestPreparationDrain();
						} catch {
							publishReviewMetadataPostCommitFailure();
						}
					},
				};
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
				publishUpdatingChrome();
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
				publishUpdatingChrome();
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
			onReviewMetadataEvent: (event, workerDerivationEpoch) => {
				activeReviewWorkerDerivationEpoch = workerDerivationEpoch;
				reviewDemandScheduling.updateWorkerDerivationEpoch(workerDerivationEpoch);
				publishUpdatingChrome();
				return reviewMetadataApplicator.apply(event, workerDerivationEpoch);
			},
			onReviewMetadataFailure: (_error, workerDerivationEpoch): void => {
				activeReviewWorkerDerivationEpoch = workerDerivationEpoch;
				reviewDemandScheduling.updateWorkerDerivationEpoch(workerDerivationEpoch);
				publishUpdatingChrome();
				const failureDisposition =
					reviewMetadataApplicator.handleMetadataFailure(workerDerivationEpoch);
				if (failureDisposition === 'noActive') {
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
				}
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
		if (parsedMessage.data.command === 'activeViewerModeUpdate') {
			activeViewerMode = parsedMessage.data.update.mode;
			publishUpdatingChrome();
		}
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
