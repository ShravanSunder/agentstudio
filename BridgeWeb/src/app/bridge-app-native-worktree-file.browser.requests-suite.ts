import { afterEach, describe, expect, test } from 'vitest';

import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	chunkedTextResponse,
	cleanupNativeWorktreeFileBackendBrowserTest,
	commandIdFromUnknownCommand,
	createNativeWorktreeFileRPCFetchHarness,
	installReadyNativeWorktreeFileBackend,
	makeAttachedDescriptor,
	makeFileDescriptorFrame,
	makeIntakeEnvelope,
	makeSnapshotFrame,
	makeSourceIdentity,
	nativeWorktreeFileInjectedSenderProps,
} from './bridge-app-native-worktree-file.browser.test-support.js';
import {
	createBridgeAppNativeWorktreeFileBackend,
	createNativeWorktreeFileRequestId,
} from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend', () => {
	afterEach(() => {
		cleanupNativeWorktreeFileBackendBrowserTest();
	});

	test('posts native Worktree/File open and intake-ready commands through injected worker senders', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness();
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
				includeComments: false,
				includeAgentComms: false,
				freshness: 'live',
			}),
		);
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			sendWorktreeFileIntakeReady: rpcFetch.sendWorktreeFileIntakeReady,
			...nativeWorktreeFileInjectedSenderProps(rpcFetch),
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		await expect.poll(() => rpcFetch.commandDetails.length).toBe(2);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
			}),
		);

		await expect(surfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity(),
		});
		expect(rpcFetch.commandDetails).toMatchObject([
			{
				id: 'request-1',
				method: 'worktreeFileSurface.openSourceStream',
				sentBy: 'open-source-stream-sender',
			},
			{
				method: 'bridge.intakeReady',
				sentBy: 'intake-ready-sender',
				params: {
					protocolId: 'worktree-file',
					streamId: 'worktree-file:pane-1',
				},
			},
		]);
		backend.dispose();
	});

	test('requests native Worktree/File descriptors through injected worker senders and publishes intake frames', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness();
		const commandDetails = rpcFetch.commandDetails;
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
				includeComments: false,
				includeAgentComms: false,
				freshness: 'live',
			}),
		);
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: (() => {
				let sequence = 0;
				return (): string => {
					sequence += 1;
					return `request-${sequence}`;
				};
			})(),
			sendWorktreeFileIntakeReady: rpcFetch.sendWorktreeFileIntakeReady,
			...nativeWorktreeFileInjectedSenderProps(rpcFetch),
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}
		const deliveredFrames: Array<readonly WorktreeFileProtocolFrame[]> = [];
		backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
			});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
			}),
		);
		await expect(surfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity(),
		});

		const requestPromise = backend.requestWorktreeFileDescriptor({
			sourceIdentity: makeSourceIdentity(),
			rowId: 'row:src/app.ts',
			path: 'src/app.ts',
			fileId: 'file-1',
			lane: 'foreground',
		});

		expect(commandDetails[2]).toMatchObject({
			jsonrpc: '2.0',
			id: 'request-2',
			method: 'worktreeFileSurface.requestFileDescriptor',
			sentBy: 'request-file-descriptor-sender',
			params: {
				sourceIdentity: makeSourceIdentity(),
				rowId: 'row:src/app.ts',
				path: 'src/app.ts',
				fileId: 'file-1',
				lane: 'foreground',
			},
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(makeFileDescriptorFrame())),
					nonce: 'push-1',
				},
			}),
		);

		await expect(requestPromise).resolves.toBeUndefined();
		expect(deliveredFrames).toEqual([[makeFileDescriptorFrame()]]);
		backend.dispose();
	});

	test('rejects malformed native Worktree/File descriptor requests before dispatch', async () => {
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend();
		const foregroundLane: WorktreeFileDescriptorRequest['lane'] = 'foreground';
		const requestWithExtraField = {
			sourceIdentity: makeSourceIdentity(),
			rowId: 'row:src/app.ts',
			path: 'src/app.ts',
			fileId: 'file-1',
			lane: foregroundLane,
			unexpected: 'reject-me',
		};

		await expect(backend.requestWorktreeFileDescriptor(requestWithExtraField)).rejects.toThrow(
			'Native Worktree/File descriptor request is invalid',
		);

		expect(commandDetails).toHaveLength(2);
		backend.dispose();
	});

	test('rejects malformed native Worktree/File descriptor acknowledgements', async () => {
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend({
			requestFileDescriptorResponse: (command) => ({
				id: commandIdFromUnknownCommand(command),
			}),
		});

		const requestPromise = backend.requestWorktreeFileDescriptor({
			sourceIdentity: makeSourceIdentity(),
			rowId: 'row:src/app.ts',
			path: 'src/app.ts',
			fileId: 'file-1',
			lane: 'foreground',
		});
		expect(commandDetails[2]).toMatchObject({
			id: 'request-2',
			method: 'worktreeFileSurface.requestFileDescriptor',
			sentBy: 'request-file-descriptor-sender',
		});

		await expect(requestPromise).rejects.toThrow(
			'Native Worktree/File descriptor request returned invalid acknowledgement',
		);
		backend.dispose();
	});

	test('signals stream reset when descriptor RPC fails for stale source generation', async () => {
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend({
			requestFileDescriptorResponse: (command) => ({
				id: commandIdFromUnknownCommand(command),
				error: { code: -32_602, message: 'worktree_file.stale_source_generation' },
			}),
		});
		let resetRequiredNotificationCount = 0;
		const unregisterResetRequiredCallback = backend.registerWorktreeFileStreamResetRequiredCallback(
			(): void => {
				resetRequiredNotificationCount += 1;
			},
		);

		const requestPromise = backend.requestWorktreeFileDescriptor({
			sourceIdentity: makeSourceIdentity(),
			rowId: 'row:src/app.ts',
			path: 'src/app.ts',
			fileId: 'file-1',
			lane: 'foreground',
		});
		expect(commandDetails[2]).toMatchObject({
			id: 'request-2',
			method: 'worktreeFileSurface.requestFileDescriptor',
			sentBy: 'request-file-descriptor-sender',
		});

		await expect(requestPromise).rejects.toThrow(
			'Native Worktree/File descriptor request failed: worktree_file.stale_source_generation',
		);
		await expect.poll(() => resetRequiredNotificationCount).toBe(1);
		unregisterResetRequiredCallback();
		backend.dispose();
	});

	test('opens the native source stream without WebCrypto request ids', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness();
		const commandDetails = rpcFetch.commandDetails;
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
				includeComments: false,
				includeAgentComms: false,
				freshness: 'live',
			}),
		);
		const backend = createBridgeAppNativeWorktreeFileBackend({
			sendWorktreeFileIntakeReady: rpcFetch.sendWorktreeFileIntakeReady,
			...nativeWorktreeFileInjectedSenderProps(rpcFetch),
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		const openCommand = commandDetails[0];
		expect(openCommand).toMatchObject({
			jsonrpc: '2.0',
			method: 'worktreeFileSurface.openSourceStream',
			sentBy: 'open-source-stream-sender',
		});
		expect(openCommand).toHaveProperty('id');
		const commandId = commandIdFromUnknownCommand(openCommand);
		expect(commandId.startsWith('worktree-file-')).toBe(true);

		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
				sentBy: 'intake-ready-sender',
				params: {
					protocolId: 'worktree-file',
					streamId: 'worktree-file:pane-1',
				},
			});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
			}),
		);

		await expect(surfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity(),
		});
		backend.dispose();
	});

	test('preserves safe native open-source rejection codes in browser errors', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness({
			openSourceStreamResponse: (command) => ({
				id: commandIdFromUnknownCommand(command),
				error: {
					code: -32_602,
					message: 'worktree_file.root_token_mismatch',
				},
			}),
		});
		const commandDetails = rpcFetch.commandDetails;
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
				includeComments: false,
				includeAgentComms: false,
				freshness: 'live',
			}),
		);
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			sendWorktreeFileIntakeReady: rpcFetch.sendWorktreeFileIntakeReady,
			...nativeWorktreeFileInjectedSenderProps(rpcFetch),
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		expect(commandDetails[0]).toMatchObject({
			id: 'request-1',
			method: 'worktreeFileSurface.openSourceStream',
			sentBy: 'open-source-stream-sender',
		});

		await expect(surfacePromise).rejects.toThrow(
			'Native Worktree/File open stream failed: worktree_file.root_token_mismatch',
		);
		backend.dispose();
	});

	test('creates native Worktree/File request ids without browser crypto', () => {
		const firstRequestId = createNativeWorktreeFileRequestId();
		const secondRequestId = createNativeWorktreeFileRequestId();

		expect(firstRequestId).toMatch(/^worktree-file-[a-z0-9]+-[a-z0-9]+$/u);
		expect(secondRequestId).toMatch(/^worktree-file-[a-z0-9]+-[a-z0-9]+$/u);
		expect(secondRequestId).not.toBe(firstRequestId);
	});

	test('fetches native worktree file resources from streamed response chunks', async () => {
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
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
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
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
		document.documentElement.setAttribute(
			'data-bridge-worktree-file-source-spec',
			JSON.stringify({
				clientRequestId: 'bootstrap-request',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				includeStatuses: true,
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
