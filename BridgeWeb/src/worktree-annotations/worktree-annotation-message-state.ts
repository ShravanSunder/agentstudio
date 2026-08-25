export interface WorktreeAnnotationMessageStateFacts {
	readonly attentionState: 'new' | 'not_applicable' | 'viewed';
	readonly authorKind: 'agent' | 'human';
	readonly draft: object | null;
	readonly handled: boolean;
	readonly savedBody: string | null;
	readonly savedRevision: number | null;
}

export interface WorktreeAnnotationDerivedMessageState {
	readonly isAllEligible: boolean;
	readonly isNew: boolean;
	readonly isPending: boolean;
}

export interface WorktreeAnnotationThreadStateCounts {
	readonly newCount: number;
	readonly pendingCount: number;
}

export function deriveWorktreeAnnotationMessageState(
	message: WorktreeAnnotationMessageStateFacts,
): WorktreeAnnotationDerivedMessageState {
	const isCurrentSaved =
		message.savedBody !== null && message.savedRevision !== null && message.draft === null;
	return {
		isAllEligible: isCurrentSaved,
		isNew: isCurrentSaved && message.authorKind === 'agent' && message.attentionState === 'new',
		isPending: isCurrentSaved && message.authorKind === 'human' && !message.handled,
	};
}

export function deriveWorktreeAnnotationThreadStateCounts(
	messages: readonly WorktreeAnnotationMessageStateFacts[],
): WorktreeAnnotationThreadStateCounts {
	let newCount = 0;
	let pendingCount = 0;
	for (const message of messages) {
		const state = deriveWorktreeAnnotationMessageState(message);
		if (state.isNew) newCount += 1;
		if (state.isPending) pendingCount += 1;
	}
	return { newCount, pendingCount };
}
