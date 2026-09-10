import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';

type AnnotationCommandReceipt = NonNullable<WorktreeAnnotationCommandOutcome['receipt']>;
type AnnotationMessageReceipt = Extract<AnnotationCommandReceipt, { readonly kind: 'message' }>;
type AnnotationMessageReceiptContext = AnnotationMessageReceipt['context'];
type AnnotationThreadState = {
	readonly context: AnnotationMessageReceiptContext;
	readonly messages: WorktreeAnnotationMessageEntry[];
};

export class WorktreeAnnotationBrowserCommandReceiptFixture {
	readonly #commandConfirmedThreadsById = new Map<string, AnnotationThreadState>();
	#nextMessageIdentity = 31;
	#nextReplyMessageIdentity = 93;
	#nextThreadIdentity = 21;

	constructor(readonly preferredRootThreadId: string) {}

	receiptForCommittedOperation(props: {
		readonly committedSessionId: string;
		readonly committedSessionRevision: number;
		readonly operation: BridgeProductWorktreeAnnotationOperation;
		readonly projectedThreadsById: ReadonlyMap<
			string,
			{
				readonly context: WorktreeAnnotationThreadContext;
				readonly messages: readonly WorktreeAnnotationMessageEntry[];
			}
		>;
	}): WorktreeAnnotationCommandOutcome['receipt'] {
		const operation = props.operation;
		if (operation.kind === 'root.create') {
			if (operation.origin.kind !== 'located') return undefined;
			const threadId = this.#nextThreadId(props.projectedThreadsById);
			const message = this.#newDraftMessage({
				body: operation.body,
				editToken: operation.editToken,
				messageId: this.#nextMessageId(),
				ordinal: 0,
				sessionId: props.committedSessionId,
				sessionRevision: props.committedSessionRevision,
				threadId,
				threadRevision: 0,
			});
			const context = {
				diffSide: operation.origin.diffSide,
				endLine: operation.origin.endLine,
				path: operation.origin.path,
				resolution: 'open',
				scope: 'located',
				sourceIdentity: operation.origin.sourceIdentity,
				sourceRole: annotationReceiptSourceRole(operation.origin.sourceRole),
				startLine: operation.origin.startLine,
				threadId,
			} satisfies AnnotationMessageReceiptContext;
			this.#commandConfirmedThreadsById.set(threadId, { context, messages: [message] });
			return { context, kind: 'message', message };
		}
		if (operation.kind === 'reply.create') {
			const thread =
				this.#commandThread(operation.threadId, props.projectedThreadsById) ??
				this.#seedReplyThread(operation.threadId);
			const message = this.#newDraftMessage({
				body: operation.body,
				editToken: operation.editToken,
				messageId: this.#nextReplyMessageId(),
				ordinal: thread.messages.length,
				sessionId: operation.sessionId,
				sessionRevision: props.committedSessionRevision,
				threadId: operation.threadId,
				threadRevision: operation.expectedThreadRevision + 1,
			});
			thread.messages.push(message);
			return { context: thread.context, kind: 'message', message };
		}
		if (!isAnnotationMessageMutationOperation(operation)) return undefined;
		const located = this.#commandMessage(operation.messageId, props.projectedThreadsById);
		if (located === null) return undefined;
		const { message, thread } = located;
		if (
			(operation.kind === 'draft.flush' &&
				operation.body.trim().length === 0 &&
				message.savedRevision === null) ||
			(operation.kind === 'draft.revert' && message.savedRevision === null)
		) {
			thread.messages.splice(thread.messages.indexOf(message), 1);
			if (thread.messages.length === 0)
				this.#commandConfirmedThreadsById.delete(thread.context.threadId);
			return {
				kind: 'message_removed',
				messageId: message.messageId,
				removedMessageRevision: operation.expectedMessageRevision,
				sessionId: operation.sessionId,
				sessionRevision: props.committedSessionRevision,
				threadId: message.threadId,
				threadRevision:
					thread.messages.length === 0
						? null
						: Math.max(...thread.messages.map((item) => item.threadRevision)),
			};
		}
		const nextMessage = annotationMessageAfterOperation({
			committedSessionRevision: props.committedSessionRevision,
			message,
			operation,
		});
		thread.messages.splice(thread.messages.indexOf(message), 1, nextMessage);
		return { context: thread.context, kind: 'message', message: nextMessage };
	}

	#commandThread(
		threadId: string,
		projectedThreadsById: ReadonlyMap<
			string,
			{
				readonly context: WorktreeAnnotationThreadContext;
				readonly messages: readonly WorktreeAnnotationMessageEntry[];
			}
		>,
	): AnnotationThreadState | null {
		const confirmed = this.#commandConfirmedThreadsById.get(threadId);
		if (confirmed !== undefined) return confirmed;
		const projected = projectedThreadsById.get(threadId);
		if (projected === undefined) return null;
		const { placement: _placement, ...context } = projected.context;
		const seeded = { context, messages: [...projected.messages] };
		this.#commandConfirmedThreadsById.set(threadId, seeded);
		return seeded;
	}

	#seedReplyThread(threadId: string): AnnotationThreadState {
		const thread = {
			context: {
				diffSide: null,
				endLine: 7,
				path: 'Sources/App/View.swift',
				resolution: 'open',
				scope: 'located',
				sourceIdentity: 'source-1',
				sourceRole: 'file',
				startLine: 4,
				threadId,
			} satisfies AnnotationMessageReceiptContext,
			messages: [],
		};
		this.#commandConfirmedThreadsById.set(threadId, thread);
		return thread;
	}

	#commandMessage(
		messageId: string,
		projectedThreadsById: ReadonlyMap<
			string,
			{
				readonly context: WorktreeAnnotationThreadContext;
				readonly messages: readonly WorktreeAnnotationMessageEntry[];
			}
		>,
	): {
		readonly message: WorktreeAnnotationMessageEntry;
		readonly thread: AnnotationThreadState;
	} | null {
		for (const thread of this.#commandConfirmedThreadsById.values()) {
			const message = thread.messages.find((candidate) => candidate.messageId === messageId);
			if (message !== undefined) return { message, thread };
		}
		for (const threadId of projectedThreadsById.keys()) {
			const thread = this.#commandThread(threadId, projectedThreadsById);
			const message = thread?.messages.find((candidate) => candidate.messageId === messageId);
			if (thread !== null && thread !== undefined && message !== undefined)
				return { message, thread };
		}
		return null;
	}

	#newDraftMessage(props: {
		readonly body: string;
		readonly editToken: string;
		readonly messageId: string;
		readonly ordinal: number;
		readonly sessionId: string;
		readonly sessionRevision: number;
		readonly threadId: string;
		readonly threadRevision: number;
	}): WorktreeAnnotationMessageEntry {
		return {
			attentionState: 'not_applicable',
			authorKind: 'human',
			createdAt: props.sessionRevision,
			draft: { activeEditToken: props.editToken, body: props.body, revision: 0 },
			handled: false,
			messageId: props.messageId,
			messageRevision: 0,
			ordinal: props.ordinal,
			savedBody: null,
			savedRevision: null,
			sessionId: props.sessionId,
			sessionRevision: props.sessionRevision,
			status: 'editable',
			threadId: props.threadId,
			threadRevision: props.threadRevision,
		};
	}

	#nextMessageId(): string {
		const nextIdentity = this.#nextMessageIdentity++;
		return annotationFixtureId(nextIdentity);
	}

	#nextReplyMessageId(): string {
		const nextIdentity = this.#nextReplyMessageIdentity++;
		return annotationFixtureId(nextIdentity);
	}

	#nextThreadId(projectedThreadsById: ReadonlyMap<string, unknown>): string {
		if (
			this.#nextThreadIdentity === 21 &&
			!projectedThreadsById.has(this.preferredRootThreadId) &&
			!this.#commandConfirmedThreadsById.has(this.preferredRootThreadId)
		) {
			this.#nextThreadIdentity += 1;
			return this.preferredRootThreadId;
		}
		return annotationFixtureId(this.#nextThreadIdentity++);
	}
}

type AnnotationMessageMutationOperation = Extract<
	BridgeProductWorktreeAnnotationOperation,
	{
		readonly kind:
			| 'draft.edit.acquire'
			| 'draft.edit.release'
			| 'draft.flush'
			| 'draft.revert'
			| 'draft.save';
	}
>;

function isAnnotationMessageMutationOperation(
	operation: BridgeProductWorktreeAnnotationOperation,
): operation is AnnotationMessageMutationOperation {
	return (
		operation.kind === 'draft.edit.acquire' ||
		operation.kind === 'draft.edit.release' ||
		operation.kind === 'draft.flush' ||
		operation.kind === 'draft.revert' ||
		operation.kind === 'draft.save'
	);
}

function annotationMessageAfterOperation(props: {
	readonly committedSessionRevision: number;
	readonly message: WorktreeAnnotationMessageEntry;
	readonly operation: AnnotationMessageMutationOperation;
}): WorktreeAnnotationMessageEntry {
	const operation = props.operation;
	const message = props.message;
	if (operation.kind === 'draft.flush') {
		return {
			...message,
			draft: {
				activeEditToken: operation.editToken,
				body: operation.body,
				revision:
					operation.expectedDraftRevision === null ? 0 : operation.expectedDraftRevision + 1,
			},
			messageRevision: operation.expectedMessageRevision + 1,
			sessionRevision: props.committedSessionRevision,
		};
	}
	if (operation.kind === 'draft.save') {
		return {
			...message,
			draft: null,
			messageRevision: operation.expectedMessageRevision + 1,
			savedBody: message.draft?.body ?? message.savedBody,
			savedRevision: (message.savedRevision ?? 0) + 1,
			sessionRevision: props.committedSessionRevision,
		};
	}
	if (operation.kind === 'draft.revert') {
		return {
			...message,
			draft: null,
			messageRevision: operation.expectedMessageRevision + 1,
			sessionRevision: props.committedSessionRevision,
		};
	}
	return {
		...message,
		draft: {
			activeEditToken: operation.kind === 'draft.edit.acquire' ? operation.editToken : null,
			body: message.draft?.body ?? message.savedBody ?? '',
			revision: operation.expectedDraftRevision,
		},
		messageRevision: operation.expectedMessageRevision + 1,
		sessionRevision: props.committedSessionRevision,
	};
}

function annotationReceiptSourceRole(
	sourceRole: 'file' | 'reviewBase' | 'reviewHead',
): 'file' | 'review_base' | 'review_head' {
	if (sourceRole === 'reviewBase') return 'review_base';
	if (sourceRole === 'reviewHead') return 'review_head';
	return 'file';
}

function annotationFixtureId(identity: number): string {
	return `00000000-0000-7000-8000-${String(identity).padStart(12, '0')}`;
}
