import type { BridgeProductWorktreeAnnotationEvent } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';

type WorktreeAnnotationProjectionStateEvent = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'projection.state' }
>;
type WorktreeAnnotationMessageBatchEvent = Extract<
	BridgeProductWorktreeAnnotationEvent,
	{ readonly eventKind: 'message.batch' }
>;

export type WorktreeAnnotationCommandOutcome =
	WorktreeAnnotationProjectionStateEvent['payload']['commandOutcomes'][number];
export type WorktreeAnnotationOutputHistorySummary =
	WorktreeAnnotationProjectionStateEvent['payload']['outputHistory'][number];
export type WorktreeAnnotationSessionSummary =
	WorktreeAnnotationProjectionStateEvent['payload']['sessions'][number];
export type WorktreeAnnotationMessageEntry =
	WorktreeAnnotationMessageBatchEvent['payload']['messages'][number];
export type WorktreeAnnotationThreadContext =
	WorktreeAnnotationMessageBatchEvent['payload']['context'];

export interface WorktreeAnnotationThreadProjection {
	readonly context: WorktreeAnnotationThreadContext;
	readonly messages: readonly WorktreeAnnotationMessageEntry[];
}

export interface WorktreeAnnotationProjectionSnapshot {
	readonly commandOutcomes: readonly WorktreeAnnotationCommandOutcome[];
	readonly outputHistory: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly presentationRevision: number;
	readonly recoveryStatus: 'available' | 'recovered_degraded' | 'unavailable';
	readonly revision: number | null;
	readonly sessions: readonly WorktreeAnnotationSessionSummary[];
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
	readonly transportStatus:
		| { readonly kind: 'available' }
		| {
				readonly failedRevision: number;
				readonly failureClass: WorktreeAnnotationProjectionAssemblyFailureClass;
				readonly kind: 'unavailable';
				readonly recovery: 'awaitingReplay' | 'blocked' | 'requested';
		  };
	readonly worktreeId: string | null;
}

export type WorktreeAnnotationProjectionAssemblyFailureClass =
	| 'duplicateTerminal'
	| 'excessThreadCount'
	| 'messageIdentityViolation'
	| 'postTerminalBatch';

export interface WorktreeAnnotationProjectionAssemblyFailure {
	readonly failureClass: WorktreeAnnotationProjectionAssemblyFailureClass;
	readonly revision: number;
	readonly subscriptionId: string;
}

interface WorktreeAnnotationThreadAssembly {
	readonly context: WorktreeAnnotationThreadContext;
	readonly messagesById: Map<string, WorktreeAnnotationMessageEntry>;
	readonly ordinals: Set<number>;
	terminal: boolean;
}

interface WorktreeAnnotationProjectionAssembly {
	readonly completedThreadIds: Set<string>;
	readonly expectedThreadCount: number;
	readonly messageIds: Set<string>;
	readonly producerId: string;
	readonly revision: number;
	readonly state: WorktreeAnnotationProjectionStateEvent['payload'];
	readonly threadsById: Map<string, WorktreeAnnotationThreadAssembly>;
}

export const emptyWorktreeAnnotationProjectionSnapshot: WorktreeAnnotationProjectionSnapshot = {
	commandOutcomes: [],
	outputHistory: [],
	presentationRevision: 0,
	recoveryStatus: 'available',
	revision: null,
	sessions: [],
	threads: [],
	transportStatus: { kind: 'available' },
	worktreeId: null,
};

export class WorktreeAnnotationProjectionStore {
	#barredSubscriptionId: string | null = null;
	readonly #listeners = new Set<() => void>();
	readonly #onAssemblyFailure: (
		failure: WorktreeAnnotationProjectionAssemblyFailure,
	) => 'blocked' | 'requested';
	#assembly: WorktreeAnnotationProjectionAssembly | null = null;
	#snapshot = emptyWorktreeAnnotationProjectionSnapshot;

	constructor(
		onAssemblyFailure: (
			failure: WorktreeAnnotationProjectionAssemblyFailure,
		) => 'blocked' | 'requested' = (): 'blocked' => 'blocked',
	) {
		this.#onAssemblyFailure = onAssemblyFailure;
	}

	getSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	getServerSnapshot = (): WorktreeAnnotationProjectionSnapshot => this.#snapshot;

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	apply(event: BridgeProductWorktreeAnnotationEvent, producerId: string): void {
		if (this.#barredSubscriptionId === producerId) return;
		if (event.eventKind === 'projection.state') {
			this.#applyProjectionState(event, producerId);
			return;
		}
		this.#applyMessageBatch(event, producerId);
	}

	#applyProjectionState(event: WorktreeAnnotationProjectionStateEvent, producerId: string): void {
		const publishedRevision = this.#snapshot.revision ?? -1;
		const assemblingRevision = this.#assembly?.revision ?? -1;
		const highestAcceptedRevision = Math.max(publishedRevision, assemblingRevision);
		const isActiveRevision = event.payload.revision === assemblingRevision;
		if (event.payload.revision < highestAcceptedRevision) return;
		if (event.payload.revision === publishedRevision && !isActiveRevision) return;

		const assembly: WorktreeAnnotationProjectionAssembly = {
			completedThreadIds: new Set(),
			expectedThreadCount: event.payload.expectedThreadCount,
			messageIds: new Set(),
			producerId,
			revision: event.payload.revision,
			state: event.payload,
			threadsById: new Map(),
		};
		this.#assembly = assembly;
		if (assembly.expectedThreadCount !== 0) return;
		this.#assembly = null;
		this.#publishCompleteAssembly(assembly, []);
	}

	#applyMessageBatch(event: WorktreeAnnotationMessageBatchEvent, producerId: string): void {
		const assembly = this.#assembly;
		if (
			assembly === null ||
			assembly.producerId !== producerId ||
			event.payload.revision !== assembly.revision
		) {
			return;
		}
		const threadId = event.payload.context.threadId;
		let thread = assembly.threadsById.get(threadId);
		if (thread === undefined) {
			if (assembly.threadsById.size >= assembly.expectedThreadCount) {
				this.#failAssembly(assembly, 'excessThreadCount');
				return;
			}
			thread = {
				context: event.payload.context,
				messagesById: new Map(),
				ordinals: new Set(),
				terminal: false,
			};
			assembly.threadsById.set(threadId, thread);
		} else if (thread.terminal) {
			this.#failAssembly(
				assembly,
				event.payload.isLastBatchForThread ? 'duplicateTerminal' : 'postTerminalBatch',
			);
			return;
		} else if (!annotationThreadContextsEqual(thread.context, event.payload.context)) {
			this.#failAssembly(assembly, 'messageIdentityViolation');
			return;
		}

		for (const message of event.payload.messages) {
			if (
				message.threadId !== threadId ||
				assembly.messageIds.has(message.messageId) ||
				thread.ordinals.has(message.ordinal)
			) {
				this.#failAssembly(assembly, 'messageIdentityViolation');
				return;
			}
			assembly.messageIds.add(message.messageId);
			thread.ordinals.add(message.ordinal);
			thread.messagesById.set(message.messageId, message);
		}
		if (!event.payload.isLastBatchForThread) return;
		thread.terminal = true;
		assembly.completedThreadIds.add(threadId);
		if (assembly.completedThreadIds.size !== assembly.expectedThreadCount) return;

		const threads = [...assembly.threadsById.values()].map(
			(threadAssembly): WorktreeAnnotationThreadProjection => ({
				context: threadAssembly.context,
				messages: [...threadAssembly.messagesById.values()].toSorted(
					(left, right): number => left.ordinal - right.ordinal,
				),
			}),
		);
		this.#assembly = null;
		this.#publishCompleteAssembly(assembly, threads);
	}

	updateTransportRecovery(
		failure: WorktreeAnnotationProjectionAssemblyFailure,
		recovery: 'awaitingReplay' | 'blocked',
	): void {
		const current = this.#snapshot.transportStatus;
		if (
			current.kind !== 'unavailable' ||
			current.failedRevision !== failure.revision ||
			current.failureClass !== failure.failureClass ||
			current.recovery !== 'requested'
		) {
			return;
		}
		this.#publish({
			...this.#snapshot,
			transportStatus: { ...current, recovery },
		});
	}

	#publish(snapshot: Omit<WorktreeAnnotationProjectionSnapshot, 'presentationRevision'>): void {
		this.#snapshot = {
			...snapshot,
			presentationRevision: this.#snapshot.presentationRevision + 1,
		};
		for (const listener of this.#listeners) listener();
	}

	#publishCompleteAssembly(
		assembly: WorktreeAnnotationProjectionAssembly,
		threads: readonly WorktreeAnnotationThreadProjection[],
	): void {
		if (this.#barredSubscriptionId !== null && this.#barredSubscriptionId !== assembly.producerId) {
			this.#barredSubscriptionId = null;
		}
		this.#publish(completeProjectionSnapshot(assembly, threads));
	}

	#failAssembly(
		assembly: WorktreeAnnotationProjectionAssembly,
		failureClass: WorktreeAnnotationProjectionAssemblyFailureClass,
	): void {
		this.#assembly = null;
		this.#barredSubscriptionId = assembly.producerId;
		const failure = {
			failureClass,
			revision: assembly.revision,
			subscriptionId: assembly.producerId,
		} satisfies WorktreeAnnotationProjectionAssemblyFailure;
		this.#publish({
			...this.#snapshot,
			transportStatus: {
				failedRevision: failure.revision,
				failureClass,
				kind: 'unavailable',
				recovery: this.#onAssemblyFailure(failure),
			},
		});
	}
}

function completeProjectionSnapshot(
	assembly: WorktreeAnnotationProjectionAssembly,
	threads: readonly WorktreeAnnotationThreadProjection[],
): Omit<WorktreeAnnotationProjectionSnapshot, 'presentationRevision'> {
	return {
		commandOutcomes: assembly.state.commandOutcomes,
		outputHistory: assembly.state.outputHistory,
		recoveryStatus: assembly.state.recoveryStatus,
		revision: assembly.revision,
		sessions: assembly.state.sessions,
		threads: threads.toSorted(compareAnnotationThreads),
		transportStatus: { kind: 'available' },
		worktreeId: assembly.state.worktreeId,
	};
}

function annotationThreadContextsEqual(
	left: WorktreeAnnotationThreadContext,
	right: WorktreeAnnotationThreadContext,
): boolean {
	return (
		left.diffSide === right.diffSide &&
		left.endLine === right.endLine &&
		left.path === right.path &&
		left.placement === right.placement &&
		left.resolution === right.resolution &&
		left.scope === right.scope &&
		left.sourceIdentity === right.sourceIdentity &&
		left.sourceRole === right.sourceRole &&
		left.startLine === right.startLine &&
		left.threadId === right.threadId
	);
}

function compareAnnotationThreads(
	left: WorktreeAnnotationThreadProjection,
	right: WorktreeAnnotationThreadProjection,
): number {
	const leftKey = [
		left.context.path ?? '',
		left.context.startLine ?? -1,
		left.context.endLine ?? -1,
		left.context.threadId,
	];
	const rightKey = [
		right.context.path ?? '',
		right.context.startLine ?? -1,
		right.context.endLine ?? -1,
		right.context.threadId,
	];
	return JSON.stringify(leftKey).localeCompare(JSON.stringify(rightKey));
}
