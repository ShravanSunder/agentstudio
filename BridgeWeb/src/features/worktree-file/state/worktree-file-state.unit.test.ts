import { describe, expect, test } from 'vitest';

import type { WorktreeFileDescriptor } from '../models/worktree-file-protocol-models.js';
import {
	applyWorktreeFileInvalidationToState,
	createWorktreeFileSurfaceState,
	openWorktreeFileSession,
	refreshWorktreeOpenFileSession,
} from './worktree-file-state.js';

describe('worktree file state', () => {
	test('keeps large bodies out of state while opening file sessions', () => {
		const descriptor = makeDescriptor('Sources/App/View.swift', 'descriptor-1');
		const state = openWorktreeFileSession({
			state: createWorktreeFileSurfaceState(),
			descriptor,
			openFileSessionId: 'session-1',
		});

		expect(state.openFileSessionsById['session-1']).toMatchObject({
			status: 'fresh',
			renderContentKey: 'descriptor-1',
			descriptorRef: descriptor.contentDescriptor.ref,
		});
		expect(JSON.stringify(state)).not.toContain('struct View');
	});

	test('marks open file stale without auto-fetching replacement content', () => {
		const descriptor = makeDescriptor('Sources/App/View.swift', 'descriptor-1');
		const latestDescriptor = makeDescriptor('Sources/App/View.swift', 'descriptor-2');
		const opened = openWorktreeFileSession({
			state: createWorktreeFileSurfaceState(),
			descriptor,
			openFileSessionId: 'session-1',
		});

		const result = applyWorktreeFileInvalidationToState({
			state: opened,
			invalidation: {
				path: 'Sources/App/View.swift',
				fileId: 'file-1',
				reason: 'filesystemEvent',
				contentHandleIds: ['handle-2'],
				latestDescriptor,
			},
		});

		expect(result.state.openFileSessionsById['session-1']).toMatchObject({
			status: 'stale',
			staleReason: 'filesystemEvent',
			latestDescriptorRef: latestDescriptor.contentDescriptor.ref,
		});
		expect(result.stimuli).toEqual([
			{
				kind: 'openFileInvalidated',
				descriptorRef: descriptor.contentDescriptor.ref,
			},
		]);
	});

	test('manual refresh emits explicit refresh demand for latest descriptor only', () => {
		const descriptor = makeDescriptor('Sources/App/View.swift', 'descriptor-1');
		const latestDescriptor = makeDescriptor('Sources/App/View.swift', 'descriptor-2');
		const opened = openWorktreeFileSession({
			state: createWorktreeFileSurfaceState(),
			descriptor,
			openFileSessionId: 'session-1',
		});
		const stale = applyWorktreeFileInvalidationToState({
			state: opened,
			invalidation: {
				path: 'Sources/App/View.swift',
				fileId: 'file-1',
				reason: 'filesystemEvent',
				latestDescriptor,
			},
		}).state;

		const result = refreshWorktreeOpenFileSession({
			state: stale,
			openFileSessionId: 'session-1',
		});

		expect(result.state.openFileSessionsById['session-1']?.status).toBe('refreshing');
		expect(result.stimulus).toEqual({
			kind: 'explicitRefresh',
			descriptorRef: latestDescriptor.contentDescriptor.ref,
		});
	});
});

function makeDescriptor(path: string, descriptorId: string): WorktreeFileDescriptor {
	const sourceIdentity = {
		sourceId: 'source-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
	};
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		streamId: 'worktree-file:pane-1',
	};
	return {
		path,
		fileId: 'file-1',
		contentHandle: `handle-${descriptorId}`,
		contentDescriptor: {
			ref: {
				descriptorId,
				expectedProtocol: 'worktree-file',
				expectedResourceKind: 'worktree.fileContent',
				expectedIdentity: identity,
			},
			descriptor: {
				descriptorId,
				protocol: 'worktree-file',
				resourceKind: 'worktree.fileContent',
				resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/${descriptorId}?generation=1`,
				identity,
				content: {
					mediaType: 'text/plain',
					encoding: 'utf-8',
					expectedBytes: 64,
					maxBytes: 1024,
				},
			},
		},
		sourceIdentity,
		sizeBytes: 64,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 4,
		isBinary: false,
	};
}
