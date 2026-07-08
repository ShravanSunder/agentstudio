import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerWorktreeFileIntakeReadyCommand,
	encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand,
	encodeBridgeWorkerWorktreeFileRequestDescriptorCommand,
} from './bridge-comm-worker-protocol.js';

describe('Bridge comm worker command handler Worktree/File intake-ready protocol', () => {
	test('Worktree/File scheme RPC commands are accepted as worker-owned intents', () => {
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
		const openMessages = handler.handleMessage(
			encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
				requestId: 'request-worktree-file-open-source',
				epoch: 1,
				sourceSpec: makeWorktreeFileSourceSpec(),
			}),
		);
		const descriptorMessages = handler.handleMessage(
			encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
				requestId: 'request-worktree-file-descriptor',
				epoch: 1,
				descriptorRequest: makeWorktreeFileDescriptorRequest(),
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
		expect(openMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-worktree-file-open-source',
				status: 'ready',
			},
		]);
		expect(descriptorMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'ready',
			},
		]);
	});
});

function makeWorktreeFileSourceSpec() {
	return {
		clientRequestId: 'client-open-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		rootPathToken: 'root-token-1',
		includeStatuses: true,
		includeComments: false,
		includeAgentComms: false,
		freshness: 'live',
	} as const;
}

function makeWorktreeFileDescriptorRequest() {
	return {
		sourceIdentity: {
			sourceId: 'source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 4,
			sourceCursor: 'cursor-1',
		},
		rowId: 'row-1',
		path: 'Sources/App/File.swift',
		fileId: 'file-1',
		lane: 'foreground',
	} as const;
}
