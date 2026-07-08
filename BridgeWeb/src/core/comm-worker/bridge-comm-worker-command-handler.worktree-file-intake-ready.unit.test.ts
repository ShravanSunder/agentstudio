import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import { encodeBridgeWorkerWorktreeFileIntakeReadyCommand } from './bridge-comm-worker-protocol.js';

describe('Bridge comm worker command handler Worktree/File intake-ready protocol', () => {
	test('worktreeFileIntakeReady commands are accepted as worker-owned ordinary RPC intents', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
			scheduleSelectedFileViewContentReadyPreparation: (): void => {},
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
				requestId: 'request-worktree-file-intake-ready',
				epoch: 1,
				generation: 4,
				streamId: 'worktree-file:pane-1',
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-worktree-file-intake-ready',
				status: 'ready',
			},
		]);
	});
});
