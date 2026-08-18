export type WorktreeAnnotationOutputSelection =
	| { readonly kind: 'explicit'; readonly messageIds: ReadonlySet<string> }
	| { readonly excludedMessageIds: ReadonlySet<string>; readonly kind: 'allEligible' };

import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';

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

export function worktreeAnnotationOutputTransferOperations(props: {
	readonly outputKind: 'clipboardMarkdown' | 'jsonFile';
	readonly selection: WorktreeAnnotationOutputSelection;
	readonly sessionId: string;
	readonly transferId: string;
}): readonly BridgeProductWorktreeAnnotationOperation[] {
	const selectionMode = props.selection.kind;
	const messageIds =
		props.selection.kind === 'explicit'
			? [...props.selection.messageIds]
			: [...props.selection.excludedMessageIds];
	const operations: BridgeProductWorktreeAnnotationOperation[] = [
		{
			kind: 'output.selection.begin',
			outputKind: props.outputKind,
			selectionMode,
			sessionId: props.sessionId,
			transferId: props.transferId,
		},
	];
	for (let offset = 0, ordinal = 0; offset < messageIds.length; offset += 64, ordinal += 1) {
		operations.push({
			kind: 'output.selection.chunk',
			messageIds: messageIds.slice(offset, offset + 64),
			ordinal,
			selectionMode,
			sessionId: props.sessionId,
			transferId: props.transferId,
		});
	}
	operations.push({
		kind: 'output.selection.commit',
		selectionMode,
		sessionId: props.sessionId,
		transferId: props.transferId,
	});
	return operations;
}
