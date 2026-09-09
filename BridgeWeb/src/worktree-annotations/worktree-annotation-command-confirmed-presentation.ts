import type {
	WorktreeAnnotationCommandConfirmedThreadProjection,
	WorktreeAnnotationInlineThreadProjection,
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-projection-store.js';

export function mergeWorktreeAnnotationCommandConfirmedThreads(props: {
	readonly commandConfirmedThreads: readonly WorktreeAnnotationCommandConfirmedThreadProjection[];
	readonly serverThreads: readonly WorktreeAnnotationThreadProjection[];
}): readonly WorktreeAnnotationInlineThreadProjection[] {
	const threadsById = new Map<string, WorktreeAnnotationInlineThreadProjection>(
		props.serverThreads.map((thread) => [thread.context.threadId, thread]),
	);
	for (const commandThread of props.commandConfirmedThreads) {
		const serverThread = threadsById.get(commandThread.context.threadId);
		if (serverThread === undefined || serverThread.context.placement === 'command_confirmed') {
			threadsById.set(commandThread.context.threadId, commandThread);
			continue;
		}
		threadsById.set(commandThread.context.threadId, {
			context: { ...serverThread.context, resolution: commandThread.context.resolution },
			messages: mergeCommandConfirmedMessages(serverThread.messages, commandThread.messages),
		});
	}
	return [...threadsById.values()].toSorted(compareInlineThreads);
}

function mergeCommandConfirmedMessages(
	serverMessages: readonly WorktreeAnnotationMessageEntry[],
	commandMessages: readonly WorktreeAnnotationMessageEntry[],
): readonly WorktreeAnnotationMessageEntry[] {
	const messagesById = new Map(serverMessages.map((message) => [message.messageId, message]));
	for (const commandMessage of commandMessages) {
		const serverMessage = messagesById.get(commandMessage.messageId);
		if (
			serverMessage === undefined ||
			commandMessage.messageRevision >= serverMessage.messageRevision
		) {
			messagesById.set(commandMessage.messageId, commandMessage);
		}
	}
	return [...messagesById.values()].toSorted((left, right): number => left.ordinal - right.ordinal);
}

function compareInlineThreads(
	left: WorktreeAnnotationInlineThreadProjection,
	right: WorktreeAnnotationInlineThreadProjection,
): number {
	return JSON.stringify([
		left.context.path,
		left.context.startLine,
		left.context.endLine,
		left.context.threadId,
	]).localeCompare(
		JSON.stringify([
			right.context.path,
			right.context.startLine,
			right.context.endLine,
			right.context.threadId,
		]),
	);
}
