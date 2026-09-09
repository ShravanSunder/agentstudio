import type {
	WorktreeAnnotationCommandOutcome,
	WorktreeAnnotationMessageEntry,
} from './worktree-annotation-surface-client.js';

export interface WorktreeAnnotationMessageCommandCursor {
	readonly draftRevision: number | null;
	readonly messageId: string;
	readonly messageRevision: number;
	readonly savedRevision: number | null;
	readonly sessionId: string;
	readonly sessionRevision: number;
	readonly threadId: string;
	readonly threadRevision: number;
}

export function messageCommandCursorFromOutcome(
	outcome: WorktreeAnnotationCommandOutcome,
): WorktreeAnnotationMessageCommandCursor {
	if (
		outcome.status.kind !== 'committed' ||
		outcome.sessionId === null ||
		outcome.receipt?.kind !== 'message'
	) {
		throw new Error('Committed annotation command did not return its message receipt.');
	}
	const message = outcome.receipt.message;
	return {
		draftRevision: message.draft?.revision ?? null,
		messageId: message.messageId,
		messageRevision: message.messageRevision,
		savedRevision: message.savedRevision,
		sessionId: message.sessionId,
		sessionRevision: message.sessionRevision,
		threadId: message.threadId,
		threadRevision: message.threadRevision,
	};
}

export function messageCommandCursorFromProjection(
	message: WorktreeAnnotationMessageEntry,
): WorktreeAnnotationMessageCommandCursor {
	return {
		draftRevision: message.draft?.revision ?? null,
		messageId: message.messageId,
		messageRevision: message.messageRevision,
		savedRevision: message.savedRevision,
		sessionId: message.sessionId,
		sessionRevision: message.sessionRevision,
		threadId: message.threadId,
		threadRevision: message.threadRevision,
	};
}

export function newestMessageCommandCursor(
	current: WorktreeAnnotationMessageCommandCursor | null,
	candidate: WorktreeAnnotationMessageCommandCursor | null,
): WorktreeAnnotationMessageCommandCursor | null {
	if (current === null) return candidate;
	if (candidate === null) return current;
	if (candidate.messageRevision !== current.messageRevision) {
		return candidate.messageRevision > current.messageRevision ? candidate : current;
	}
	return candidate.sessionRevision > current.sessionRevision ? candidate : current;
}

export function newestCommandConfirmedThreadRevision(
	threadId: string,
	outcomes: readonly WorktreeAnnotationCommandOutcome[],
): number | null {
	let newestRevision: number | null = null;
	for (const outcome of outcomes) {
		if (outcome.status.kind !== 'committed') continue;
		const receipt = outcome.receipt;
		const candidateRevision =
			receipt?.kind === 'message' && receipt.context.threadId === threadId
				? receipt.message.threadRevision
				: receipt?.kind === 'message_removed' &&
					  receipt.threadId === threadId &&
					  receipt.threadRevision !== null
					? receipt.threadRevision
					: null;
		if (
			candidateRevision !== null &&
			(newestRevision === null || candidateRevision > newestRevision)
		) {
			newestRevision = candidateRevision;
		}
	}
	return newestRevision;
}
