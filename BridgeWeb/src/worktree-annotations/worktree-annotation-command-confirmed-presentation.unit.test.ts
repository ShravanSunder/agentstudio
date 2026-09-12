import { describe, expect, test } from 'vitest';

import { mergeWorktreeAnnotationCommandConfirmedThreads } from './worktree-annotation-command-confirmed-presentation.js';
import type {
	WorktreeAnnotationCommandConfirmedThreadProjection,
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';

describe('command-confirmed annotation presentation', () => {
	test('replaces stale message content, appends replies, and retains deterministic ordinal order', () => {
		const root = message({
			body: 'Stale root',
			messageId: messageId(1),
			messageRevision: 1,
			ordinal: 0,
		});
		const confirmedRoot = { ...root, messageRevision: 2, savedBody: 'Confirmed root' };
		const confirmedReply = message({
			body: 'Confirmed reply',
			messageId: messageId(2),
			messageRevision: 0,
			ordinal: 1,
		});
		const serverThread = thread([root]);
		const commandThread: WorktreeAnnotationCommandConfirmedThreadProjection = {
			context: { ...serverThread.context, placement: 'command_confirmed', resolution: 'resolved' },
			messages: [confirmedReply, confirmedRoot],
		};

		const [merged] = mergeWorktreeAnnotationCommandConfirmedThreads({
			commandConfirmedThreads: [commandThread],
			serverThreads: [serverThread],
		});

		expect(merged?.context).toMatchObject({ placement: 'exact', resolution: 'resolved' });
		expect(
			merged?.messages.map(({ messageId: receiptMessageId, savedBody }) => [
				receiptMessageId,
				savedBody,
			]),
		).toEqual([
			[messageId(1), 'Confirmed root'],
			[messageId(2), 'Confirmed reply'],
		]);
	});
});

function thread(
	messages: readonly WorktreeAnnotationMessageEntry[],
): WorktreeAnnotationThreadProjection {
	return {
		context: {
			diffSide: null,
			endLine: 2,
			path: 'Sources/App.swift',
			placement: 'exact',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'source-1',
			sourceRole: 'file',
			startLine: 2,
			threadId: '01890abc-def0-7abc-8def-012345678902',
		},
		messages,
	};
}

function message(props: {
	readonly body: string;
	readonly messageId: string;
	readonly messageRevision: number;
	readonly ordinal: number;
}): WorktreeAnnotationMessageEntry {
	return {
		attentionState: 'not_applicable',
		authorKind: 'human',
		createdAt: props.ordinal,
		draft: null,
		handled: false,
		messageId: props.messageId,
		messageRevision: props.messageRevision,
		ordinal: props.ordinal,
		savedBody: props.body,
		savedRevision: 1,
		sessionId: '01890abc-def0-7abc-8def-0123456789ab',
		sessionRevision: 2,
		status: 'editable',
		threadId: '01890abc-def0-7abc-8def-012345678902',
		threadRevision: 2,
	};
}

function messageId(suffix: number): string {
	return `01890abc-def0-7abc-8def-${String(suffix).padStart(12, '0')}`;
}
