import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

type AnnotationSurface = 'file' | 'review';
type AnnotationSubscriptionKind = 'file.annotations' | 'review.annotations';
type AnnotationSubscription = BridgeProductSubscription<AnnotationSubscriptionKind>;
type AnnotationEvent = BridgeProductSubscriptionEvent<AnnotationSubscriptionKind>;

export type AnnotationProjectionResyncInvalidationReason =
	| 'commandRejected'
	| 'concurrentReplacement'
	| 'timeout';

export interface AnnotationProjectionResyncTask {
	readonly completion: Promise<void>;
	readonly controllerResyncGeneration: number;
	readonly oldSubscriptionId: string;
	readonly requestId: string;
	readonly surface: AnnotationSurface;
	readonly invalidate: (reason: AnnotationProjectionResyncInvalidationReason) => void;
}

interface BeginAnnotationProjectionResyncProps {
	readonly requestId: string;
	readonly subscriptionId: string;
	readonly surface: AnnotationSurface;
}

interface CreateBridgeCommWorkerAnnotationSubscriptionControllerProps {
	readonly isCurrentController: () => boolean;
	readonly onEvent: (
		event: AnnotationEvent,
		subscriptionId: string,
		surface: AnnotationSurface,
	) => void;
	readonly productTransport: BridgeProductTransportSession;
}

export class BridgeCommWorkerAnnotationSubscriptionController {
	readonly #isCurrentController: () => boolean;
	readonly #onEvent: CreateBridgeCommWorkerAnnotationSubscriptionControllerProps['onEvent'];
	readonly #productTransport: BridgeProductTransportSession;
	readonly #subscriptionBySurface: Record<AnnotationSurface, AnnotationSubscription | null> = {
		file: null,
		review: null,
	};
	readonly #currentResyncTaskBySurface: Record<
		AnnotationSurface,
		AnnotationProjectionResyncTaskOwner | null
	> = { file: null, review: null };
	readonly #provisionalBySurface: Record<
		AnnotationSurface,
		{
			readonly subscription: AnnotationSubscription;
			readonly task: AnnotationProjectionResyncTaskOwner;
		} | null
	> = { file: null, review: null };
	readonly #resyncGenerationBySurface: Record<AnnotationSurface, number> = { file: 0, review: 0 };

	constructor(props: CreateBridgeCommWorkerAnnotationSubscriptionControllerProps) {
		this.#isCurrentController = props.isCurrentController;
		this.#onEvent = props.onEvent;
		this.#productTransport = props.productTransport;
	}

	ensureSubscriptions(): void {
		for (const surface of ['file', 'review'] as const) {
			if (this.#subscriptionBySurface[surface] !== null) continue;
			const subscription = this.#subscribe(surface);
			this.#subscriptionBySurface[surface] = subscription;
			void this.#consumeActiveSubscription(subscription, surface).catch((): void => {});
		}
	}

	beginResync(props: BeginAnnotationProjectionResyncProps): AnnotationProjectionResyncTask {
		const oldSubscription = this.#subscriptionBySurface[props.surface];
		if (
			!this.#isCurrentController() ||
			this.#currentResyncTaskBySurface[props.surface] !== null ||
			oldSubscription === null ||
			oldSubscription.subscriptionId !== props.subscriptionId
		) {
			return AnnotationProjectionResyncTaskOwner.rejected(props);
		}

		this.#resyncGenerationBySurface[props.surface] += 1;
		const task = new AnnotationProjectionResyncTaskOwner({
			controllerResyncGeneration: this.#resyncGenerationBySurface[props.surface],
			onInvalidate: (owner, reason): void => this.#invalidateTask(owner, reason),
			oldSubscriptionId: oldSubscription.subscriptionId,
			requestId: props.requestId,
			surface: props.surface,
		});
		this.#currentResyncTaskBySurface[props.surface] = task;
		this.#subscriptionBySurface[props.surface] = null;
		void this.#runResync(task, oldSubscription);
		return task;
	}

	invalidateCurrentResync(reason: AnnotationProjectionResyncInvalidationReason): void {
		this.#currentResyncTaskBySurface.file?.invalidate(reason);
		this.#currentResyncTaskBySurface.review?.invalidate(reason);
	}

	#taskIsCurrent(task: AnnotationProjectionResyncTaskOwner): boolean {
		return (
			this.#isCurrentController() &&
			this.#currentResyncTaskBySurface[task.surface] === task &&
			this.#resyncGenerationBySurface[task.surface] === task.controllerResyncGeneration
		);
	}

	#continueCurrentTask(task: AnnotationProjectionResyncTaskOwner): boolean {
		if (this.#taskIsCurrent(task)) return true;
		task.invalidate('concurrentReplacement');
		return false;
	}

	#invalidateTask(
		task: AnnotationProjectionResyncTaskOwner,
		reason: AnnotationProjectionResyncInvalidationReason,
	): void {
		if (this.#currentResyncTaskBySurface[task.surface] === task) {
			this.#currentResyncTaskBySurface[task.surface] = null;
			this.#resyncGenerationBySurface[task.surface] += 1;
		}
		const provisional = this.#provisionalBySurface[task.surface];
		if (provisional?.task === task) {
			this.#provisionalBySurface[task.surface] = null;
			void provisional.subscription.cancel().catch((): void => {});
		}
		task.rejectOnce(new Error(`Annotation projection resync invalidated: ${reason}.`));
	}

	async #runResync(
		task: AnnotationProjectionResyncTaskOwner,
		oldSubscription: AnnotationSubscription,
	): Promise<void> {
		try {
			await oldSubscription.cancel();
			if (!this.#continueCurrentTask(task)) return;
			const provisionalSubscription = this.#subscribe(task.surface);
			if (!this.#continueCurrentTask(task)) return;
			this.#provisionalBySurface[task.surface] = {
				subscription: provisionalSubscription,
				task,
			};
			const iterator = provisionalSubscription.events[Symbol.asyncIterator]();
			const firstResult = await iterator.next();
			if (!this.#continueCurrentTask(task)) return;
			if (firstResult.done || firstResult.value.eventKind !== 'projection.state') {
				this.#invalidateTask(task, 'commandRejected');
				return;
			}

			this.#subscriptionBySurface[task.surface] = provisionalSubscription;
			this.#onEvent(firstResult.value, provisionalSubscription.subscriptionId, task.surface);
			if (!this.#continueCurrentTask(task)) {
				this.#subscriptionBySurface[task.surface] = null;
				return;
			}
			this.#provisionalBySurface[task.surface] = null;
			this.#currentResyncTaskBySurface[task.surface] = null;
			task.resolveOnce();
			void this.#consumeActiveSubscription(provisionalSubscription, task.surface, iterator).catch(
				(): void => {},
			);
		} catch {
			if (this.#taskIsCurrent(task)) {
				this.#subscriptionBySurface[task.surface] = null;
				this.#invalidateTask(task, 'commandRejected');
			}
		}
	}

	async #consumeActiveSubscription(
		subscription: AnnotationSubscription,
		surface: AnnotationSurface,
		iterator: AsyncIterator<AnnotationEvent> = subscription.events[Symbol.asyncIterator](),
	): Promise<void> {
		try {
			while (true) {
				const result = await iterator.next();
				if (result.done) return;
				if (subscription !== this.#subscriptionBySurface[surface]) return;
				this.#onEvent(result.value, subscription.subscriptionId, surface);
			}
		} finally {
			if (subscription === this.#subscriptionBySurface[surface]) {
				this.#subscriptionBySurface[surface] = null;
			}
		}
	}

	#subscribe(surface: AnnotationSurface): AnnotationSubscription {
		const subscription =
			surface === 'file'
				? this.#productTransport.subscribe('file.annotations', {})
				: this.#productTransport.subscribe('review.annotations', {});
		const expectedKind: AnnotationSubscriptionKind =
			surface === 'file' ? 'file.annotations' : 'review.annotations';
		if (subscription.subscriptionKind !== expectedKind) {
			throw new Error('Annotation subscription crossed surfaces.');
		}
		return subscription;
	}
}

interface CreateAnnotationProjectionResyncTaskOwnerProps {
	readonly controllerResyncGeneration: number;
	readonly oldSubscriptionId: string;
	readonly onInvalidate: (
		task: AnnotationProjectionResyncTaskOwner,
		reason: AnnotationProjectionResyncInvalidationReason,
	) => void;
	readonly requestId: string;
	readonly surface: AnnotationSurface;
}

class AnnotationProjectionResyncTaskOwner implements AnnotationProjectionResyncTask {
	readonly completion: Promise<void>;
	readonly controllerResyncGeneration: number;
	readonly oldSubscriptionId: string;
	readonly requestId: string;
	readonly surface: AnnotationSurface;
	readonly #onInvalidate: CreateAnnotationProjectionResyncTaskOwnerProps['onInvalidate'];
	#rejectCompletion!: (error: Error) => void;
	#resolveCompletion!: () => void;
	#settled = false;

	constructor(props: CreateAnnotationProjectionResyncTaskOwnerProps) {
		this.controllerResyncGeneration = props.controllerResyncGeneration;
		this.oldSubscriptionId = props.oldSubscriptionId;
		this.requestId = props.requestId;
		this.surface = props.surface;
		this.#onInvalidate = props.onInvalidate;
		this.completion = new Promise<void>((resolve, reject): void => {
			this.#rejectCompletion = reject;
			this.#resolveCompletion = resolve;
		});
		void this.completion.catch((): void => {});
	}

	static rejected(props: BeginAnnotationProjectionResyncProps): AnnotationProjectionResyncTask {
		const completion = Promise.reject(new Error('Annotation projection resync request is stale.'));
		void completion.catch((): void => {});
		return {
			completion,
			controllerResyncGeneration: -1,
			invalidate: (): void => {},
			oldSubscriptionId: props.subscriptionId,
			requestId: props.requestId,
			surface: props.surface,
		};
	}

	invalidate(reason: AnnotationProjectionResyncInvalidationReason): void {
		if (this.#settled) return;
		this.#onInvalidate(this, reason);
	}

	rejectOnce(error: Error): void {
		if (this.#settled) return;
		this.#settled = true;
		this.#rejectCompletion(error);
	}

	resolveOnce(): void {
		if (this.#settled) return;
		this.#settled = true;
		this.#resolveCompletion();
	}
}
