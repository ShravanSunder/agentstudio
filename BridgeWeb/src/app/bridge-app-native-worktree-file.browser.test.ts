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
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
		await expect.poll(() => commandDetails[1]).toMatchObject({
			jsonrpc: '2.0',
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'worktree-file',
				streamId: 'worktree-file:pane-1',
			},
			__nonce: 'bridge-1',
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeSnapshotFrame()), nonce: 'push-1' },
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

	test('fetches native worktree file resources from streamed response chunks', async () => {
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
		const backend = createBridgeAppNativeWorktreeFileBackend({
			target: document,
			fetchResource: async (url, init): Promise<Response> => {
				expect(url).toBe(
					'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1&revision=1',
				);
				expect(init?.signal).toBeInstanceOf(AbortSignal);
				return chunkedTextResponse(['native ', 'streamed ', 'content']);
			},
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		const body = await backend.fetchWorktreeFileResource({
			descriptor: makeAttachedDescriptor('content-1').descriptor,
			resourceUrl:
				'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1&revision=1',
			signal: new AbortController().signal,
		});

		expect(body).toMatchObject({
			authoritative: true,
			byteLength: 23,
		});
		expect(body.readText()).toBe('native streamed content');
		backend.dispose();
	});

	test('rejects native worktree file resources that exceed descriptor max bytes', async () => {
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
		const backend = createBridgeAppNativeWorktreeFileBackend({
			target: document,
			fetchResource: async (): Promise<Response> => chunkedTextResponse(['too ', 'large']),
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		await expect(
			backend.fetchWorktreeFileResource({
				descriptor: makeAttachedDescriptor('content-1', { maxBytes: 4 }).descriptor,
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1&revision=1',
				signal: new AbortController().signal,
			}),
		).rejects.toThrow('Bridge text resource stream exceeded issued max bytes');
		backend.dispose();
	});

	test('rejects native worktree file resources whose whole-body integrity mismatches', async () => {
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
		const backend = createBridgeAppNativeWorktreeFileBackend({
			target: document,
			fetchResource: async (): Promise<Response> => chunkedTextResponse(['tampered']),
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		await expect(
			backend.fetchWorktreeFileResource({
				descriptor: makeAttachedDescriptor('content-1', {
					integrity: {
						algorithm: 'sha256',
						kind: 'wholeHash',
						value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
					},
				}).descriptor,
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/content-1?generation=1&revision=1',
				signal: new AbortController().signal,
			}),
		).rejects.toThrow('Bridge text resource stream failed whole-body integrity validation');
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

function makeOpenSourceOutcome(): {
	readonly status: 'accepted';
	readonly protocol: 'worktree-file';
	readonly streamId: string;
	readonly generation: number;
} {
	return {
		status: 'accepted',
		protocol: 'worktree-file',
		streamId: 'worktree-file:pane-1',
		generation: 1,
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
	props: {
		readonly integrity?: ReturnType<
			typeof makeSnapshotFrame
		>['treeDescriptor']['descriptor']['content']['integrity'];
		readonly maxBytes?: number;
	} = {},
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
				maxBytes: props.maxBytes ?? 1024,
				...(props.integrity === undefined ? {} : { integrity: props.integrity }),
			},
		},
	};
}

function chunkedTextResponse(chunks: readonly string[]): Response {
	const encoder = new TextEncoder();
	const body = new ReadableStream<Uint8Array>({
		start(controller): void {
			for (const chunk of chunks) {
				controller.enqueue(encoder.encode(chunk));
			}
			controller.close();
		},
	});
	return Object.assign(new Response(body), {
		text: async (): Promise<string> => {
			throw new Error('whole body text() should not be used for Worktree/File resources');
		},
	});
}
