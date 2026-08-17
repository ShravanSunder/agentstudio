export type WorktreeAnnotationOutputSelection =
	| { readonly kind: 'explicit'; readonly messageIds: ReadonlySet<string> }
	| { readonly excludedMessageIds: ReadonlySet<string>; readonly kind: 'allEligible' };

export type WorktreeAnnotationOutputWireSelection =
	| { readonly kind: 'explicit'; readonly messageIds: string[] }
	| { readonly excludedMessageIds: string[]; readonly kind: 'allEligible' };

export function createWorktreeAnnotationOutputSelection(): WorktreeAnnotationOutputSelection {
	return { kind: 'explicit', messageIds: new Set() };
}

export function clearWorktreeAnnotationOutputSelection(): WorktreeAnnotationOutputSelection {
	return createWorktreeAnnotationOutputSelection();
}

export function selectAllEligibleWorktreeAnnotationOutput(): WorktreeAnnotationOutputSelection {
	return { excludedMessageIds: new Set(), kind: 'allEligible' };
}

export function toggleWorktreeAnnotationOutputMessage(
	selection: WorktreeAnnotationOutputSelection,
	messageId: string,
	selected: boolean,
): WorktreeAnnotationOutputSelection {
	if (selection.kind === 'explicit') {
		const nextMessageIds = new Set(selection.messageIds);
		if (selected) nextMessageIds.add(messageId);
		else nextMessageIds.delete(messageId);
		return { kind: 'explicit', messageIds: nextMessageIds };
	}
	const nextExcludedMessageIds = new Set(selection.excludedMessageIds);
	if (selected) nextExcludedMessageIds.delete(messageId);
	else nextExcludedMessageIds.add(messageId);
	return { excludedMessageIds: nextExcludedMessageIds, kind: 'allEligible' };
}

export function selectedWorktreeAnnotationMessageIds(
	selection: WorktreeAnnotationOutputSelection,
	eligibleMessageIds: readonly string[],
): readonly string[] {
	if (selection.kind === 'explicit') {
		return eligibleMessageIds.filter((messageId): boolean => selection.messageIds.has(messageId));
	}
	return eligibleMessageIds.filter(
		(messageId): boolean => !selection.excludedMessageIds.has(messageId),
	);
}

export function worktreeAnnotationOutputWireSelection(
	selection: WorktreeAnnotationOutputSelection,
): WorktreeAnnotationOutputWireSelection {
	if (selection.kind === 'explicit') {
		return { kind: 'explicit', messageIds: [...selection.messageIds] };
	}
	return {
		excludedMessageIds: [...selection.excludedMessageIds],
		kind: 'allEligible',
	};
}
