import {
	BridgeCommWorkerAnnotationProjectionDecoder,
	type BridgeWorkerAnnotationProjectionSnapshot,
} from './bridge-comm-worker-annotation-projection-decoder.js';
import { scheduleBridgeCommWorkerTaskBoundary } from './bridge-comm-worker-task-boundary.js';
import { BridgeProductControlRequestError } from './bridge-product-session-authority.js';
import type {
	BridgeProductContentStream,
	BridgeProductSubscription,
} from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import { bridgeProductWorktreeAnnotationEventSchema } from './bridge-product-worktree-annotation-contracts.js';
import {
	bridgeProductAnnotationProjectionQueryResultSchema,
	type BridgeProductAnnotationProjectionContentDescriptor,
	type BridgeProductAnnotationProjectionPageContract,
	type BridgeProductAnnotationProjectionQueryRequest,
	type BridgeProductAnnotationProjectionQueryResult,
} from './bridge-product-worktree-annotation-projection-query-contracts.js';

export type BridgeCommWorkerAnnotationSurface = 'file' | 'review';

export interface BridgeCommWorkerAnnotationProjectionDemand {
	readonly active: boolean;
	readonly sessionIds: readonly string[];
	readonly sourceGeneration: number | null;
}

export interface BridgeCommWorkerAnnotationProjectionPublication {
	readonly state:
		| { readonly error: unknown; readonly kind: 'unavailable' }
		| { readonly kind: 'ready'; readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot }
		| { readonly kind: 'refreshing' };
	readonly surface: BridgeCommWorkerAnnotationSurface;
}

export interface BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication {
	readonly currentSourceGeneration: number;
	readonly requestedSourceGeneration: number;
	readonly surface: BridgeCommWorkerAnnotationSurface;
}

interface CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps {
	readonly onConvergence: (publication: BridgeCommWorkerAnnotationProjectionPublication) => void;
	readonly onSourceAuthorityStale: (
		publication: BridgeCommWorkerAnnotationProjectionSourceAuthorityStalePublication,
	) => void;
	readonly surface: BridgeCommWorkerAnnotationSurface;
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
	) => BridgeProductSubscription<'file.annotations' | 'review.annotations'>;
}

interface AnnotationProjectionInvalidation {
	readonly sourceGeneration: number;
	readonly worktreeId: string;
}

export class BridgeCommWorkerAnnotationProjectionQueryController {
	readonly #onConvergence: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps['onConvergence'];
	readonly #onSourceAuthorityStale: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps['onSourceAuthorityStale'];
	readonly #surface: BridgeCommWorkerAnnotationSurface;
	readonly #transport: BridgeCommWorkerAnnotationProjectionTransport;
	#active = false;
	#automaticQueryRetryConsumed = false;
	#automaticSubscriptionReopenConsumed = false;
	#abortController: AbortController | null = null;
	#disposed = false;
	#invalidation: AnnotationProjectionInvalidation | null = null;
	#invalidationGeneration = 0;
	#lastAttemptedGeneration = 0;
	#queryLoop: Promise<void> | null = null;
	readonly #queryAttempts = new Set<Promise<void>>();
	#scheduledQueryStart: Promise<void> | null = null;
	#scheduledSubscriptionReopen: Promise<void> | null = null;
	#sessionIds: readonly string[] = [];
	#sourceGeneration: number | null = null;
	#subscription: BridgeProductSubscription<'file.annotations' | 'review.annotations'> | null = null;

	constructor(props: CreateBridgeCommWorkerAnnotationProjectionQueryControllerProps) {
		this.#onConvergence = props.onConvergence;
		this.#onSourceAuthorityStale = props.onSourceAuthorityStale;
		this.#surface = props.surface;
		this.#transport = props.transport;
	}

	ensureSubscription(): void {
		if (this.#disposed || this.#subscription !== null) return;
		let subscription: BridgeProductSubscription<'file.annotations' | 'review.annotations'>;
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
		this.#sourceGeneration = demand.sourceGeneration;
		const nextActive = demand.active && demand.sourceGeneration !== null;
		const becameInactive = this.#active && !nextActive;
		const becameActive = !this.#active && nextActive;
		this.#active = nextActive;
		if (becameInactive) {
			this.#abortController?.abort();
			return;
		}
		if (
			nextActive &&
			(becameActive || previousSourceGeneration !== demand.sourceGeneration || sessionDemandChanged)
		) {
			this.#automaticQueryRetryConsumed = false;
			this.#automaticSubscriptionReopenConsumed = false;
			this.#invalidationGeneration += 1;
			this.#abortController?.abort();
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
		this.#invalidationGeneration += 1;
		this.#lastAttemptedGeneration = this.#invalidationGeneration;
		this.#abortController?.abort();
		this.#onConvergence({ state: { error, kind: 'unavailable' }, surface: this.#surface });
	}

	async dispose(): Promise<void> {
		if (this.#disposed) return;
		this.#disposed = true;
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

	async #consumeSubscription(
		subscription: BridgeProductSubscription<'file.annotations' | 'review.annotations'>,
	): Promise<void> {
		for await (const unknownEvent of subscription.events) {
			if (this.#disposed || this.#subscription !== subscription) return;
			const event = bridgeProductWorktreeAnnotationEventSchema.parse(unknownEvent);
			this.#automaticQueryRetryConsumed = false;
			this.#automaticSubscriptionReopenConsumed = false;
			this.#invalidation = {
				sourceGeneration: event.sourceGeneration,
				worktreeId: event.worktreeId,
			};
			this.#invalidationGeneration += 1;
			this.#abortController?.abort();
			this.#scheduleQueryLoop();
		}
		if (!this.#disposed && this.#subscription === subscription) {
			throw new Error('Annotation projection notification subscription ended unexpectedly.');
		}
	}

	#handleSubscriptionFailure(error: unknown): void {
		this.#subscription = null;
		this.#onConvergence({ state: { error, kind: 'unavailable' }, surface: this.#surface });
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
		this.#lastAttemptedGeneration = attemptGeneration;
		this.#abortController?.abort();
		const abortController = new AbortController();
		this.#abortController = abortController;
		this.#onConvergence({ state: { kind: 'refreshing' }, surface: this.#surface });
		const queryLoop = this.#runQueryAttempt(
			attemptGeneration,
			invalidation,
			sourceGeneration,
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
		abortController: AbortController,
	): Promise<void> {
		try {
			const fetchResult = await this.#fetchSnapshot(
				invalidation,
				sourceGeneration,
				abortController.signal,
			);
			if (
				this.#disposed ||
				!this.#active ||
				abortController.signal.aborted ||
				attemptGeneration !== this.#invalidationGeneration
			) {
				return;
			}
			if (fetchResult.kind === 'source_stale') {
				this.#onSourceAuthorityStale({
					currentSourceGeneration: fetchResult.currentSourceGeneration,
					requestedSourceGeneration: sourceGeneration,
					surface: this.#surface,
				});
				return;
			}
			this.#onConvergence({
				state: { kind: 'ready', snapshot: fetchResult.snapshot },
				surface: this.#surface,
			});
			this.#automaticQueryRetryConsumed = false;
		} catch (error) {
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
					state: { error, kind: 'unavailable' },
					surface: this.#surface,
				});
			}
		}
	}

	async #fetchSnapshot(
		invalidation: AnnotationProjectionInvalidation,
		sourceGeneration: number,
		signal: AbortSignal,
	): Promise<
		| { readonly kind: 'content'; readonly snapshot: BridgeWorkerAnnotationProjectionSnapshot }
		| Extract<BridgeProductAnnotationProjectionQueryResult, { readonly kind: 'source_stale' }>
	> {
		const decoder = new BridgeCommWorkerAnnotationProjectionDecoder();
		let cursor: string | null = null;
		let expectedPage: BridgeProductAnnotationProjectionPageContract | null = null;
		let previousPageOrdinal: number | null = null;
		while (true) {
			// eslint-disable-next-line no-await-in-loop -- Continuation cursors are single-use and strictly ordered.
			const result = await this.#queryProjection(
				{
					cursor,
					sessionIds: [...this.#sessionIds],
					sourceGeneration,
					surface: this.#surface,
				},
				signal,
			);
			const parsedResult = bridgeProductAnnotationProjectionQueryResultSchema.parse(result);
			if (parsedResult.kind === 'source_stale') return parsedResult;
			const descriptor = parsedResult.descriptor;
			validatePageContract({
				descriptor,
				expectedPage,
				previousPageOrdinal,
				requestedCursor: cursor,
				requestedSourceGeneration: sourceGeneration,
				requestedSurface: this.#surface,
			});
			expectedPage ??= descriptor.page;
			previousPageOrdinal = descriptor.page.pageOrdinal;
			// eslint-disable-next-line no-await-in-loop -- Each claimed page must complete before its continuation query.
			const pageBytes = await openAnnotationProjectionPage({
				descriptor,
				openContent: this.#transport.openContent,
				signal,
			});
			decoder.acceptPage(pageBytes, descriptor.page.pageOrdinal);
			if (descriptor.page.isLastPage) break;
			cursor = descriptor.page.nextCursor;
		}
		if (expectedPage === null) throw new Error('Annotation projection returned no pages.');
		const decodedProjection = decoder.finish();
		const snapshot = decodedProjection.snapshot;
		if (
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
			throw new Error('Annotation projection aggregate SHA-256 does not match its page contract.');
		}
		return { kind: 'content', snapshot };
	}

	#queryProjection(
		request: {
			readonly cursor: string | null;
			readonly sessionIds: string[];
			readonly sourceGeneration: number;
			readonly surface: BridgeCommWorkerAnnotationSurface;
		},
		signal: AbortSignal,
	): Promise<unknown> {
		return this.#transport.callProjection(
			this.#surface,
			{ ...request, surface: this.#surface },
			signal,
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
				? productTransport.call(
						'file.annotations.projection.query',
						{ ...request, surface: 'file' },
						{ signal },
					)
				: productTransport.call(
						'review.annotations.projection.query',
						{ ...request, surface: 'review' },
						{ signal },
					),
		openContent: (descriptor, signal) => productTransport.openContent(descriptor, signal),
		subscribe: (surface) =>
			surface === 'file'
				? productTransport.subscribe('file.annotations', {})
				: productTransport.subscribe('review.annotations', {}),
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
	readonly requestedSourceGeneration: number;
	readonly requestedSurface: BridgeCommWorkerAnnotationSurface;
}): void {
	const expectedOrdinal = props.previousPageOrdinal === null ? 0 : props.previousPageOrdinal + 1;
	if (
		props.descriptor.surface !== props.requestedSurface ||
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
		'projectionRevision',
		'snapshotId',
		'sourceGeneration',
	] as const) {
		if (props.descriptor.page[field] !== props.expectedPage[field]) {
			throw new Error(`Annotation projection page changed ${field} within one snapshot.`);
		}
	}
}
