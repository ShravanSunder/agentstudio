import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { installBridgeAppDevWorktreeBackend } from './bridge-app-dev-worktree.js';

describe('Bridge app dev Worktree/File backend', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		window.history.replaceState(null, '', '/');
		document.documentElement.removeAttribute('data-bridge-app-protocol');
	});

	test('requests file descriptors through the Vite demand endpoint and publishes the frame', async () => {
		window.history.replaceState(null, '', '/?fixture=worktree&scenario=current-worktree');
		const fetchRequests: string[] = [];
		const fetchMock = vi.fn(async (input: RequestInfo | URL): Promise<Response> => {
			const requestUrl =
				typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
			fetchRequests.push(requestUrl);
			if (requestUrl.startsWith('/__bridge-worktree/file-descriptor?')) {
				return Response.json({ frame: makeDescriptorFrame() });
			}
			return new Response('unexpected request', { status: 500 });
		});
		vi.stubGlobal('fetch', fetchMock);
		const backend = installBridgeAppDevWorktreeBackend();
		const deliveredFrames: Array<readonly WorktreeFileProtocolFrame[]> = [];
		backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});

		await backend.requestWorktreeFileDescriptor(makeDescriptorRequest());

		expect(fetchRequests).toEqual([
			'/__bridge-worktree/file-descriptor?scenario=current-worktree&path=Sources%2FAgentStudio%2FApp%2FAppDelegate.swift&generation=1&cursor=cursor-1',
		]);
		expect(deliveredFrames).toEqual([[makeDescriptorFrame()]]);
	});
});

function makeSourceIdentity(): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'dev-worktree-source',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		subscriptionGeneration: 1,
		sourceCursor: 'cursor-1',
		rootRevisionToken: 'root-1',
	};
}

function makeDescriptorRequest(): WorktreeFileDescriptorRequest {
	return {
		sourceIdentity: makeSourceIdentity(),
		rowId: 'row:Sources/AgentStudio/App/AppDelegate.swift',
		path: 'Sources/AgentStudio/App/AppDelegate.swift',
		fileId: 'file-app-delegate',
		lane: 'foreground',
	};
}

function makeDescriptorFrame(): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: 'worktree-file:bridge-worktree-dev-pane',
		generation: 1,
		sequence: 1,
		frameKind: 'worktree.fileDescriptor',
		descriptor: {
			path: 'Sources/AgentStudio/App/AppDelegate.swift',
			fileId: 'file-app-delegate',
			contentHandle: 'app-delegate-content',
			contentHash: 'sha256:app-delegate',
			sourceIdentity: makeSourceIdentity(),
			sizeBytes: 20,
			virtualizedExtentKind: 'exactLineCount',
			lineCount: 2,
			isBinary: false,
			language: 'swift',
			fileExtension: 'swift',
			contentDescriptor: {
				ref: {
					descriptorId: 'app-delegate-content',
					expectedProtocol: 'worktree-file',
					expectedResourceKind: 'worktree.fileContent',
					expectedIdentity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
						sourceId: 'dev-worktree-source',
						generation: 1,
						streamId: 'worktree-file:bridge-worktree-dev-pane',
						cursor: 'cursor-1',
					},
				},
				descriptor: {
					descriptorId: 'app-delegate-content',
					protocol: 'worktree-file',
					resourceKind: 'worktree.fileContent',
					resourceUrl:
						'agentstudio://resource/worktree-file/worktree.fileContent/app-delegate-content?generation=1&cursor=cursor-1',
					identity: {
						paneId: 'bridge-worktree-dev-pane',
						protocol: 'worktree-file',
						sourceId: 'dev-worktree-source',
						generation: 1,
						streamId: 'worktree-file:bridge-worktree-dev-pane',
						cursor: 'cursor-1',
					},
					content: {
						mediaType: 'text/plain; charset=utf-8',
						encoding: 'utf-8',
						maxBytes: 20,
						integrity: {
							kind: 'wholeHash',
							algorithm: 'sha256',
							value: 'app-delegate',
						},
					},
				},
			},
		},
	};
}
