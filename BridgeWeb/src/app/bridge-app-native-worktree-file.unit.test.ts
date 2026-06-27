// @vitest-environment jsdom

import { afterEach, describe, expect, test } from 'vitest';

import type {
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { createBridgeAppNativeWorktreeFileBackend } from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend', () => {
	afterEach(() => {
		document.documentElement.removeAttribute('data-bridge-worktree-file-source-spec');
		document.body.replaceChildren();
	});

	test('opens the native source stream and publishes response plus intake frames', async () => {
		const commandDetails: unknown[] = [];
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-1');
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
				includeFileDescriptors: true,
				includeComments: false,
				includeAgentComms: false,
				freshness: 'live',
			}),
		);
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}
		const deliveredFrames: Array<readonly WorktreeFileProtocolFrame[]> = [];
		const unsubscribe = backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		expect(commandDetails[0]).toMatchObject({
			jsonrpc: '2.0',
			id: 'request-1',
			method: 'worktreeFileSurface.openSourceStream',
			__nonce: 'bridge-1',
			params: {
				clientRequestId: 'request-1',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				freshness: 'live',
			},
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeSnapshotFrame(), nonce: 'push-1' },
			}),
		);
		const surface = await surfacePromise;
		expect(surface.frames).toEqual([makeSnapshotFrame()]);
		expect(surface.provenance).toEqual({
			baseRef: 'native-current-worktree',
			scenarioName: 'current-worktree',
			worktreeRootToken: 'root-token',
		});
		expect(surface.source).toEqual(makeSourceIdentity());

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeFileDescriptorFrame()), nonce: 'push-1' },
			}),
		);
		expect(deliveredFrames).toEqual([[makeFileDescriptorFrame()]]);

		unsubscribe();
		backend.dispose();
	});
});

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: '11111111-1111-4111-8111-111111111111',
		worktreeId: '22222222-2222-4222-8222-222222222222',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
		rootRevisionToken: 'root-token',
	};
}

function makeSnapshotFrame(): Extract<
	WorktreeFileProtocolFrame,
	{ readonly frameKind: 'worktree.snapshot' }
> {
	return {
		kind: 'snapshot',
		frameKind: 'worktree.snapshot',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 0,
		source: makeSourceIdentity(),
		treeDescriptor: makeAttachedDescriptor('tree-window'),
		treeSizeFacts: {
			pathCount: 1,
			rowHeightPixels: 24,
		},
	};
}

function makeFileDescriptorFrame(): Extract<
	WorktreeFileProtocolFrame,
	{ readonly frameKind: 'worktree.fileDescriptor' }
> {
	return {
		kind: 'delta',
		frameKind: 'worktree.fileDescriptor',
		streamId: 'worktree-file:pane-1',
		generation: 1,
		sequence: 1,
		descriptor: {
			path: 'Sources/App.swift',
			fileId: 'file-1',
			contentHandle: 'content-1',
			contentDescriptor: makeAttachedDescriptor('content-1'),
			sourceIdentity: makeSourceIdentity(),
			sizeBytes: 42,
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 2,
			isBinary: false,
			language: 'swift',
			fileExtension: 'swift',
		},
	};
}

function makeAttachedDescriptor(
	descriptorId: string,
): ReturnType<typeof makeSnapshotFrame>['treeDescriptor'] {
	const identity = {
		paneId: 'pane-1',
		protocol: 'worktree-file',
		sourceId: 'source-1',
		generation: 1,
		revision: 1,
	};
	return {
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
			resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/${descriptorId}?generation=1&revision=1`,
			identity,
			content: {
				mediaType: 'text/plain',
				encoding: 'utf-8',
				expectedBytes: 42,
				maxBytes: 1024,
			},
		},
	};
}
