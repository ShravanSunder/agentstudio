import type { WorktreeAnnotationLifecycleTelemetryRecorder } from '../../worktree-annotations/worktree-annotation-lifecycle-telemetry.js';
import {
	BridgeCommWorkerAnnotationProjectionQueryController,
	bridgeCommWorkerAnnotationProjectionTransport,
	type BridgeCommWorkerAnnotationProjectionDemand,
	type BridgeCommWorkerAnnotationProjectionPublication,
	type BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication,
} from './bridge-comm-worker-annotation-projection-query-controller.js';
import {
	bridgeProductWorktreeAnnotationDecodedCommandResultSchema,
	type BridgeProductReviewAnnotationPublicationIdentity,
	type BridgeProductCallResult,
	type BridgeProductWorktreeAnnotationOperation,
} from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeWorkerMetadataInterestRequest } from './bridge-worker-contracts.js';

type FileMetadataSubscription = BridgeProductSubscription<'file.metadata'>;
type FileMetadataEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type FileMetadataEventHandler = (event: FileMetadataEvent, workerDerivationEpoch: number) => void;
type FileMetadataFailureHandler = (error: unknown, workerDerivationEpoch: number) => void;
type FileMetadataDemandFailureHandler = (error: unknown, workerDerivationEpoch: number) => void;
type FileMetadataInterest = Parameters<FileMetadataSubscription['update']>[0]['interests'][number];
type FileMetadataInterestLane = FileMetadataInterest['lane'];
type FileSourceDiscoveryResult = BridgeProductCallResult<'file.source.current'>;
type ReviewMetadataSubscription = BridgeProductSubscription<'review.metadata'>;
type ReviewMetadataEvent = BridgeProductSubscriptionEvent<'review.metadata'>;
type ReviewMetadataEventHandler = (
	event: ReviewMetadataEvent,
	workerDerivationEpoch: number,
) =>
	| Promise<{ readonly publicationId: string } | null | void>
	| { readonly publicationId: string }
	| null
	| void;
type ReviewMetadataFailureHandler = (error: unknown, workerDerivationEpoch: number) => void;
type ReviewMetadataInterest = Parameters<
	ReviewMetadataSubscription['update']
>[0]['interests'][number];
type ReviewMetadataInterestLane = ReviewMetadataInterest['lane'];

export interface BridgeCommWorkerFileMetadataDemand {
	readonly epoch: number;
	readonly nearbyPaths: readonly string[];
	readonly selectedPath: string | null;
	readonly visiblePaths: readonly string[];
}

export class BridgeCommWorkerProductController {
	readonly #annotationProjectionBySurface: Record<
		'file' | 'review',
		BridgeCommWorkerAnnotationProjectionQueryController
	>;
	readonly #onFileMetadataEvent: FileMetadataEventHandler;
	readonly #onFileMetadataFailure: FileMetadataFailureHandler;
	readonly #onFileMetadataDemandFailure: FileMetadataDemandFailureHandler;
	readonly #onReviewMetadataEvent: ReviewMetadataEventHandler;
	readonly #onReviewMetadataFailure: ReviewMetadataFailureHandler;
	readonly #productTransport: BridgeProductTransportSession;
	readonly #annotationSessionIdsBySurface: Record<'file' | 'review', Set<string>> = {
		file: new Set(),
		review: new Set(),
	};
	readonly #annotationSurfaceActive: Record<'file' | 'review', boolean> = {
		file: false,
		review: false,
	};
	readonly #annotationSourceGeneration: Record<'file' | 'review', number | null> = {
		file: null,
		review: null,
	};
	#reviewAnnotationPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null =
		null;
	readonly #annotationSourceReconciliationBySurface: Record<
		'file' | 'review',
		Promise<void> | null
	> = { file: null, review: null };
	readonly #callCurrentFileSource: () => Promise<FileSourceDiscoveryResult>;
	readonly #subscribeFile: (
		options: BridgeProductSubscriptionOptions<'file.metadata'>,
	) => FileMetadataSubscription;
	readonly #subscribeReview: (
		options: BridgeProductSubscriptionOptions<'review.metadata'>,
	) => ReviewMetadataSubscription;
	#fileSubscription: FileMetadataSubscription | null = null;
	#fileSource: FileMetadataEvent['source'] | null = null;
	#filePathScope: readonly string[] = [];
	readonly #fileInterestPathsByLane = new Map<FileMetadataInterestLane, readonly string[]>();
	#fileInterestRevision = 0;
	#fileInterestUpdate: Promise<void> = Promise.resolve();
	#fileInterestUpdateFailed = false;
	#fileDesiredInterestSignature: string | null = null;
	#hasPublishedFileMetadataInterests = false;
	#fileWorkerDerivationEpoch = 0;
	#fileDemandEpoch = 0;
	#hasFileMetadataDemand = false;
	#fileSourceEnsure: Promise<void> | null = null;
	#reviewSubscription: ReviewMetadataSubscription | null = null;
	readonly #reviewInterestItemIdsByLane = new Map<ReviewMetadataInterestLane, readonly string[]>();
	#reviewInterestUpdate: Promise<void> = Promise.resolve();
	#reviewDesiredInterestSignature: string | null = null;
	#reviewRecoveryPublicationId: string | null = null;
	#reviewWorkerDerivationEpoch = 0;

	constructor(props: {
		readonly callCurrentFileSource?: () => Promise<FileSourceDiscoveryResult>;
		readonly onAnnotationProjectionConvergence?: (
			publication: BridgeCommWorkerAnnotationProjectionPublication,
		) => void;
		readonly onFileMetadataEvent: FileMetadataEventHandler;
		readonly onFileMetadataFailure?: FileMetadataFailureHandler;
		readonly onFileMetadataDemandFailure?: FileMetadataDemandFailureHandler;
		readonly onReviewMetadataEvent?: ReviewMetadataEventHandler;
		readonly onReviewMetadataFailure?: ReviewMetadataFailureHandler;
		readonly productTransport: BridgeProductTransportSession;
		readonly telemetryClient?: WorktreeAnnotationLifecycleTelemetryRecorder | undefined;
		readonly subscribeFile?: (
			options: BridgeProductSubscriptionOptions<'file.metadata'>,
		) => FileMetadataSubscription;
		readonly subscribeReview?: (
			options: BridgeProductSubscriptionOptions<'review.metadata'>,
		) => ReviewMetadataSubscription;
	}) {
		this.#onFileMetadataEvent = props.onFileMetadataEvent;
		this.#onFileMetadataFailure = props.onFileMetadataFailure ?? ignoreFileMetadataFailure;
		this.#onFileMetadataDemandFailure =
			props.onFileMetadataDemandFailure ?? ignoreFileMetadataFailure;
		this.#onReviewMetadataEvent = props.onReviewMetadataEvent ?? ignoreReviewMetadataEvent;
		this.#onReviewMetadataFailure = props.onReviewMetadataFailure ?? ignoreReviewMetadataFailure;
		this.#productTransport = props.productTransport;
		const onConvergence =
			props.onAnnotationProjectionConvergence ?? ignoreAnnotationProjectionConvergence;
		const annotationProjectionTransport = bridgeCommWorkerAnnotationProjectionTransport(
			props.productTransport,
		);
		this.#annotationProjectionBySurface = {
			file: new BridgeCommWorkerAnnotationProjectionQueryController({
				onConvergence,
				onSourceAuthorityStale: (publication): void => {
					void this.reconcileAnnotationProjectionSourceAuthority(publication);
				},
				surface: 'file',
				transport: annotationProjectionTransport,
				telemetryClient: props.telemetryClient,
			}),
			review: new BridgeCommWorkerAnnotationProjectionQueryController({
				onConvergence,
				onSourceAuthorityStale: (publication): void => {
					void this.reconcileAnnotationProjectionSourceAuthority(publication);
				},
				surface: 'review',
				transport: annotationProjectionTransport,
				telemetryClient: props.telemetryClient,
			}),
		};
		this.#callCurrentFileSource =
			props.callCurrentFileSource ??
			((): Promise<FileSourceDiscoveryResult> =>
				this.#productTransport.call('file.source.current', {}));
		this.#subscribeFile =
			props.subscribeFile ??
			((options): FileMetadataSubscription =>
				this.#productTransport.subscribe('file.metadata', options));
		this.#subscribeReview =
			props.subscribeReview ??
			((options): ReviewMetadataSubscription =>
				this.#productTransport.subscribe('review.metadata', options));
	}

	ensureAnnotationSubscriptions(): void {
		this.#annotationProjectionBySurface.file.ensureSubscription();
		this.#annotationProjectionBySurface.review.ensureSubscription();
	}

	setAnnotationProjectionSurfaceActive(
		surface: 'file' | 'review',
		active: boolean,
		sourceGeneration: number | null,
	): void {
		this.#annotationSurfaceActive[surface] = active;
		this.#annotationSourceGeneration[surface] = sourceGeneration;
		this.#publishAnnotationProjectionDemand(surface);
	}

	setReviewAnnotationProjectionActive(active: boolean): void {
		this.#annotationSurfaceActive.review = active;
		this.#publishAnnotationProjectionDemand('review');
	}

	setReviewAnnotationProjectionIdentity(
		identity: BridgeProductReviewAnnotationPublicationIdentity | null,
	): void {
		this.#reviewAnnotationPublicationIdentity = identity;
		this.#annotationSourceGeneration.review = identity?.reviewGeneration ?? null;
		this.#publishAnnotationProjectionDemand('review');
	}

	retryAnnotationProjection(surface: 'file' | 'review'): void {
		this.#annotationProjectionBySurface[surface].retry();
	}

	setAnnotationProjectionSourceUnavailable(surface: 'file' | 'review', error: unknown): void {
		this.#annotationProjectionBySurface[surface].sourceUnavailable(error);
	}

	reconcileAnnotationProjectionSourceAuthority(
		publication: BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication,
	): Promise<void> {
		if (publication.currentSourceGeneration <= publication.requestedSourceGeneration) {
			this.setAnnotationProjectionSourceUnavailable(
				publication.surface,
				new Error('Annotation projection source authority did not advance.'),
			);
			return Promise.resolve();
		}
		const existingReconciliation =
			this.#annotationSourceReconciliationBySurface[publication.surface];
		if (existingReconciliation !== null) return existingReconciliation;
		const reconciliation = this.#reopenAnnotationProjectionSourceAuthority(
			publication.surface,
		).catch((error: unknown): void => {
			this.setAnnotationProjectionSourceUnavailable(publication.surface, error);
		});
		const trackedReconciliation = reconciliation.finally((): void => {
			if (
				this.#annotationSourceReconciliationBySurface[publication.surface] === trackedReconciliation
			) {
				this.#annotationSourceReconciliationBySurface[publication.surface] = null;
			}
		});
		this.#annotationSourceReconciliationBySurface[publication.surface] = trackedReconciliation;
		return trackedReconciliation;
	}

	async disposeAnnotationProjections(): Promise<void> {
		await Promise.all([
			this.#annotationProjectionBySurface.file.dispose(),
			this.#annotationProjectionBySurface.review.dispose(),
		]);
	}

	async #reopenAnnotationProjectionSourceAuthority(surface: 'file' | 'review'): Promise<void> {
		if (surface === 'file') {
			const subscription = this.#fileSubscription;
			this.#fileSubscription = null;
			this.#fileSource = null;
			this.#fileSourceEnsure = null;
			this.#fileDesiredInterestSignature = null;
			this.#hasPublishedFileMetadataInterests = false;
			this.#fileInterestRevision += 1;
			this.#fileInterestUpdate = Promise.resolve();
			this.#fileInterestUpdateFailed = false;
			if (subscription !== null) {
				try {
					await subscription.cancel();
				} catch {
					// The replacement source authority supersedes the retired subscription locally.
				}
			}
			await this.ensureFileSource();
			return;
		}
		const subscription = this.#reviewSubscription;
		this.#reviewSubscription = null;
		this.#reviewDesiredInterestSignature = null;
		this.#reviewInterestUpdate = Promise.resolve();
		this.#reviewRecoveryPublicationId = null;
		if (subscription !== null) {
			try {
				await subscription.cancel();
			} catch {
				// The replacement source authority supersedes the retired subscription locally.
			}
		}
		this.ensureReviewMetadata();
	}

	ensureFileSource(): Promise<void> {
		if (this.#fileSourceEnsure !== null) return this.#fileSourceEnsure;
		const discoveryAttempt = this.#discoverAndOpenFileSource();
		const memoizedAttempt = discoveryAttempt.catch((error: unknown): never => {
			if (this.#fileSourceEnsure === memoizedAttempt) {
				this.#fileSourceEnsure = null;
			}
			throw error;
		});
		this.#fileSourceEnsure = memoizedAttempt;
		return memoizedAttempt;
	}

	ensureReviewMetadata(): void {
		if (this.#reviewSubscription !== null) return;
		const interests = reviewMetadataInterestsInPriorityOrder(this.#reviewInterestItemIdsByLane);
		const workerDerivationEpoch = this.#productTransport.bumpWorkerDerivationEpoch('review');
		this.#reviewWorkerDerivationEpoch = workerDerivationEpoch;
		this.#reviewDesiredInterestSignature = JSON.stringify(interests);
		try {
			const subscription = this.#subscribeReview({ interests });
			this.#reviewSubscription = subscription;
			void this.#consumeReviewMetadataEvents(subscription, workerDerivationEpoch).catch(
				(): void => {},
			);
		} catch (error) {
			this.#reviewDesiredInterestSignature = null;
			this.#onReviewMetadataFailure(error, workerDerivationEpoch);
			throw error;
		}
	}

	async sendProductControl(command: BridgeProductControlCommand): Promise<unknown> {
		switch (command.method) {
			case 'file.refresh.retry':
				return await this.#productTransport.call('file.refresh.retry', {});
			case 'file.annotations.command':
				return await this.#sendAnnotationCommand('file', command.params.operation, null);
			case 'review.annotations.command':
				return await this.#sendAnnotationCommand(
					'review',
					command.params.operation,
					command.params['reviewPublicationIdentity'],
				);
			case 'review.markFileViewed':
				return await this.#productTransport.call('review.markFileViewed', {
					itemId: command.params.fileId,
				});
			case 'review.comparison.update':
				return await this.#productTransport.call('review.comparison.update', {
					target: command.params.target,
				});
			case 'review.comparisonTargets.query':
				return await this.#productTransport.call('review.comparisonTargets.query', {});
			case 'review.publication.install.admit':
				return await this.#productTransport.call(
					'review.publication.install.admit',
					command.params,
				);
			case 'review.publication.applied':
				return await this.#productTransport.call('review.publication.applied', command.params);
			case 'bridge.activeViewerMode.update':
				return await this.#sendActiveViewerModeUpdate(command);
			case 'bridge.intakeReady':
				return await this.#productTransport.call('review.intake.ready', {
					reason: command.params.reason ?? null,
					streamId: command.params.streamId ?? null,
				});
			default:
				return assertNeverBridgeProductControlCommand(command);
		}
	}

	async #sendAnnotationCommand(
		surface: 'file' | 'review',
		operation: BridgeProductWorktreeAnnotationOperation,
		reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null,
	): Promise<unknown> {
		const result =
			surface === 'file'
				? await this.#productTransport.call('file.annotations.command', { operation })
				: await this.#productTransport.call('review.annotations.command', {
						operation,
						reviewPublicationIdentity:
							requireReviewAnnotationPublicationIdentity(reviewPublicationIdentity),
					});
		const parsedResult = bridgeProductWorktreeAnnotationDecodedCommandResultSchema.parse(result);
		if (parsedResult.outcome.status.kind !== 'committed') return parsedResult;
		if (operation.kind === 'demand.acquire') {
			this.#annotationSessionIdsBySurface[surface].add(operation.sessionId);
			this.#publishAnnotationProjectionDemand(surface);
		} else if (operation.kind === 'demand.release') {
			this.#annotationSessionIdsBySurface[surface].delete(operation.sessionId);
			this.#publishAnnotationProjectionDemand(surface);
		}
		return parsedResult;
	}

	#publishAnnotationProjectionDemand(surface: 'file' | 'review'): void {
		this.#annotationProjectionBySurface[surface].setDemand({
			active: this.#annotationSurfaceActive[surface],
			reviewPublicationIdentity:
				surface === 'review' ? this.#reviewAnnotationPublicationIdentity : null,
			sessionIds: [...this.#annotationSessionIdsBySurface[surface]],
			sourceGeneration: this.#annotationSourceGeneration[surface],
		} satisfies BridgeCommWorkerAnnotationProjectionDemand);
	}

	async updateReviewMetadataInterests(request: BridgeWorkerMetadataInterestRequest): Promise<void> {
		this.#replaceReviewInterestLane(request.lane, request.itemIds ?? []);
		const interests = reviewMetadataInterestsInPriorityOrder(this.#reviewInterestItemIdsByLane);
		if (this.#reviewSubscription === null) {
			this.ensureReviewMetadata();
			return;
		}
		const signature = JSON.stringify(interests);
		if (signature === this.#reviewDesiredInterestSignature) {
			await this.#reviewInterestUpdate;
			return;
		}
		this.#reviewDesiredInterestSignature = signature;
		const subscription = this.#reviewSubscription;
		const workerDerivationEpoch = this.#reviewWorkerDerivationEpoch;
		const nextUpdate = this.#reviewInterestUpdate
			.catch((): void => {})
			.then(async (): Promise<void> => {
				if (subscription !== this.#reviewSubscription) return;
				try {
					await subscription.update({ interests });
				} catch (error) {
					if (subscription === this.#reviewSubscription) {
						this.#reviewDesiredInterestSignature = null;
						this.#onReviewMetadataFailure(error, workerDerivationEpoch);
					}
					throw error;
				}
			});
		this.#reviewInterestUpdate = nextUpdate;
		await nextUpdate;
	}

	#replaceReviewInterestLane(lane: ReviewMetadataInterestLane, itemIds: readonly string[]): void {
		const uniqueItemIds = [...new Set(itemIds)];
		if (uniqueItemIds.length === 0) {
			this.#reviewInterestItemIdsByLane.delete(lane);
			return;
		}
		this.#reviewInterestItemIdsByLane.set(lane, uniqueItemIds);
	}

	async #consumeReviewMetadataEvents(
		subscription: ReviewMetadataSubscription,
		workerDerivationEpoch: number,
	): Promise<void> {
		try {
			for await (const event of subscription.events) {
				if (subscription !== this.#reviewSubscription) return;
				try {
					const applicationReceipt = await this.#onReviewMetadataEvent(
						event,
						workerDerivationEpoch,
					);
					if (
						applicationReceipt === null ||
						applicationReceipt === undefined ||
						subscription !== this.#reviewSubscription
					) {
						continue;
					}
					this.#reviewRecoveryPublicationId = null;
				} catch (error) {
					await this.#recoverReviewMetadataApplicationFailure(
						subscription,
						workerDerivationEpoch,
						error,
						event.publicationId,
					);
					return;
				}
			}
		} catch (error) {
			if (subscription === this.#reviewSubscription) {
				this.#reviewSubscription = null;
				this.#reviewDesiredInterestSignature = null;
				this.#onReviewMetadataFailure(error, workerDerivationEpoch);
				throw error;
			}
		}
		if (subscription === this.#reviewSubscription) {
			const error = new Error('Bridge Review metadata subscription ended unexpectedly.');
			this.#reviewSubscription = null;
			this.#reviewDesiredInterestSignature = null;
			this.#onReviewMetadataFailure(error, workerDerivationEpoch);
			throw error;
		}
	}

	async #recoverReviewMetadataApplicationFailure(
		subscription: ReviewMetadataSubscription,
		workerDerivationEpoch: number,
		error: unknown,
		publicationId: string,
	): Promise<void> {
		if (subscription !== this.#reviewSubscription) return;
		this.#onReviewMetadataFailure(error, workerDerivationEpoch);
		const shouldReopen = this.#reviewRecoveryPublicationId !== publicationId;
		this.#reviewRecoveryPublicationId = publicationId;
		try {
			await subscription.cancel();
		} catch {
			// Reopening with a new derivation epoch supersedes the failed subscription locally.
		}
		if (subscription !== this.#reviewSubscription) return;
		this.#reviewSubscription = null;
		this.#reviewDesiredInterestSignature = null;
		this.#reviewInterestUpdate = Promise.resolve();
		if (!shouldReopen) return;
		try {
			this.ensureReviewMetadata();
		} catch {
			// ensureReviewMetadata publishes the typed failure through the injected callback.
		}
	}

	async updateFileMetadataDemand(demand: BridgeCommWorkerFileMetadataDemand): Promise<void> {
		if (demand.epoch < this.#fileDemandEpoch) return;
		this.#fileDemandEpoch = demand.epoch;
		this.#hasFileMetadataDemand = true;
		const selectedPaths = demand.selectedPath === null ? [] : [demand.selectedPath];
		const selectedPathSet = new Set(selectedPaths);
		const visiblePaths = uniqueFileDemandPaths(demand.visiblePaths).filter(
			(path) => !selectedPathSet.has(path),
		);
		const selectedOrVisiblePathSet = new Set([...selectedPaths, ...visiblePaths]);
		const nearbyPaths = uniqueFileDemandPaths(demand.nearbyPaths).filter(
			(path) => !selectedOrVisiblePathSet.has(path),
		);
		this.#replaceFileInterestLane('foreground', selectedPaths);
		this.#replaceFileInterestLane('visible', visiblePaths);
		this.#replaceFileInterestLane('nearby', nearbyPaths);
		await this.#publishFileMetadataInterests();
	}

	async #discoverAndOpenFileSource(): Promise<void> {
		const discovery = await this.#callCurrentFileSource();
		if (discovery.status === 'unavailable') {
			return;
		}
		const workerDerivationEpoch = this.#productTransport.bumpWorkerDerivationEpoch('file');
		this.#fileWorkerDerivationEpoch = workerDerivationEpoch;
		this.#filePathScope = [];
		this.#fileDesiredInterestSignature = null;
		this.#hasPublishedFileMetadataInterests = false;
		this.#fileInterestRevision += 1;
		const subscription = this.#subscribeFile({
			interests: [],
			pathScope: [],
			source: discovery.source,
		});
		this.#fileSubscription = subscription;
		void this.#consumeFileMetadataEvents(subscription, workerDerivationEpoch).catch((): void => {});
	}

	#replaceFileInterestLane(lane: FileMetadataInterestLane, paths: readonly string[]): void {
		const uniquePaths = uniqueFileDemandPaths(paths);
		if (uniquePaths.length === 0) {
			this.#fileInterestPathsByLane.delete(lane);
			return;
		}
		this.#fileInterestPathsByLane.set(lane, uniquePaths);
	}

	async #publishFileMetadataInterests(): Promise<void> {
		if (!this.#hasFileMetadataDemand) {
			return;
		}
		const subscription = this.#fileSubscription;
		const source = this.#fileSource;
		if (subscription === null || source === null) {
			return;
		}
		const interests = fileMetadataInterestsInPriorityOrder(this.#fileInterestPathsByLane);
		if (interests.length === 0 && !this.#hasPublishedFileMetadataInterests) {
			return;
		}
		const update = {
			interests,
			pathScope: this.#filePathScope,
		};
		const signature = JSON.stringify({
			interests,
			pathScope: this.#filePathScope,
			sourceId: source.sourceId,
			subscriptionGeneration: source.subscriptionGeneration,
		});
		if (signature === this.#fileDesiredInterestSignature) {
			await this.#fileInterestUpdate;
			return;
		}
		this.#fileDesiredInterestSignature = signature;
		this.#fileInterestRevision += 1;
		const interestRevision = this.#fileInterestRevision;
		const workerDerivationEpoch = this.#fileWorkerDerivationEpoch;
		if (this.#fileInterestUpdateFailed) {
			const retryUpdate = this.#performFileMetadataInterestUpdate({
				interestRevision,
				subscription,
				update,
				workerDerivationEpoch,
			});
			this.#fileInterestUpdate = retryUpdate;
			await retryUpdate;
			return;
		}
		const nextUpdate = this.#fileInterestUpdate
			.catch((): void => {})
			.then(
				(): Promise<void> =>
					this.#performFileMetadataInterestUpdate({
						interestRevision,
						subscription,
						update,
						workerDerivationEpoch,
					}),
			);
		this.#fileInterestUpdate = nextUpdate;
		await nextUpdate;
	}

	async #performFileMetadataInterestUpdate(props: {
		readonly interestRevision: number;
		readonly subscription: FileMetadataSubscription;
		readonly update: Parameters<FileMetadataSubscription['update']>[0];
		readonly workerDerivationEpoch: number;
	}): Promise<void> {
		if (
			props.subscription !== this.#fileSubscription ||
			props.interestRevision !== this.#fileInterestRevision
		) {
			return;
		}
		try {
			await props.subscription.update(props.update);
			this.#hasPublishedFileMetadataInterests = true;
			this.#fileInterestUpdateFailed = false;
		} catch (error) {
			if (props.subscription === this.#fileSubscription) {
				this.#fileDesiredInterestSignature = null;
				this.#fileInterestUpdateFailed = true;
				this.#onFileMetadataDemandFailure(error, props.workerDerivationEpoch);
			}
			throw error;
		}
	}

	async #consumeFileMetadataEvents(
		subscription: FileMetadataSubscription,
		workerDerivationEpoch: number,
	): Promise<void> {
		try {
			for await (const event of subscription.events) {
				if (subscription !== this.#fileSubscription) return;
				this.#fileSource = event.source;
				this.#onFileMetadataEvent(event, workerDerivationEpoch);
				if (event.eventKind === 'file.sourceAccepted' || this.#hasFileMetadataDemand) {
					this.#scheduleFileMetadataInterestPublication();
				}
			}
		} catch (error) {
			if (this.#retireFailedFileMetadataSubscription(subscription)) {
				this.#onFileMetadataFailure(error, workerDerivationEpoch);
				throw error;
			}
		}
		if (this.#retireFailedFileMetadataSubscription(subscription)) {
			const error = new Error('Bridge File metadata subscription ended unexpectedly.');
			this.#onFileMetadataFailure(error, workerDerivationEpoch);
			throw error;
		}
	}

	#retireFailedFileMetadataSubscription(subscription: FileMetadataSubscription): boolean {
		if (subscription !== this.#fileSubscription) return false;
		this.#fileSubscription = null;
		this.#fileSource = null;
		this.#fileSourceEnsure = null;
		this.#fileDesiredInterestSignature = null;
		this.#hasPublishedFileMetadataInterests = false;
		this.#fileInterestUpdate = Promise.resolve();
		this.#fileInterestUpdateFailed = false;
		return true;
	}

	#scheduleFileMetadataInterestPublication(): void {
		void this.#publishFileMetadataInterests()
			.catch((): void => {})
			.then((): void => {
				if (!this.#fileInterestUpdateFailed) return;
				void this.#publishFileMetadataInterests().catch((): void => {});
			});
	}

	async #sendActiveViewerModeUpdate(
		command: Extract<
			BridgeProductControlCommand,
			{ readonly method: 'bridge.activeViewerMode.update' }
		>,
	): Promise<unknown> {
		const expectedProtocol = command.params.mode === 'review' ? 'review' : 'worktree-file';
		if (
			command.params.activeSource !== null &&
			command.params.activeSource.protocol !== expectedProtocol
		) {
			throw new Error('Bridge active viewer source does not match its selected surface.');
		}
		const request = {
			activeSource:
				command.params.activeSource === null
					? null
					: {
							generation: command.params.activeSource.generation,
							streamId: command.params.activeSource.streamId,
						},
			nativeSelectionRequestId: command.params.nativeSelectionRequestId,
			sequence: command.params.sequence,
			sessionId: command.params.sessionId,
		};
		return command.params.mode === 'review'
			? await this.#productTransport.call('review.activeViewerMode.update', request)
			: await this.#productTransport.call('file.activeViewerMode.update', request);
	}
}

function requireReviewAnnotationPublicationIdentity(
	identity: BridgeProductReviewAnnotationPublicationIdentity | null,
): BridgeProductReviewAnnotationPublicationIdentity {
	if (identity === null) {
		throw new Error('Review annotation command has no installed publication identity.');
	}
	return identity;
}

const fileMetadataInterestLanePriority: readonly FileMetadataInterestLane[] = [
	'foreground',
	'visible',
	'nearby',
	'active',
	'speculative',
	'idle',
];

const reviewMetadataInterestLanePriority: readonly ReviewMetadataInterestLane[] = [
	'foreground',
	'visible',
	'nearby',
	'active',
	'speculative',
	'idle',
];

function reviewMetadataInterestsInPriorityOrder(
	itemIdsByLane: ReadonlyMap<ReviewMetadataInterestLane, readonly string[]>,
): readonly ReviewMetadataInterest[] {
	const claimedItemIds = new Set<string>();
	const interests: ReviewMetadataInterest[] = [];
	for (const lane of reviewMetadataInterestLanePriority) {
		const remainingItemCount =
			BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT - claimedItemIds.size;
		if (remainingItemCount <= 0) break;
		const itemIds: string[] = [];
		for (const itemId of itemIdsByLane.get(lane) ?? []) {
			if (claimedItemIds.has(itemId)) continue;
			claimedItemIds.add(itemId);
			itemIds.push(itemId);
			if (itemIds.length === remainingItemCount) break;
		}
		if (itemIds.length > 0) interests.push({ itemIds, lane });
	}
	return interests;
}

function fileMetadataInterestsInPriorityOrder(
	pathsByLane: ReadonlyMap<FileMetadataInterestLane, readonly string[]>,
): readonly FileMetadataInterest[] {
	const claimedPaths = new Set<string>();
	const interests: FileMetadataInterest[] = [];
	for (const lane of fileMetadataInterestLanePriority) {
		const remainingPathCount =
			BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT - claimedPaths.size;
		if (remainingPathCount <= 0) break;
		const paths: string[] = [];
		for (const path of pathsByLane.get(lane) ?? []) {
			if (claimedPaths.has(path)) continue;
			claimedPaths.add(path);
			paths.push(path);
			if (paths.length === remainingPathCount) break;
		}
		if (paths.length > 0) interests.push({ lane, paths });
	}
	return interests;
}

function uniqueFileDemandPaths(paths: readonly string[]): readonly string[] {
	return [...new Set(paths)];
}

function assertNeverBridgeProductControlCommand(command: never): never {
	throw new Error(`Unhandled Bridge product command: ${JSON.stringify(command)}`);
}

function ignoreFileMetadataFailure(_error: unknown, _workerDerivationEpoch: number): void {}

function ignoreReviewMetadataEvent(
	_event: ReviewMetadataEvent,
	_workerDerivationEpoch: number,
): null {
	return null;
}

function ignoreReviewMetadataFailure(_error: unknown, _workerDerivationEpoch: number): void {}

function ignoreAnnotationProjectionConvergence(
	_publication: BridgeCommWorkerAnnotationProjectionPublication,
): void {}
