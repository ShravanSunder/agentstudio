import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	cleanupNativeWorktreeFileBackendBrowserTest,
	commandIdFromUnknownCommand,
	createNativeWorktreeFileRPCFetchHarness,
	installReadyNativeWorktreeFileBackend,
	makeFileDescriptorFrame,
	makeIntakeEnvelope,
	makeOpenSourceOutcome,
	makeSnapshotFrame,
	makeSourceIdentity,
	makeTreeWindowFrame,
} from './bridge-app-native-worktree-file.browser.test-support.js';
import { createBridgeAppNativeWorktreeFileBackend } from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend', () => {
	afterEach(() => {
		cleanupNativeWorktreeFileBackendBrowserTest();
	});

	test('opens the native source stream and publishes response plus intake frames', async () => {
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
			createRequestId: () => 'request-1',
			fetchRPC: rpcFetch.fetch,
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
			params: {
				clientRequestId: 'request-1',
				repoId: '11111111-1111-4111-8111-111111111111',
				worktreeId: '22222222-2222-4222-8222-222222222222',
				rootPathToken: 'root-token',
				freshness: 'live',
			},
		});

		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				jsonrpc: '2.0',
				method: 'bridge.intakeReady',
				params: {
					generation: 1,
					protocolId: 'worktree-file',
					streamId: 'worktree-file:pane-1',
				},
			});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
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
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(makeFileDescriptorFrame())),
					nonce: 'push-1',
				},
			}),
		);
		expect(deliveredFrames).toEqual([[makeFileDescriptorFrame()]]);

		unsubscribe();
		backend.dispose();
	});

	test('requests buffered intake replay after the native stream identity is known', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness();
		let replayRequestCount = 0;
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
		const handleIntakeReplayRequest = (): void => {
			replayRequestCount += 1;
			document.dispatchEvent(
				new CustomEvent('__bridge_intake_json', {
					detail: {
						json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())),
						nonce: 'push-1',
					},
				}),
			);
		};
		document.addEventListener('__bridge_intake_replay_request', handleIntakeReplayRequest);
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			fetchRPC: rpcFetch.fetch,
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
			}),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();

		await expect(surfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity(),
		});
		expect(rpcFetch.commandDetails[1]).toMatchObject({
			method: 'bridge.intakeReady',
		});
		expect(replayRequestCount).toBe(1);
		document.removeEventListener('__bridge_intake_replay_request', handleIntakeReplayRequest);
		backend.dispose();
	});

	test('sends foreground descriptor metadata requests through the native worktree stream', async () => {
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend();
		const descriptorRequest: WorktreeFileDescriptorRequest = {
			fileId: 'file-1',
			lane: 'foreground',
			path: 'Sources/App/View.swift',
			rowId: 'row-1',
			sourceIdentity: makeSourceIdentity(),
		};

		const descriptorPromise = backend.requestWorktreeFileDescriptor(descriptorRequest);

		await expect
			.poll(() => commandDetails[2])
			.toMatchObject({
				jsonrpc: '2.0',
				id: 'request-2',
				method: 'worktreeFileSurface.requestFileDescriptor',
				params: descriptorRequest,
			});

		await expect(descriptorPromise).resolves.toBeUndefined();
		backend.dispose();
	});

	test('uses generation-specific intake-ready command ids across repeated opens', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness({
			openSourceStreamResponse: (command) => ({
				id: commandIdFromUnknownCommand(command),
				result: {
					...makeOpenSourceOutcome(),
					generation: commandIdFromUnknownCommand(command) === 'request-2' ? 2 : 1,
				},
			}),
		});
		const commandDetails = rpcFetch.commandDetails;
		let requestSequence = 0;
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
			createRequestId: () => {
				requestSequence += 1;
				return `request-${requestSequence}`;
			},
			fetchRPC: rpcFetch.fetch,
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const firstSurfacePromise = backend.loadWorktreeFileSurface().catch(() => null);
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({ __commandId: 'worktree-file:pane-1:generation-1:intake-ready' });
		const secondSurfacePromise = backend.loadWorktreeFileSurface().catch(() => null);
		await expect
			.poll(() => commandDetails[3])
			.toMatchObject({ __commandId: 'worktree-file:pane-1:generation-2:intake-ready' });

		backend.dispose();
		await expect(firstSurfacePromise).resolves.toBeNull();
		await expect(secondSurfacePromise).resolves.toBeNull();
	});

	test('keeps waiting for a late initial snapshot instead of permanently blanking FileView', async () => {
		vi.useFakeTimers();
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
			createRequestId: () => 'request-1',
			fetchRPC: rpcFetch.fetch,
			responseTimeoutMilliseconds: 5,
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
			});
		await vi.advanceTimersByTimeAsync(6);
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

	test('records invalid native open outcome responses before rejecting the surface load', async () => {
		const rpcFetch = createNativeWorktreeFileRPCFetchHarness({
			openSourceStreamResponse: (command) => ({
				id: commandIdFromUnknownCommand(command),
				result: {
					status: 'accepted',
					protocol: 'review',
					streamId: 'worktree-file:pane-1',
					generation: 1,
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
			fetchRPC: rpcFetch.fetch,
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();

		await expect(surfacePromise).rejects.toThrow(
			'Native Worktree/File open stream returned invalid outcome',
		);
		expect(commandDetails[0]).toMatchObject({
			method: 'worktreeFileSurface.openSourceStream',
		});
		expect(window.__bridgeNativeWorktreeFileProbe).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ reason: 'open_response_received' }),
				expect.objectContaining({ reason: 'open_response_parse_failed' }),
			]),
		);
		backend.dispose();
	});

	test('keeps replayed tree windows with the initial surface while snapshot is resolving', async () => {
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
			createRequestId: () => 'request-1',
			fetchRPC: rpcFetch.fetch,
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
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(makeTreeWindowFrame())),
					nonce: 'push-1',
				},
			}),
		);

		const surface = await surfacePromise;
		expect(surface.frames).toEqual([makeSnapshotFrame(), makeTreeWindowFrame()]);
		expect(deliveredFrames).toEqual([]);
		backend.dispose();
	});
});
