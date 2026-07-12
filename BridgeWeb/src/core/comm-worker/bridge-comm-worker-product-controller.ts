import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import type { BridgeProductCallResult } from './bridge-product-call-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

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
) => void;
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
	readonly #onFileMetadataEvent: FileMetadataEventHandler;
	readonly #onFileMetadataFailure: FileMetadataFailureHandler;
	readonly #onFileMetadataDemandFailure: FileMetadataDemandFailureHandler;
	readonly #onReviewMetadataEvent: ReviewMetadataEventHandler;
	readonly #onReviewMetadataFailure: ReviewMetadataFailureHandler;
	readonly #productTransport: BridgeProductTransportSession;
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
	#reviewWorkerDerivationEpoch = 0;

	constructor(props: {
		readonly callCurrentFileSource?: () => Promise<FileSourceDiscoveryResult>;
		readonly onFileMetadataEvent: FileMetadataEventHandler;
		readonly onFileMetadataFailure?: FileMetadataFailureHandler;
		readonly onFileMetadataDemandFailure?: FileMetadataDemandFailureHandler;
		readonly onReviewMetadataEvent?: ReviewMetadataEventHandler;
		readonly onReviewMetadataFailure?: ReviewMetadataFailureHandler;
		readonly productTransport: BridgeProductTransportSession;
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

	ensureFileSource(): Promise<void> {
		this.#fileSourceEnsure ??= this.#discoverAndOpenFileSource();
		return this.#fileSourceEnsure;
	}

	async send(command: BridgeRPCCommand): Promise<unknown> {
		switch (command.method) {
			case 'review.markFileViewed':
				return await this.#productTransport.call('review.markFileViewed', {
					itemId: command.params.fileId,
				});
			case 'bridge.activeViewerMode.update':
				return await this.#sendActiveViewerModeUpdate(command);
			case 'bridge.metadata_interest.update':
				return await this.#updateReviewMetadataInterests(command.params);
			case 'bridge.intakeReady':
				throw new Error('Bridge intake readiness is local to the comm worker.');
			default:
				return assertNeverBridgeRPCCommand(command);
		}
	}

	async #updateReviewMetadataInterests(
		request: Extract<
			BridgeRPCCommand,
			{ readonly method: 'bridge.metadata_interest.update' }
		>['params'],
	): Promise<void> {
		this.#replaceReviewInterestLane(request.lane, request.itemIds ?? []);
		const interests = reviewMetadataInterestsInPriorityOrder(this.#reviewInterestItemIdsByLane);
		if (this.#reviewSubscription === null) {
			const workerDerivationEpoch = this.#productTransport.bumpWorkerDerivationEpoch('review');
			this.#reviewWorkerDerivationEpoch = workerDerivationEpoch;
			this.#reviewDesiredInterestSignature = JSON.stringify(interests);
			const subscription = this.#subscribeReview({ interests });
			this.#reviewSubscription = subscription;
			void this.#consumeReviewMetadataEvents(subscription, workerDerivationEpoch).catch(
				(): void => {},
			);
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
				this.#onReviewMetadataEvent(event, workerDerivationEpoch);
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
					await this.#publishFileMetadataInterests().catch((): void => {});
					if (this.#fileInterestUpdateFailed) {
						await this.#publishFileMetadataInterests().catch((): void => {});
					}
				}
			}
		} catch (error) {
			if (subscription === this.#fileSubscription) {
				this.#fileSubscription = null;
				this.#onFileMetadataFailure(error, workerDerivationEpoch);
				throw error;
			}
		}
		if (subscription === this.#fileSubscription) {
			const error = new Error('Bridge File metadata subscription ended unexpectedly.');
			this.#fileSubscription = null;
			this.#onFileMetadataFailure(error, workerDerivationEpoch);
			throw error;
		}
	}

	async #sendActiveViewerModeUpdate(
		command: Extract<BridgeRPCCommand, { readonly method: 'bridge.activeViewerMode.update' }>,
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
			sequence: command.params.sequence,
			sessionId: command.params.sessionId,
		};
		return command.params.mode === 'review'
			? await this.#productTransport.call('review.activeViewerMode.update', request)
			: await this.#productTransport.call('file.activeViewerMode.update', request);
	}
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

function assertNeverBridgeRPCCommand(command: never): never {
	throw new Error(`Unhandled Bridge product command: ${JSON.stringify(command)}`);
}

function ignoreFileMetadataFailure(_error: unknown, _workerDerivationEpoch: number): void {}

function ignoreReviewMetadataEvent(
	_event: ReviewMetadataEvent,
	_workerDerivationEpoch: number,
): void {}

function ignoreReviewMetadataFailure(_error: unknown, _workerDerivationEpoch: number): void {}
