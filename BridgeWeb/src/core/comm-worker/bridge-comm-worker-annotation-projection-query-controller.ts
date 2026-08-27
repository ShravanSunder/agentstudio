import {
	recordWorktreeAnnotationLifecycleTelemetry,
	type WorktreeAnnotationLifecycleTelemetryRecorder,
} from '../../worktree-annotations/worktree-annotation-lifecycle-telemetry.js';
import { type BridgeCommWorkerAnnotationCatalog } from './bridge-comm-worker-annotation-catalog-applicator.js';
import { BridgeCommWorkerAnnotationMetadataApplication } from './bridge-comm-worker-annotation-metadata-application.js';
import {
	BridgeCommWorkerAnnotationProjectionDecoder,
	type BridgeWorkerAnnotationProjectionSnapshot,
} from './bridge-comm-worker-annotation-projection-decoder.js';
import { scheduleBridgeCommWorkerTaskBoundary } from './bridge-comm-worker-task-boundary.js';
import {
	bridgeProductFileAnnotationMetadataApplicationProtocol,
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeProductContentStream,
	BridgeProductMetadataApplicationSubscription,
} from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import { bridgeProductWorktreeAnnotationEventSchema } from './bridge-product-worktree-annotation-contracts.js';
import {
	bridgeProductAnnotationProjectionQueryResultSchema,
	type BridgeProductAnnotationProjectionContentDescriptor,
	type BridgeProductAnnotationProjectionPageContract,
	type BridgeProductAnnotationProjectionQueryRequest,
	type BridgeProductAnnotationProjectionQueryResult,
	type BridgeProductReviewAnnotationPublicationIdentity,
} from './bridge-product-worktree-annotation-projection-query-contracts.js';

export type BridgeCommWorkerAnnotationSurface = 'file' | 'review';

type AnnotationMetadataProtocol =
	| typeof bridgeProductFileAnnotationMetadataApplicationProtocol
	| typeof bridgeProductReviewAnnotationMetadataApplicationProtocol;
type AnnotationMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<AnnotationMetadataProtocol>;

export interface BridgeCommWorkerAnnotationProjectionDemand {
	readonly active: boolean;
	readonly reviewPublicationIdentity?: BridgeProductReviewAnnotationPublicationIdentity | null;
	readonly sessionIds: readonly string[];
	readonly sourceGeneration: number | null;
}

export interface BridgeCommWorkerAnnotationProjectionPublication {
	readonly operationCorrelationId: string | null;
	readonly state:
		| { readonly error: unknown; readonly kind: 'unavailable' }
		| {
				readonly contentSessionIds: readonly string[];
				readonly kind: 'ready';
				readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot;
		  }
		| { readonly kind: 'refreshing' };
	readonly surface: BridgeCommWorkerAnnotationSurface;
}

export interface BridgeCommWorkerAnnotationCatalogPublication {
	readonly catalog: BridgeCommWorkerAnnotationCatalog;
	readonly operationCorrelationId: string;
	readonly surface: BridgeCommWorkerAnnotationSurface;
}

export interface BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication {
	readonly currentSourceGeneration: number;
	readonly requestedSourceGeneration: number;
	readonly surface: BridgeCommWorkerAnnotationSurface;
}

interface CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps {
	readonly onCatalog: (publication: BridgeCommWorkerAnnotationCatalogPublication) => void;
	readonly onConvergence: (publication: BridgeCommWorkerAnnotationProjectionPublication) => void;
	readonly onSourceAuthorityStale: (
		publication: BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication,
	) => void;
	readonly surface: BridgeCommWorkerAnnotationSurface;
	readonly telemetryClient?: WorktreeAnnotationLifecycleTelemetryRecorder | undefined;
	readonly transport: BridgeCommWorkerAnnotationProjectionTransport;
}

export interface BridgeCommWorkerAnnotationProjectionTransport {
	readonly callProjection: (
		surface: BridgeCommWorkerAnnotationSurface,
		request: BridgeProductAnnotationProjectionQueryRequest,
		signal: AbortSignal,
	) => Promise<unknown>;
	readonly openContent: (
		descriptor: BridgeProductAnnotationProjectionContentDescriptor,
		signal: AbortSignal,
	) => BridgeProductContentStream<'annotation.projection'>;
	readonly subscribe: (
		surface: BridgeCommWorkerAnnotationSurface,
	) => AnnotationMetadataSubscription;
}

interface AnnotationProjectionInvalidation {
	readonly operationCorrelationId: string;
	readonly queryKind: 'content' | 'control';
	readonly sessionIds: readonly string[];
	readonly sourceGeneration: number;
	readonly worktreeId: string;
}

export class BridgeCommWorkerAnnotationProjectionQueryController {
	readonly #onCatalog: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps['onCatalog'];
	readonly #onConvergence: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps['onConvergence'];
	readonly #onSourceAuthorityStale: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps['onSourceAuthorityStale'];
	readonly #surface: BridgeCommWorkerAnnotationSurface;
	readonly #transport: BridgeCommWorkerAnnotationProjectionTransport;
	readonly #telemetryClient: WorktreeAnnotationLifecycleTelemetryRecorder | undefined;
	#active = false;
	readonly #metadataApplication = new BridgeCommWorkerAnnotationMetadataApplication();
	#controlReady = false;
	#automaticQueryRetryConsumed = false;
	#automaticSubscriptionReopenConsumed = false;
	#abortController: AbortController | null = null;
	#disposed = false;
	#invalidation: AnnotationProjectionInvalidation | null = null;
	#invalidationGeneration = 0;
	#lastAttemptedGeneration = 0;
	#queryLoop: Promise<void> | null = null;
	#reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null = null;
	readonly #queryAttempts = new Set<Promise<void>>();
	#scheduledQueryStart: Promise<void> | null = null;
	#scheduledSubscriptionReopen: Promise<void> | null = null;
	#sessionIds: readonly string[] = [];
	#sourceGeneration: number | null = null;
	#stageAttemptOperationCorrelationId: string | null = null;
	#nextStageAttempt = 0;
	#subscription: AnnotationMetadataSubscription | null = null;

	constructor(props: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps) {
		this.#onCatalog = props.onCatalog;
		this.#onConvergence = props.onConvergence;
		this.#onSourceAuthorityStale = props.onSourceAuthorityStale;
		this.#surface = props.surface;
		this.#transport = props.transport;
		this.#telemetryClient = props.telemetryClient;
	}

	ensureSubscription(): void {
		if (this.#disposed || this.#subscription !== null) return;
		let subscription: AnnotationMetadataSubscription;
		try {
			subscription = this.#transport.subscribe(this.#surface);
		} catch (error) {
			this.#handleSubscriptionFailure(error);
			return;
		}
		this.#subscription = subscription;
		void this.#consumeSubscription(subscription).catch((error: unknown): void => {
			if (this.#subscription !== subscription || this.#disposed) return;
			this.#handleSubscriptionFailure(error);
		});
	}

	setDemand(demand: BridgeCommWorkerAnnotationProjectionDemand): void {
		if (this.#disposed) return;
		const previousSessionSignature = JSON.stringify(this.#sessionIds);
		this.#sessionIds = [...new Set(demand.sessionIds)].toSorted();
		const sessionDemandChanged = JSON.stringify(this.#sessionIds) !== previousSessionSignature;
		const previousSourceGeneration = this.#sourceGeneration;
		const previousReviewPublicationIdentity = JSON.stringify(this.#reviewPublicationIdentity);
		this.#sourceGeneration = demand.sourceGeneration;
		this.#reviewPublicationIdentity = demand.reviewPublicationIdentity ?? null;
		const reviewIdentityChanged =
			previousReviewPublicationIdentity !==
			JSON.stringify(demand.reviewPublicationIdentity ?? null);
		const nextActive =
			demand.active &&
			demand.sourceGeneration !== null &&
			(this.#surface === 'file' || (demand.reviewPublicationIdentity ?? null) !== null);
		const becameInactive = this.#active && !nextActive;
		const becameActive = !this.#active && nextActive;
		this.#active = nextActive;
		if (becameInactive) {
			this.#abortController?.abort();
			return;
		}
		const presentationAuthorityChanged =
			previousSourceGeneration !== demand.sourceGeneration || reviewIdentityChanged;
		if (nextActive && (becameActive || presentationAuthorityChanged)) {
			if (this.#invalidation?.queryKind === 'content') {
				this.#invalidation = { ...this.#invalidation, sessionIds: this.#sessionIds };
			}
			this.#automaticQueryRetryConsumed = false;
			this.#automaticSubscriptionReopenConsumed = false;
			this.#invalidationGeneration += 1;
			this.#abortController?.abort();
		}
		if (
			nextActive &&
			sessionDemandChanged &&
			!becameActive &&
			!presentationAuthorityChanged &&
			this.#invalidation !== null
		) {
			if (this.#controlReady) {
				this.#admitProjectionInvalidation({
					...this.#invalidation,
					queryKind: 'content',
					sessionIds: this.#sessionIds,
				});
			} else if (this.#invalidation.queryKind === 'content') {
				this.#invalidation = { ...this.#invalidation, sessionIds: this.#sessionIds };
				this.#invalidationGeneration += 1;
				this.#abortController?.abort();
			}
		}
		if (nextActive && this.#subscription === null) this.ensureSubscription();
		if (becameActive || this.#invalidationGeneration > this.#lastAttemptedGeneration) {
			this.#scheduleQueryLoop();
		}
	}

	retry(): void {
		if (this.#disposed) return;
		this.#automaticQueryRetryConsumed = false;
		this.#automaticSubscriptionReopenConsumed = false;
		if (this.#active && this.#subscription === null) this.ensureSubscription();
		if (this.#invalidation === null) return;
		this.#invalidationGeneration += 1;
		this.#abortController?.abort();
		this.#scheduleQueryLoop();
	}

	sourceUnavailable(error: unknown): void {
		if (this.#disposed || !this.#active) return;
		this.#controlReady = false;
		this.#invalidationGeneration += 1;
		this.#lastAttemptedGeneration = this.#invalidationGeneration;
		this.#abortController?.abort();
		this.#onConvergence({
			operationCorrelationId: this.#invalidation?.operationCorrelationId ?? null,
			state: { error, kind: 'unavailable' },
			surface: this.#surface,
		});
	}

	async dispose(): Promise<void> {
		if (this.#disposed) return;
		this.#disposed = true;
		this.#metadataApplication.retireAuthority();
		this.#invalidationGeneration += 1;
		this.#abortController?.abort();
		const subscription = this.#subscription;
		this.#subscription = null;
		await Promise.allSettled([
			...(subscription === null ? [] : [subscription.cancel()]),
			...(this.#scheduledQueryStart === null ? [] : [this.#scheduledQueryStart]),
			...(this.#scheduledSubscriptionReopen === null ? [] : [this.#scheduledSubscriptionReopen]),
			...this.#queryAttempts,
		]);
	}

	async waitForIdle(): Promise<void> {
		await Promise.resolve();
		await Promise.resolve();
		while (
			this.#scheduledQueryStart !== null ||
			this.#scheduledSubscriptionReopen !== null ||
			this.#queryAttempts.size > 0
		) {
			if (this.#scheduledSubscriptionReopen !== null) {
				// eslint-disable-next-line no-await-in-loop -- Reopen is one bounded task boundary.
				await this.#scheduledSubscriptionReopen;
			}
			if (this.#scheduledQueryStart !== null) {
				// eslint-disable-next-line no-await-in-loop -- The scheduled start coalesces current notification facts.
				await this.#scheduledQueryStart;
			}
			// eslint-disable-next-line no-await-in-loop -- Replacement attempts may settle and schedule one newer attempt.
			await Promise.allSettled(this.#queryAttempts);
		}
	}

	async #consumeSubscription(subscription: AnnotationMetadataSubscription): Promise<void> {
		for await (const frame of subscription.events) {
			if (this.#disposed || this.#subscription !== subscription) return;
			const event = bridgeProductWorktreeAnnotationEventSchema.parse(frame.data);
			if (frame.operationCorrelationId === null) {
				throw new Error('Annotation metadata event requires lifecycle correlation.');
			}
			this.#recordLifecycle(
				frame.operationCorrelationId,
				'annotation_invalidation_received',
				'success',
				event.authority.applicationSourceGeneration,
			);
			this.#automaticQueryRetryConsumed = false;
			this.#automaticSubscriptionReopenConsumed = false;
			const action = this.#metadataApplication.accept({ ...frame, data: event }, this.#sessionIds);
			switch (action.kind) {
				case 'catalog':
					this.#onCatalog({
						catalog: action.catalog,
						operationCorrelationId: frame.operationCorrelationId,
						surface: this.#surface,
					});
					this.#controlReady = false;
					this.#admitProjectionInvalidation({
						operationCorrelationId: frame.operationCorrelationId,
						queryKind: 'control',
						sessionIds: [],
						sourceGeneration: event.authority.applicationSourceGeneration,
						worktreeId: event.authority.worktreeId,
					});
					break;
				case 'control':
					this.#controlReady = false;
					this.#admitProjectionInvalidation({
						operationCorrelationId: frame.operationCorrelationId,
						queryKind: 'control',
						sessionIds: [],
						sourceGeneration: event.authority.applicationSourceGeneration,
						worktreeId: event.authority.worktreeId,
					});
					break;
				case 'content':
					this.#admitProjectionInvalidation({
						operationCorrelationId: frame.operationCorrelationId,
						queryKind: 'content',
						sessionIds: this.#sessionIds,
						sourceGeneration: event.authority.applicationSourceGeneration,
						worktreeId: event.authority.worktreeId,
					});
					break;
				case 'none':
					break;
			}
		}
		if (!this.#disposed && this.#subscription === subscription) {
			throw new Error('Annotation projection notification subscription ended unexpectedly.');
		}
	}

	#admitProjectionInvalidation(invalidation: AnnotationProjectionInvalidation): void {
		this.#invalidation = invalidation;
		this.#invalidationGeneration += 1;
		this.#abortController?.abort();
		this.#scheduleQueryLoop();
	}

	#handleSubscriptionFailure(error: unknown): void {
		this.#subscription = null;
		this.#controlReady = false;
		this.#metadataApplication.retireAuthority();
		this.#onConvergence({
			operationCorrelationId: this.#invalidation?.operationCorrelationId ?? null,
			state: { error, kind: 'unavailable' },
			surface: this.#surface,
		});
		if (
			this.#disposed ||
			!this.#active ||
			this.#automaticSubscriptionReopenConsumed ||
			this.#scheduledSubscriptionReopen !== null
		) {
			return;
		}
		this.#automaticSubscriptionReopenConsumed = true;
		const scheduledReopen = scheduleBridgeCommWorkerTaskBoundary((): void => {
			if (this.#scheduledSubscriptionReopen !== scheduledReopen) return;
			this.#scheduledSubscriptionReopen = null;
			this.ensureSubscription();
		});
		this.#scheduledSubscriptionReopen = scheduledReopen;
	}

	#scheduleQueryLoop(): void {
		if (this.#scheduledQueryStart !== null) return;
		const scheduledStart = scheduleBridgeCommWorkerTaskBoundary((): void => {
			if (this.#scheduledQueryStart !== scheduledStart) return;
			this.#scheduledQueryStart = null;
			this.#startQueryAttempt();
		});
		this.#scheduledQueryStart = scheduledStart;
	}

	#startQueryAttempt(): void {
		if (
			!this.#active ||
			this.#disposed ||
			this.#invalidation === null ||
			this.#invalidationGeneration <= this.#lastAttemptedGeneration
		) {
			return;
		}
		const attemptGeneration = this.#invalidationGeneration;
		const invalidation = this.#invalidation;
		const sourceGeneration = this.#sourceGeneration;
		if (sourceGeneration === null) return;
		const reviewPublicationIdentity = this.#reviewPublicationIdentity;
		const stageAttempt = this.#claimStageAttempt(invalidation.operationCorrelationId);
		this.#lastAttemptedGeneration = attemptGeneration;
		this.#abortController?.abort();
		const abortController = new AbortController();
		this.#abortController = abortController;
		this.#onConvergence({
			operationCorrelationId: invalidation.operationCorrelationId,
			state: { kind: 'refreshing' },
			surface: this.#surface,
		});
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'projection_convergence_started',
			'started',
			sourceGeneration,
			stageAttempt,
		);
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'projection_query_started',
			'started',
			sourceGeneration,
			stageAttempt,
		);
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'worker_application_started',
			'started',
			sourceGeneration,
			stageAttempt,
		);
		const queryLoop = this.#runQueryAttempt(
			attemptGeneration,
			invalidation,
			sourceGeneration,
			reviewPublicationIdentity,
			stageAttempt,
			abortController,
		).finally((): void => {
			this.#queryAttempts.delete(queryLoop);
			if (this.#queryLoop !== queryLoop) return;
			this.#queryLoop = null;
			if (this.#abortController === abortController) this.#abortController = null;
			if (
				this.#active &&
				!this.#disposed &&
				this.#invalidationGeneration > this.#lastAttemptedGeneration
			) {
				this.#scheduleQueryLoop();
			}
		});
		this.#queryLoop = queryLoop;
		this.#queryAttempts.add(queryLoop);
	}

	async #runQueryAttempt(
		attemptGeneration: number,
		invalidation: AnnotationProjectionInvalidation,
		sourceGeneration: number,
		reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null,
		stageAttempt: number,
		abortController: AbortController,
	): Promise<void> {
		let terminalRecorded = false;
		try {
			const fetchResult = await this.#fetchSnapshot(
				invalidation,
				sourceGeneration,
				reviewPublicationIdentity,
				stageAttempt,
				abortController.signal,
			);
			if (
				this.#disposed ||
				!this.#active ||
				abortController.signal.aborted ||
				attemptGeneration !== this.#invalidationGeneration
			) {
				this.#recordAttemptTerminal(invalidation, sourceGeneration, stageAttempt, 'cancelled');
				terminalRecorded = true;
				return;
			}
			if (fetchResult.kind === 'source_stale') {
				this.#recordAttemptTerminal(invalidation, sourceGeneration, stageAttempt, 'stale');
				terminalRecorded = true;
				this.#onSourceAuthorityStale({
					currentSourceGeneration: fetchResult.currentSourceGeneration,
					requestedSourceGeneration: sourceGeneration,
					surface: this.#surface,
				});
				return;
			}
			this.#onConvergence({
				operationCorrelationId: invalidation.operationCorrelationId,
				state: {
					contentSessionIds: invalidation.sessionIds,
					kind: 'ready',
					snapshot: fetchResult.snapshot,
				},
				surface: this.#surface,
			});
			this.#recordAttemptTerminal(invalidation, sourceGeneration, stageAttempt, 'success');
			terminalRecorded = true;
			this.#automaticQueryRetryConsumed = false;
			if (invalidation.queryKind === 'control') {
				this.#controlReady = true;
				if (this.#sessionIds.length > 0) {
					this.#invalidation = {
						...invalidation,
						queryKind: 'content',
						sessionIds: this.#sessionIds,
					};
					this.#invalidationGeneration += 1;
				}
			}
		} catch (error) {
			const result = abortController.signal.aborted ? 'cancelled' : 'failure';
			this.#recordAttemptTerminal(invalidation, sourceGeneration, stageAttempt, result);
			terminalRecorded = true;
			if (
				!this.#disposed &&
				this.#active &&
				!abortController.signal.aborted &&
				attemptGeneration === this.#invalidationGeneration
			) {
				if (isRetryableProjectionAttempt(error) && !this.#automaticQueryRetryConsumed) {
					this.#automaticQueryRetryConsumed = true;
					this.#invalidationGeneration += 1;
					return;
				}
				this.#onConvergence({
					operationCorrelationId: invalidation.operationCorrelationId,
					state: { error, kind: 'unavailable' },
					surface: this.#surface,
				});
			}
		} finally {
			if (!terminalRecorded) {
				this.#recordAttemptTerminal(invalidation, sourceGeneration, stageAttempt, 'cancelled');
			}
		}
	}

	async #fetchSnapshot(
		invalidation: AnnotationProjectionInvalidation,
		sourceGeneration: number,
		reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null,
		stageAttempt: number,
		signal: AbortSignal,
	): Promise<
		| { readonly kind: 'content'; readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot }
		| Extract<BridgeProductAnnotationProjectionQueryResult, { readonly kind: 'source_stale' }>
	> {
		const decoder = new BridgeCommWorkerAnnotationProjectionDecoder();
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'content_transfer_started',
			'started',
			sourceGeneration,
			stageAttempt,
		);
		let cursor: string | null = null;
		let expectedPage: BridgeProductAnnotationProjectionPageContract | null = null;
		let previousPageOrdinal: number | null = null;
		while (true) {
			// eslint-disable-next-line no-await-in-loop -- Continuation cursors are single-use and strictly ordered.
			const result = await this.#queryProjection({
				cursor,
				operationCorrelationId: invalidation.operationCorrelationId,
				reviewPublicationIdentity,
				sessionIds: [...invalidation.sessionIds],
				signal,
				sourceGeneration,
			});
			const parsedResult = bridgeProductAnnotationProjectionQueryResultSchema.parse(result);
			if (parsedResult.kind === 'source_stale') return parsedResult;
			const descriptor = parsedResult.descriptor;
			validatePageContract({
				descriptor,
				expectedPage,
				previousPageOrdinal,
				requestedCursor: cursor,
				requestedOperationCorrelationId: invalidation.operationCorrelationId,
				requestedSourceGeneration: sourceGeneration,
				requestedSurface: this.#surface,
			});
			expectedPage ??= descriptor.page;
			previousPageOrdinal = descriptor.page.pageOrdinal;
			// eslint-disable-next-line no-await-in-loop -- Each claimed page must complete before its continuation query.
			let pageBytes: Uint8Array;
			try {
				pageBytes = await openAnnotationProjectionPage({
					descriptor,
					openContent: this.#transport.openContent,
					signal,
				});
			} catch (error) {
				this.#recordLifecycle(
					invalidation.operationCorrelationId,
					'content_transfer_terminal',
					'failure',
					sourceGeneration,
					stageAttempt,
				);
				throw error;
			}
			decoder.acceptPage(pageBytes, descriptor.page.pageOrdinal);
			if (descriptor.page.isLastPage) break;
			cursor = descriptor.page.nextCursor;
		}
		if (expectedPage === null) throw new Error('Annotation projection returned no pages.');
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'content_transfer_terminal',
			'success',
			sourceGeneration,
			stageAttempt,
		);
		try {
			this.#recordLifecycle(
				invalidation.operationCorrelationId,
				'projection_validation_started',
				'started',
				sourceGeneration,
				stageAttempt,
			);
			const decodedProjection = decoder.finish();
			const snapshot = decodedProjection.snapshot;
			if (
				!this.#metadataApplication.projectionMeetsCurrentness(snapshot, invalidation.sessionIds)
			) {
				throw new Error(
					'Annotation rich projection did not meet current catalog session authority.',
				);
			}
			if (
				expectedPage.operationCorrelationId !== invalidation.operationCorrelationId ||
				snapshot.projectionRevision !== expectedPage.projectionRevision ||
				snapshot.sourceGeneration !== expectedPage.sourceGeneration ||
				snapshot.worktreeId !== invalidation.worktreeId ||
				snapshot.expectedSessionCount !== expectedPage.expectedSessionCount ||
				snapshot.expectedThreadCount !== expectedPage.expectedThreadCount ||
				snapshot.expectedMessageCount !== expectedPage.expectedMessageCount
			) {
				throw new Error('Annotation projection header does not match its page contract.');
			}
			if (decodedProjection.aggregateSha256 !== expectedPage.aggregateSha256) {
				throw new Error(
					'Annotation projection aggregate SHA-256 does not match its page contract.',
				);
			}
			this.#recordLifecycle(
				invalidation.operationCorrelationId,
				'projection_validation_terminal',
				'success',
				sourceGeneration,
				stageAttempt,
			);
			return { kind: 'content', snapshot };
		} catch (error) {
			this.#recordLifecycle(
				invalidation.operationCorrelationId,
				'projection_validation_terminal',
				'failure',
				sourceGeneration,
				stageAttempt,
			);
			throw error;
		}
	}

	#recordAttemptTerminal(
		invalidation: AnnotationProjectionInvalidation,
		sourceGeneration: number,
		stageAttempt: number,
		result: 'cancelled' | 'failure' | 'stale' | 'success',
	): void {
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'projection_query_terminal',
			result,
			sourceGeneration,
			stageAttempt,
		);
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'projection_convergence_terminal',
			result,
			sourceGeneration,
			stageAttempt,
		);
		this.#recordLifecycle(
			invalidation.operationCorrelationId,
			'worker_application_terminal',
			result,
			sourceGeneration,
			stageAttempt,
		);
	}

	#recordLifecycle(
		operationCorrelationId: string,
		phase: Parameters<typeof recordWorktreeAnnotationLifecycleTelemetry>[0]['phase'],
		result: Parameters<typeof recordWorktreeAnnotationLifecycleTelemetry>[0]['result'],
		sourceGeneration: number,
		stageAttempt = 0,
	): void {
		recordWorktreeAnnotationLifecycleTelemetry({
			operationCorrelationId,
			phase,
			recorder: this.#telemetryClient,
			result,
			sourceGeneration,
			stageAttempt,
			transport: 'worker',
			viewer: this.#surface,
		});
	}

	#claimStageAttempt(operationCorrelationId: string): number {
		if (this.#stageAttemptOperationCorrelationId !== operationCorrelationId) {
			this.#stageAttemptOperationCorrelationId = operationCorrelationId;
			this.#nextStageAttempt = 1;
			return 0;
		}
		const stageAttempt = this.#nextStageAttempt;
		this.#nextStageAttempt += 1;
		return stageAttempt;
	}

	#queryProjection(props: {
		readonly cursor: string | null;
		readonly operationCorrelationId: string;
		readonly reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity | null;
		readonly sessionIds: string[];
		readonly signal: AbortSignal;
		readonly sourceGeneration: number;
	}): Promise<unknown> {
		const requestBase = {
			cursor: props.cursor,
			operationCorrelationId: props.operationCorrelationId,
			sessionIds: props.sessionIds,
			sourceGeneration: props.sourceGeneration,
		};
		if (this.#surface === 'file') {
			return this.#transport.callProjection(
				'file',
				{ ...requestBase, surface: 'file' },
				props.signal,
			);
		}
		if (props.reviewPublicationIdentity === null) {
			return Promise.reject(
				new Error('Review annotation projection has no installed publication identity.'),
			);
		}
		return this.#transport.callProjection(
			'review',
			{
				...requestBase,
				reviewPublicationIdentity: props.reviewPublicationIdentity,
				surface: 'review',
			},
			props.signal,
		);
	}
}

function isRetryableProjectionAttempt(error: unknown): boolean {
	return error instanceof BridgeProductControlRequestError && error.retryable;
}

export function bridgeCommWorkerAnnotationProjectionTransport(
	productTransport: BridgeProductTransportSession,
): BridgeCommWorkerAnnotationProjectionTransport {
	return {
		callProjection: (surface, request, signal): Promise<unknown> =>
			surface === 'file'
				? productTransport.call('file.annotations.projection.query', request, { signal })
				: productTransport.call('review.annotations.projection.query', request, { signal }),
		openContent: (descriptor, signal) =>
			productTransport.openContent(descriptor, signal, descriptor.page.operationCorrelationId),
		subscribe: (surface) =>
			surface === 'file'
				? productTransport.subscribe(bridgeProductFileAnnotationMetadataApplicationProtocol, {})
				: productTransport.subscribe(bridgeProductReviewAnnotationMetadataApplicationProtocol, {}),
	};
}

async function openAnnotationProjectionPage(props: {
	readonly descriptor: BridgeProductAnnotationProjectionContentDescriptor;
	readonly openContent: BridgeCommWorkerAnnotationProjectionTransport['openContent'];
	readonly signal: AbortSignal;
}): Promise<Uint8Array<ArrayBuffer>> {
	const contentStream: BridgeProductContentStream<'annotation.projection'> = props.openContent(
		props.descriptor,
		props.signal,
	);
	const drain = (async (): Promise<void> => {
		for await (const frame of contentStream.frames) void frame;
	})();
	const [, terminal] = await Promise.all([drain, contentStream.terminal]);
	if (terminal.kind !== 'complete') {
		throw new Error('Annotation projection content did not complete.');
	}
	if (
		terminal.descriptorId !== props.descriptor.descriptorId ||
		terminal.observedByteLength !== props.descriptor.maximumBytes ||
		terminal.bytes.byteLength !== props.descriptor.maximumBytes ||
		!terminal.endOfSource
	) {
		throw new Error('Annotation projection content terminal does not match its descriptor.');
	}
	return new Uint8Array(terminal.bytes);
}

function validatePageContract(props: {
	readonly descriptor: BridgeProductAnnotationProjectionContentDescriptor;
	readonly expectedPage: BridgeProductAnnotationProjectionPageContract | null;
	readonly previousPageOrdinal: number | null;
	readonly requestedCursor: string | null;
	readonly requestedOperationCorrelationId: string;
	readonly requestedSourceGeneration: number;
	readonly requestedSurface: BridgeCommWorkerAnnotationSurface;
}): void {
	const expectedOrdinal = props.previousPageOrdinal === null ? 0 : props.previousPageOrdinal + 1;
	if (
		props.descriptor.surface !== props.requestedSurface ||
		props.descriptor.page.operationCorrelationId !== props.requestedOperationCorrelationId ||
		props.descriptor.page.sourceGeneration !== props.requestedSourceGeneration ||
		props.descriptor.page.pageOrdinal !== expectedOrdinal ||
		(props.requestedCursor === null) !== (props.descriptor.page.pageOrdinal === 0)
	) {
		throw new Error('Annotation projection page does not match its query authority or order.');
	}
	if (props.expectedPage === null) return;
	for (const field of [
		'aggregateSha256',
		'expectedMessageCount',
		'expectedPageCount',
		'expectedSessionCount',
		'expectedThreadCount',
		'operationCorrelationId',
		'projectionRevision',
		'snapshotId',
		'sourceGeneration',
	] as const) {
		if (props.descriptor.page[field] !== props.expectedPage[field]) {
			throw new Error(`Annotation projection page changed ${field} within one snapshot.`);
		}
	}
}
