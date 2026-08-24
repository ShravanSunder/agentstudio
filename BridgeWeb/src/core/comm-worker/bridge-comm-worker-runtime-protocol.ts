import { recordWorktreeAnnotationLifecycleTelemetry } from '../../worktree-annotations/worktree-annotation-lifecycle-telemetry.js';
import { bridgeCommWorkerAnnotationProjectionConvergenceEvent } from './bridge-comm-worker-annotation-runtime-events.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerFileMetadataDemand,
	type BridgeCommWorkerFileViewRuntimeSource,
	type BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
} from './bridge-comm-worker-command-handler.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	abortAllBridgeCommWorkerFileContentPreparations,
	abortBridgeCommWorkerFileContentPreparation,
} from './bridge-comm-worker-file-content-cancellation.js';
import { BridgeCommWorkerFileDisplayEventAuthority } from './bridge-comm-worker-file-display-event-authority.js';
import { BridgeCommWorkerFileMetadataProjection } from './bridge-comm-worker-file-metadata-projection.js';
import {
	applyBridgeCommWorkerFileQueryUpdateCommand,
	BridgeCommWorkerFileQueryProjection,
} from './bridge-comm-worker-file-query-projection.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import { createEmptyBridgeCommWorkerFileViewRuntimeSource } from './bridge-comm-worker-file-view-runtime-source.js';
import { createBridgeCommWorkerInstalledReviewSource } from './bridge-comm-worker-installed-review-source.js';
import { bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame } from './bridge-comm-worker-native-surface-selection.js';
import {
	BridgeCommWorkerSelectedFileLifecycleTelemetry,
	trackSelectedFilePreparationCompletion,
} from './bridge-comm-worker-operation-lifecycle.js';
import { BridgeCommWorkerPanePresentationAuthority } from './bridge-comm-worker-pane-presentation.js';
import { drainBridgeCommWorkerPreparations } from './bridge-comm-worker-preparation-drain.js';
import { callCurrentFileSourceWithTelemetry } from './bridge-comm-worker-product-control-runtime.js';
import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import {
	BridgeCommWorkerRenderFulfillmentLifecycleDriver,
	type BridgeCommWorkerRenderFulfillmentSurface,
} from './bridge-comm-worker-render-fulfillment-lifecycle-driver.js';
import { applyBridgeCommWorkerRenderDispositionRuntimeEffects } from './bridge-comm-worker-render-publication-release.js';
import {
	buildBridgeCommWorkerReviewCandidateReadyPublication,
	buildBridgeCommWorkerReviewCandidateFailedPublication,
	buildBridgeCommWorkerReviewCandidateStartedPublication,
} from './bridge-comm-worker-review-candidate-ready.js';
import {
	bridgeWorkerComparisonTargetsContentOpen,
	createBridgeWorkerComparisonTargetsQueryRunner,
	settleBridgeWorkerComparisonTargetsControlRequest,
} from './bridge-comm-worker-review-comparison-target-query.js';
import { createBridgeCommWorkerReviewDemandScheduling } from './bridge-comm-worker-review-demand-scheduling.js';
import { BridgeCommWorkerReviewMetadataApplicator } from './bridge-comm-worker-review-metadata-applicator.js';
import {
	BridgeCommWorkerReviewDisplayLifecyclePublisher,
	BridgeCommWorkerReviewOperationLifecycleTelemetry,
} from './bridge-comm-worker-review-operation-lifecycle.js';
import { BridgeCommWorkerReviewQueryProjection } from './bridge-comm-worker-review-query-projection.js';
import { createBridgeCommWorkerReviewRenderPublicationAuthority } from './bridge-comm-worker-review-render-publication-authority.js';
import {
	bridgeCommWorkerSemanticClassForMessage,
	bridgeCommWorkerTelemetryLaneForMessage,
} from './bridge-comm-worker-runtime-command-routing.js';
import {
	publishBridgeCommWorkerPostCommitFailureBestEffort,
	rejectUninstalledBridgeFileContentOpen,
	rejectUninstalledBridgeProductControl,
	scheduleDefaultBridgeRenderFulfillmentWake,
} from './bridge-comm-worker-runtime-defaults.js';
import {
	bridgeWorkerRuntimeMessagesContainReadyRequest,
	buildBridgeWorkerFileMetadataFailureHealthEvent,
	buildBridgeWorkerFileMetadataInterestFailureHealthEvent,
	buildBridgeWorkerRuntimeDegradedHealthEvent,
} from './bridge-comm-worker-runtime-health.js';
import { dispatchBridgeCommWorkerRuntimeProductControl } from './bridge-comm-worker-runtime-product-control-dispatch.js';
import type {
	BridgeCommWorkerPreparationDrain,
	RegisterBridgeCommWorkerRuntimePortProtocolProps,
} from './bridge-comm-worker-runtime-protocol-contracts.js';
import {
	bridgeProductMetadataStreamHealthDiagnostic,
	createBridgeWorkerRuntimeSequenceCounter,
	readBridgeCommWorkerRuntimeNowMilliseconds,
	scheduleDefaultBridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-support.js';
import {
	BridgeCommWorkerSelectedFileContentOperationController,
	settleAcceptedSelectedFileRenderDisposition,
	settleSelectedFileDescriptorWaitAtMetadataTerminal,
} from './bridge-comm-worker-selected-file-content-operation.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import {
	bridgeCommWorkerComparisonTelemetryFacts,
	recordBridgeCommWorkerPanePresentationTelemetry,
	recordBridgeCommWorkerTaskTelemetry,
} from './bridge-comm-worker-telemetry.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import {
	isBridgeWorkerFileViewContentMetadata,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerAnnotationProjectionConvergenceEventSchema,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFileViewContentOpen } from './bridge-worker-file-view-content-fetch.js';
import type { BridgeWorkerReviewContentOpen } from './bridge-worker-review-content-fetch.js';

export type {
	BridgeCommWorkerPreparationDrain,
	BridgeCommWorkerProductControlSender,
	RegisterBridgeCommWorkerRuntimePortProtocolProps,
} from './bridge-comm-worker-runtime-protocol-contracts.js';
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
	const scheduleRenderFulfillmentWake =
		props.scheduleRenderFulfillmentWake ?? scheduleDefaultBridgeRenderFulfillmentWake;
	let sendProductControl = props.sendProductControl ?? rejectUninstalledBridgeProductControl;
	const productTransport = props.productTransport;
	const openFileViewContent: BridgeWorkerFileViewContentOpen =
		props.openFileViewContent ??
		(productTransport === undefined
			? rejectUninstalledBridgeFileContentOpen
			: (descriptor, abortSignal, operationCorrelationId) =>
					productTransport.openContent(descriptor, abortSignal, operationCorrelationId));
	const openReviewContent: BridgeWorkerReviewContentOpen | undefined =
		props.openReviewContent ??
		(productTransport === undefined
			? undefined
			: (descriptor, abortSignal) => productTransport.openContent(descriptor, abortSignal));
	const openComparisonTargetsContent = bridgeWorkerComparisonTargetsContentOpen(productTransport);
	const productControlTimeoutMilliseconds = props.productControlTimeoutMilliseconds ?? 5000;
	const preparationCompletions: Promise<void>[] = [];
	let drainScheduled = false;
	let shouldRequestDrainAfterMessage = false;
	let advanceRenderFulfillmentLifecycle = (
		_surface: BridgeCommWorkerRenderFulfillmentSurface,
	): void => {};
	let activeComparisonTargetsProductControlRequestId: string | null = null;
	const panePresentationAuthority = new BridgeCommWorkerPanePresentationAuthority();
	const comparisonTargetsQueryRunner = createBridgeWorkerComparisonTargetsQueryRunner({
		getWorkAdmission: () => ({
			generation: panePresentationAuthority.snapshot.workAdmissionGeneration,
			signal: panePresentationAuthority.workSignal,
		}),
		isCurrentWorkAdmission: (generation): boolean =>
			panePresentationAuthority.isCurrentWorkAdmission(generation),
		onSettled: (requestId): void => {
			activeComparisonTargetsProductControlRequestId =
				settleBridgeWorkerComparisonTargetsControlRequest(
					activeComparisonTargetsProductControlRequestId,
					requestId,
				);
		},
		openContent: openComparisonTargetsContent,
		publish: (event): void => port.postMessage(event),
	});
	let fileViewRuntimeSource: BridgeCommWorkerFileViewRuntimeSource =
		createEmptyBridgeCommWorkerFileViewRuntimeSource();
	const fileContentAbortControllersByItemId = new Map<string, AbortController>();
	const fileContentPreparationGenerationByItemId = new Map<string, number>();
	const fileContentCancellation = {
		abortControllersByItemId: fileContentAbortControllersByItemId,
		generationByItemId: fileContentPreparationGenerationByItemId,
	};
	let latestSelectedFilePreparationRequest: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest | null =
		null;
	const selectedFileContentOperationController =
		new BridgeCommWorkerSelectedFileContentOperationController();
	let selectedFileContentOperationStore: BridgeCommWorkerStore | null = null;
	const selectedFileLifecycleTelemetry = new BridgeCommWorkerSelectedFileLifecycleTelemetry(
		props.telemetryClient,
	);
	const cancelSelectedFileContentOperation = (): void => {
		const operation = selectedFileContentOperationController.cancel();
		if (operation !== null) selectedFileLifecycleTelemetry.cancelled(operation);
	};
	const retriedSelectedFilePreparationRequests =
		new WeakSet<BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest>();
	const abortFileContentPreparation = (itemId: string): void =>
		abortBridgeCommWorkerFileContentPreparation({ ...fileContentCancellation, itemId });
	const abortAllFileContentPreparations = (): void =>
		abortAllBridgeCommWorkerFileContentPreparations(fileContentCancellation);
	let activeFileWorkerDerivationEpoch: number | null = null;
	let activeReviewWorkerDerivationEpoch: number | null = null;
	let reviewMetadataApplicator: BridgeCommWorkerReviewMetadataApplicator | null = null;
	const reviewOperationLifecycleTelemetry = new BridgeCommWorkerReviewOperationLifecycleTelemetry(
		props.telemetryClient,
	);
	let activeViewerMode: 'file' | 'review' | null = null;
	const reviewRenderPublicationAuthority = createBridgeCommWorkerReviewRenderPublicationAuthority({
		activeFileWorkerDerivationEpoch: () => activeFileWorkerDerivationEpoch,
		activeReviewWorkerDerivationEpoch: () => activeReviewWorkerDerivationEpoch,
		activeViewerMode: () => activeViewerMode,
		createSequence,
		publish: (message): void => port.postMessage(message),
		telemetryClient: props.telemetryClient,
	});
	const publishUpdatingChrome = (): void => {
		reviewRenderPublicationAuthority.publishUpdatingChrome(panePresentationAuthority.snapshot);
	};
	const fileDisplayEventAuthority = new BridgeCommWorkerFileDisplayEventAuthority({
		createSequence,
	});
	const reviewQueryProjection = new BridgeCommWorkerReviewQueryProjection();
	const reviewDisplayLifecyclePublisher = new BridgeCommWorkerReviewDisplayLifecyclePublisher({
		createSequence,
		lifecycle: reviewOperationLifecycleTelemetry,
		onReviewComparison: (reviewComparison, workerDerivationEpoch, isUpdatingReview): void => {
			reviewRenderPublicationAuthority.recordReviewComparison(
				reviewComparison,
				workerDerivationEpoch,
				isUpdatingReview,
			);
		},
		onSourceIdentity: (sourceIdentity): void => {
			reviewRenderPublicationAuthority.recordReviewSourceIdentity(sourceIdentity);
		},
		panePresentationAuthority,
		postMessage: (message): void => port.postMessage(message),
		queryProjection: reviewQueryProjection,
		readActiveViewerMode: (): 'file' | 'review' | null => activeViewerMode,
	});
	const postReviewDisplayPatches = (
		publication: Parameters<typeof reviewDisplayLifecyclePublisher.post>[0],
	): void => {
		reviewRenderPublicationAuthority.recordReviewPublicationIdentity(
			publication.reviewPublicationIdentity,
		);
		reviewDisplayLifecyclePublisher.post(publication);
	};
	const publishReviewDisplayPatches = (
		publication: Parameters<typeof reviewDisplayLifecyclePublisher.publish>[0],
	): void => {
		reviewRenderPublicationAuthority.recordReviewPublicationIdentity(
			publication.reviewPublicationIdentity,
		);
		reviewDisplayLifecyclePublisher.publish(publication);
	};
	const fileQueryProjection = new BridgeCommWorkerFileQueryProjection();
	let updateFileMetadataDemand: ((demand: BridgeCommWorkerFileMetadataDemand) => void) | null =
		null;
	let currentFileMetadataSelectedPathResolved: boolean | undefined;
	let productController: BridgeCommWorkerProductController | null = null;
	const installedReviewSource = createBridgeCommWorkerInstalledReviewSource(
		() => productController,
	);
	const drainPreparation: BridgeCommWorkerPreparationDrain = async () => {
		drainScheduled = false;
		return await drainBridgeCommWorkerPreparations({
			advanceRenderFulfillmentLifecycle,
			pendingCompletions: preparationCompletions,
			pump,
			requestPreparationDrain,
		});
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
		operationCorrelationId: (): string | null =>
			reviewOperationLifecycleTelemetry.currentOperationCorrelationId,
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

	const publishReviewMetadataPostCommitFailure = (): void =>
		publishBridgeCommWorkerPostCommitFailureBestEffort((): void => {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
		});
	const scheduleSelectedFileViewContentReadyPreparation = (
		request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest,
	): void => {
		const selectedState = request.store.getState();
		if (selectedState.selectedId !== request.itemId) return;
		const previousOperation = selectedFileContentOperationController.current;
		const selectedOperation = selectedFileContentOperationController.admitSelection({
			itemId: request.itemId,
			selectionEpoch: selectedState.selectedEpoch,
		});
		if (previousOperation?.generation !== selectedOperation.generation) {
			if (previousOperation !== null) {
				selectedFileLifecycleTelemetry.cancelled(previousOperation);
			}
			selectedFileLifecycleTelemetry.admitted(selectedOperation);
			abortAllFileContentPreparations();
			selectedFileContentOperationStore = request.store;
		}
		latestSelectedFilePreparationRequest = request;
		if (!panePresentationAuthority.admitsWork || activeViewerMode !== 'file') return;
		const workerDerivationEpoch = activeFileWorkerDerivationEpoch;
		if (workerDerivationEpoch === null) return;
		const sourceBoundOperation = selectedFileContentOperationController.bindSource({
			generation: selectedOperation.generation,
			workerDerivationEpoch,
		});
		if (sourceBoundOperation === null) return;
		if (sourceBoundOperation.generation !== selectedOperation.generation) {
			abortAllFileContentPreparations();
		}
		const metadata = selectedState.contentMetadataByItemId.get(request.itemId) ?? null;
		const contentRequest = fileViewRuntimeSource.contentRequestsByItemId?.get(request.itemId);
		if (!isBridgeWorkerFileViewContentMetadata(metadata) || contentRequest === undefined) return;
		selectedFileLifecycleTelemetry.descriptorReady(sourceBoundOperation);
		selectedFileContentOperationController.advance(
			sourceBoundOperation.generation,
			'preparingContent',
		);
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
			onPreparationOutcome: (outcome): void => {
				if (
					selectedFileLifecycleTelemetry.handlePreparationOutcome({
						controller: selectedFileContentOperationController,
						operation: sourceBoundOperation,
						outcome,
					})
				) {
					selectedFileContentOperationStore = null;
				}
			},
			openContent: openFileViewContent,
			operationCorrelationId: sourceBoundOperation.operationCorrelationId,
			port,
			pump,
			requestPreparationDrain,
			sequence: createSequence(),
			signal: abortController.signal,
			store: request.store,
			workerDerivationEpoch,
		});
		if (ticket.enqueued) {
			const trackedCompletion = trackSelectedFilePreparationCompletion({
				abortController,
				abortControllerByItemId: fileContentAbortControllersByItemId,
				completion: ticket.completion,
				isPaneWorkAdmitted: (): boolean => panePresentationAuthority.admitsWork,
				isRequestLatest: (): boolean => latestSelectedFilePreparationRequest === request,
				onClearLatest: (): void => {
					latestSelectedFilePreparationRequest = null;
				},
				request,
				requestDrain: requestPreparationDrain,
				retriedRequests: retriedSelectedFilePreparationRequests,
				retry: (): void => scheduleSelectedFileViewContentReadyPreparation(request),
			});
			preparationCompletions.push(trackedCompletion);
			shouldRequestDrainAfterMessage = true;
		} else {
			fileContentAbortControllersByItemId.delete(request.itemId);
		}
	};
	const resumeLatestSelectedFileViewContentReadyPreparation = (): void => {
		const latestFileRequest = latestSelectedFilePreparationRequest;
		if (latestFileRequest === null) return;
		if (latestFileRequest.store.getState().selectedId !== latestFileRequest.itemId) return;
		scheduleSelectedFileViewContentReadyPreparation(latestFileRequest);
	};
	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		reviewPublicationIdentity: null,
		rows: [],
		createSequence,
		...(props.now === undefined ? {} : { renderFulfillmentNow: props.now }),
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
		updateReviewDisplayProjection: (command) => {
			const patches = reviewQueryProjection.updateQuery(command.query);
			if (patches.length > 0) {
				postReviewDisplayPatches({
					patches,
					workerDerivationEpoch: activeReviewWorkerDerivationEpoch ?? command.epoch,
				});
			}
			return [];
		},
		updateFileViewRuntimeSource: (source: BridgeCommWorkerFileViewRuntimeSource): void => {
			fileViewRuntimeSource = source;
		},
		updateFileMetadataDemand: (demand): void => {
			currentFileMetadataSelectedPathResolved = demand.selectedPath !== null;
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
		retryAnnotationProjection: (surface): void => {
			productController?.retryAnnotationProjection(surface);
		},
	});
	const renderFulfillmentLifecycleDriver = new BridgeCommWorkerRenderFulfillmentLifecycleDriver({
		advanceBySurface: {
			file: handler.advanceFileRenderFulfillmentLifecycle,
			review: handler.advanceReviewRenderFulfillmentLifecycle,
		},
		needsPreparationDrain: (): boolean =>
			shouldRequestDrainAfterMessage || pump.getPendingWorkIds().length > 0,
		now: props.now ?? performance.now.bind(performance),
		requestPreparationDrain,
		scheduleWake: scheduleRenderFulfillmentWake,
	});
	advanceRenderFulfillmentLifecycle = (surface): void =>
		renderFulfillmentLifecycleDriver.advance(surface);
	if (productTransport !== undefined) {
		productTransport.setPaneSurfaceSelectionFrameSink?.((frame): void => {
			port.postMessage(bridgeWorkerNativeSurfaceSelectionRequestFromMetadataFrame(frame));
		});
		productTransport.setPanePresentationFrameSink?.((frame): void => {
			const wasRefreshingFile = panePresentationAuthority.snapshot.refreshingLanes.includes('file');
			const application = panePresentationAuthority.apply(frame);
			recordBridgeCommWorkerPanePresentationTelemetry({
				...bridgeCommWorkerComparisonTelemetryFacts(application.snapshot),
				disposition:
					application.disposition === 'idempotentReplay' ? 'idempotent_replay' : 'applied',
				phase: 'pane_presentation_applied',
				presentationRevision: application.snapshot.presentationRevision,
				refreshingReview: application.snapshot.refreshingLanes.includes('review'),
				telemetryClient: props.telemetryClient,
			});
			const fileRefreshSettled =
				wasRefreshingFile &&
				application.snapshot.nativeActivity === 'foreground' &&
				!application.snapshot.refreshingLanes.includes('file');
			if (application.leftForeground) {
				if (activeComparisonTargetsProductControlRequestId !== null) {
					comparisonTargetsQueryRunner.fail(activeComparisonTargetsProductControlRequestId);
				}
				comparisonTargetsQueryRunner.abort();
				activeComparisonTargetsProductControlRequestId = null;
				abortAllFileContentPreparations();
				cancelSelectedFileContentOperation();
				selectedFileContentOperationStore = null;
				reviewDemandScheduling.suspend();
			}
			if (application.enteredForeground) {
				if (activeViewerMode === 'review') reviewDemandScheduling.resume();
				if (activeViewerMode === 'file') {
					resumeLatestSelectedFileViewContentReadyPreparation();
				}
			}
			if (fileRefreshSettled) {
				void productController?.ensureFileSource().catch((): void => {});
				const descriptorWaitOperation = selectedFileContentOperationController.current;
				const settlement = settleSelectedFileDescriptorWaitAtMetadataTerminal({
					activeWorkerDerivationEpoch: activeFileWorkerDerivationEpoch,
					controller: selectedFileContentOperationController,
					createSequence,
					fileViewRuntimeSource,
					request: latestSelectedFilePreparationRequest,
				});
				if (settlement.terminalPatch !== null) port.postMessage(settlement.terminalPatch);
				if (settlement.settled) {
					if (descriptorWaitOperation !== null) {
						selectedFileLifecycleTelemetry.descriptorMissing(descriptorWaitOperation);
					}
					latestSelectedFilePreparationRequest = null;
					selectedFileContentOperationStore = null;
				}
			}
			publishUpdatingChrome();
		});
		const fileMetadataProjection = new BridgeCommWorkerFileMetadataProjection();
		const activeReviewMetadataApplicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application) =>
				reviewOperationLifecycleTelemetry.wrapApplication(application, () => {
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
				}),
			currentWorkerDerivationEpoch: () => productTransport.workerDerivationEpoch('review'),
			publishCandidateReady: (publication): void => {
				port.postMessage(
					buildBridgeCommWorkerReviewCandidateReadyPublication(publication, createSequence),
				);
			},
			publishCandidateFailed: (publication): void => {
				port.postMessage(
					buildBridgeCommWorkerReviewCandidateFailedPublication(publication, createSequence),
				);
			},
			publishCandidateStarted: (publication): void => {
				port.postMessage(
					buildBridgeCommWorkerReviewCandidateStartedPublication(publication, createSequence),
				);
			},
			publishDisplayPatches: publishReviewDisplayPatches,
		});
		reviewMetadataApplicator = activeReviewMetadataApplicator;
		const installedProductController = new BridgeCommWorkerProductController({
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
			callCurrentFileSource: () =>
				callCurrentFileSourceWithTelemetry({
					productTransport,
					...(props.now === undefined ? {} : { now: props.now }),
					...(props.telemetryClient === undefined
						? {}
						: { telemetryClient: props.telemetryClient }),
				}),
			onAnnotationProjectionConvergence: ({ operationCorrelationId, state, surface }): void => {
				if (operationCorrelationId !== null && state.kind === 'ready') {
					for (const phase of [
						'projection_store_started',
						'main_thread_install_started',
					] as const) {
						recordWorktreeAnnotationLifecycleTelemetry({
							operationCorrelationId,
							phase,
							recorder: props.telemetryClient,
							result: 'started',
							sourceGeneration: state.snapshot.sourceGeneration,
							transport: 'worker',
							viewer: surface === 'file' ? 'file' : 'review',
						});
					}
				}
				port.postMessage(
					bridgeWorkerAnnotationProjectionConvergenceEventSchema.parse(
						bridgeCommWorkerAnnotationProjectionConvergenceEvent({
							operationCorrelationId,
							state,
							surface,
						}),
					),
				);
			},
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
				productController?.setAnnotationProjectionSourceUnavailable('file', _error);
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
				const receipt = activeReviewMetadataApplicator.apply(event, workerDerivationEpoch);
				reviewRenderPublicationAuthority.recordReviewPublicationIdentity(
					activeReviewMetadataApplicator.admittedPublicationIdentity(),
				);
				publishUpdatingChrome();
				return receipt;
			},
			onReviewMetadataFailure: (_error, workerDerivationEpoch): void => {
				activeReviewWorkerDerivationEpoch = workerDerivationEpoch;
				installedReviewSource.handleMetadataFailure(_error);
				reviewDemandScheduling.updateWorkerDerivationEpoch(workerDerivationEpoch);
				publishUpdatingChrome();
				const failureDisposition =
					activeReviewMetadataApplicator.handleMetadataFailure(workerDerivationEpoch);
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
			installedProductController.ensureAnnotationSubscriptions();
		} catch {
			port.postMessage(buildBridgeWorkerRuntimeDegradedHealthEvent());
		}
		try {
			installedProductController.ensureReviewMetadata();
		} catch {}
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
		currentFileMetadataSelectedPathResolved = undefined;
		const handlerStartedAtMilliseconds = readBridgeCommWorkerRuntimeNowMilliseconds(props.now);
		const queueWaitMilliseconds =
			handlerStartedAtMilliseconds -
			(parsedMessage.data.issuedAtMilliseconds ?? handlerStartedAtMilliseconds);
		const messages = handler.handleMessage(parsedMessage.data);
		if (parsedMessage.data.command === 'reviewPublicationInstalled') {
			installedReviewSource.recordInstallation(parsedMessage.data);
		}
		if (parsedMessage.data.command === 'renderDisposition') {
			applyBridgeCommWorkerRenderDispositionRuntimeEffects({
				advanceRenderFulfillmentLifecycle,
				command: parsedMessage.data,
				currentFileOperationCorrelationId: () =>
					selectedFileContentOperationController.current?.operationCorrelationId ?? null,
				messages,
				onFileOperationSettled: (): void => {
					selectedFileContentOperationStore = null;
				},
				publish: (message): void => port.postMessage(message),
				recordFileDisposition: (receipt): void => {
					const currentOperation = selectedFileContentOperationController.current;
					if (currentOperation !== null) {
						selectedFileLifecycleTelemetry.disposition(currentOperation, receipt.disposition);
					}
				},
				settleFileDisposition: (receipt) =>
					settleAcceptedSelectedFileRenderDisposition({
						controller: selectedFileContentOperationController,
						createSequence,
						receipt,
						store: selectedFileContentOperationStore,
					}),
			});
		}
		if (
			parsedMessage.data.command === 'select' &&
			parsedMessage.data.surface === 'fileView' &&
			parsedMessage.data.selectedItemId === null
		) {
			abortAllFileContentPreparations();
			latestSelectedFilePreparationRequest = null;
			cancelSelectedFileContentOperation();
			selectedFileContentOperationStore = null;
		}
		if (parsedMessage.data.command === 'reviewComparisonTargetsQueryCancel') {
			if (activeComparisonTargetsProductControlRequestId === parsedMessage.data.queryRequestId) {
				comparisonTargetsQueryRunner.abort();
				activeComparisonTargetsProductControlRequestId = null;
			}
		}
		if (
			parsedMessage.data.command === 'activeViewerModeUpdate' &&
			bridgeWorkerRuntimeMessagesContainReadyRequest({
				messages,
				requestId: parsedMessage.data.requestId,
			})
		) {
			const activeSource = parsedMessage.data.update.activeSource;
			productController?.setAnnotationProjectionSurfaceActive(
				'file',
				parsedMessage.data.update.mode === 'file' && activeSource?.protocol === 'worktree-file',
				activeSource?.protocol === 'worktree-file' ? activeSource.generation : null,
			);
			productController?.setReviewAnnotationProjectionActive(
				parsedMessage.data.update.mode === 'review',
			);
			if (activeViewerMode === parsedMessage.data.update.mode) {
				publishUpdatingChrome();
			} else {
				activeViewerMode = parsedMessage.data.update.mode;
				if (activeViewerMode !== 'review') {
					comparisonTargetsQueryRunner.abort();
					activeComparisonTargetsProductControlRequestId = null;
				}
				if (activeViewerMode === 'file') {
					reviewDemandScheduling.suspend();
					resumeLatestSelectedFileViewContentReadyPreparation();
				} else {
					abortAllFileContentPreparations();
					cancelSelectedFileContentOperation();
					selectedFileContentOperationStore = null;
					reviewDemandScheduling.resume();
				}
				publishUpdatingChrome();
			}
		}
		const handlerDurationMilliseconds =
			readBridgeCommWorkerRuntimeNowMilliseconds(props.now) - handlerStartedAtMilliseconds;
		recordBridgeCommWorkerTaskTelemetry({
			command: parsedMessage.data.command,
			durationMilliseconds: handlerDurationMilliseconds,
			...(parsedMessage.data.command === 'select' && parsedMessage.data.surface === 'fileView'
				? {
						fileMetadataSelectedPathResolved: currentFileMetadataSelectedPathResolved === true,
					}
				: {}),
			lane: bridgeCommWorkerTelemetryLaneForMessage(parsedMessage.data),
			queueWaitMilliseconds,
			semanticClass: bridgeCommWorkerSemanticClassForMessage(parsedMessage.data),
			taskKind: 'message_handler',
			...(props.telemetryClient === undefined ? {} : { telemetryClient: props.telemetryClient }),
		});
		dispatchBridgeCommWorkerRuntimeProductControl({
			activeReviewWorkerDerivationEpoch,
			comparisonTargetsQueryRunner,
			getActiveComparisonTargetsRequestId: () => activeComparisonTargetsProductControlRequestId,
			mainCommand: parsedMessage.data,
			messages,
			paneWorkSignal: panePresentationAuthority.workSignal,
			publish: (message, transfer): void => {
				if (transfer === undefined) port.postMessage(message);
				else port.postMessage(message, [...transfer]);
			},
			productControlTimeoutMilliseconds,
			productController,
			productTransport,
			reviewMetadataApplicator,
			sendProductControl,
			setActiveComparisonTargetsRequestId: (requestId): void => {
				activeComparisonTargetsProductControlRequestId = requestId;
			},
		});
		if (shouldRequestDrainAfterMessage) {
			requestPreparationDrain();
		}
	});
	port.start?.();
}
