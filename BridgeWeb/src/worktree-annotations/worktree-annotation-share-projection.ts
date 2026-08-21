import type { WorktreeAnnotationShareScope } from './worktree-annotation-share-mode.js';

export interface WorktreeAnnotationShareMessageFacts {
	readonly draft: object | null;
	readonly handled: boolean;
	readonly messageId: string;
	readonly messageRevision: number;
	readonly savedBody: string | null;
	readonly sessionId: string;
	readonly sessionRevision: number;
}

export interface WorktreeAnnotationShareThreadFacts<
	TMessage extends WorktreeAnnotationShareMessageFacts,
> {
	readonly context: {
		readonly path: string;
		readonly placement: 'exact' | 'outdated' | 'relocated' | 'unavailable';
		readonly startLine: number;
		readonly threadId: string;
	};
	readonly messages: readonly TMessage[];
}

type ShareThreadMessage<
	TThread extends WorktreeAnnotationShareThreadFacts<WorktreeAnnotationShareMessageFacts>,
> = TThread['messages'][number];

type FilteredShareThread<
	TThread extends WorktreeAnnotationShareThreadFacts<WorktreeAnnotationShareMessageFacts>,
> = Omit<TThread, 'messages'> & { readonly messages: readonly ShareThreadMessage<TThread>[] };

export interface WorktreeAnnotationShareProjection<
	TThread extends WorktreeAnnotationShareThreadFacts<WorktreeAnnotationShareMessageFacts>,
> {
	readonly allCount: number;
	readonly inlineThreads: readonly FilteredShareThread<TThread>[];
	readonly newCount: number;
	readonly otherThreads: readonly FilteredShareThread<TThread>[];
}

export function deriveWorktreeAnnotationShareProjection<
	TThread extends WorktreeAnnotationShareThreadFacts<WorktreeAnnotationShareMessageFacts>,
>(props: {
	readonly scope: WorktreeAnnotationShareScope;
	readonly threads: readonly TThread[];
}): WorktreeAnnotationShareProjection<TThread> {
	let allCount = 0;
	let newCount = 0;
	const inlineThreads: FilteredShareThread<TThread>[] = [];
	const otherThreads: FilteredShareThread<TThread>[] = [];

	for (const thread of props.threads) {
		const currentSavedMessages = thread.messages.filter(isCurrentSavedMessage);
		allCount += currentSavedMessages.length;
		newCount += currentSavedMessages.filter((message) => !message.handled).length;
		const participatingMessages =
			props.scope === 'new'
				? currentSavedMessages.filter((message) => !message.handled)
				: currentSavedMessages;
		if (participatingMessages.length === 0) continue;
		const filteredThread: FilteredShareThread<TThread> = {
			...thread,
			messages: participatingMessages,
		};
		if (thread.context.placement === 'exact' || thread.context.placement === 'relocated') {
			inlineThreads.push(filteredThread);
		} else {
			otherThreads.push(filteredThread);
		}
	}

	return { allCount, inlineThreads, newCount, otherThreads };
}

function isCurrentSavedMessage(message: WorktreeAnnotationShareMessageFacts): boolean {
	return message.savedBody !== null && message.draft === null;
}
