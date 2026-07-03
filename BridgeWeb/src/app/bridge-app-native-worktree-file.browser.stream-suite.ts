import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	cleanupNativeWorktreeFileBackendBrowserTest,
	installReadyNativeWorktreeFileBackend,
	makeFileDescriptorFrame,
	makeIntakeEnvelope,
	makeOpenSourceOutcome,
	makeResetFrame,
	makeSnapshotFrame,
	makeSourceIdentity,
	makeTreeWindowFrame,
	requireMessagePort,
} from './bridge-app-native-worktree-file.browser.test-support.js';
import { createBridgeAppNativeWorktreeFileBackend } from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend', () => {
	afterEach(() => {
		cleanupNativeWorktreeFileBackendBrowserTest();
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
				__nonce: 'bridge-1',
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
		const commandDetails: unknown[] = [];
		let replayRequestCount = 0;
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-1');
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
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
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
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);

		await expect(surfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity(),
		});
		expect(commandDetails[1]).toMatchObject({
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
				__nonce: 'bridge-1',
				params: descriptorRequest,
			});
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-2', result: {}, nonce: 'push-1' },
			}),
		);

		await expect(descriptorPromise).resolves.toBeUndefined();
		backend.dispose();
	});

	test('uses generation-specific intake-ready command ids across repeated opens', async () => {
		const commandDetails: unknown[] = [];
		let requestSequence = 0;
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-1');
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
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => {
				requestSequence += 1;
				return `request-${requestSequence}`;
			},
			target: document,
		});
		if (backend === null) {
			throw new Error('expected native worktree backend');
		}
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const firstSurfacePromise = backend.loadWorktreeFileSurface().catch(() => null);
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({ __commandId: 'worktree-file:pane-1:generation-1:intake-ready' });
		const secondSurfacePromise = backend.loadWorktreeFileSurface().catch(() => null);
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: {
					id: 'request-2',
					result: { ...makeOpenSourceOutcome(), generation: 2 },
					nonce: 'push-1',
				},
			}),
		);
		await expect
			.poll(() => commandDetails[3])
			.toMatchObject({ __commandId: 'worktree-file:pane-1:generation-2:intake-ready' });

		backend.dispose();
		await expect(firstSurfacePromise).resolves.toBeNull();
		await expect(secondSurfacePromise).resolves.toBeNull();
	});

	test('keeps waiting for a late initial snapshot instead of permanently blanking FileView', async () => {
		vi.useFakeTimers();
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
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
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

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: {
					id: 'request-1',
					result: {
						status: 'accepted',
						protocol: 'review',
						streamId: 'worktree-file:pane-1',
						generation: 1,
					},
					nonce: 'push-1',
				},
			}),
		);

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
		backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
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

	test('records ordered-stream receiver rejection reasons for native intake drops', async () => {
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
		let resetRequiredNotificationCount = 0;
		const unregisterResetRequiredCallback = backend.registerWorktreeFileStreamResetRequiredCallback(
			(): void => {
				resetRequiredNotificationCount += 1;
			},
		);

		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-1' } }),
		);
		const surfacePromise = backend.loadWorktreeFileSurface();
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
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

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(makeTreeWindowFrame({ sequence: 3, startIndex: 200 })),
					),
					nonce: 'push-1',
				},
			}),
		);

		await expect
			.poll(() => window.__bridgeNativeWorktreeFileProbe?.at(-1))
			.toMatchObject({
				reason: 'drop_sequence_gap',
				receiverReason: 'sequence_gap',
				sequence: 3,
			});
		await expect.poll(() => resetRequiredNotificationCount).toBe(1);
		unregisterResetRequiredCallback();
		backend.dispose();
	});

	test('publishes accepted reset-generation tree windows to FileView subscribers', async () => {
		const { backend } = await installReadyNativeWorktreeFileBackend();
		const deliveredFrames: Array<readonly WorktreeFileProtocolFrame[]> = [];
		backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});
		const resetFrame = makeResetFrame({ generation: 2, sequence: 0 });
		const treeWindowFrame = makeTreeWindowFrame({
			generation: 2,
			sequence: 1,
			startIndex: 200,
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(resetFrame)), nonce: 'push-1' },
			}),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(treeWindowFrame)), nonce: 'push-1' },
			}),
		);

		expect(deliveredFrames).toEqual([[resetFrame], [treeWindowFrame]]);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).not.toContainEqual(
			expect.objectContaining({
				reason: 'drop_identity_mismatch',
				generation: 2,
			}),
		);
		backend.dispose();
	});

	test('accepts same-generation reset frames after a sequence gap', async () => {
		const { backend } = await installReadyNativeWorktreeFileBackend();
		const deliveredFrames: Array<readonly WorktreeFileProtocolFrame[]> = [];
		backend.subscribeWorktreeFileFrames((frames): void => {
			deliveredFrames.push(frames);
		});
		const resetFrame = makeResetFrame({ generation: 1, sequence: 4 });
		const recoveredTreeWindowFrame = makeTreeWindowFrame({
			generation: 1,
			sequence: 5,
			startIndex: 200,
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(makeTreeWindowFrame({ sequence: 3, startIndex: 100 })),
					),
					nonce: 'push-1',
				},
			}),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: JSON.stringify(makeIntakeEnvelope(resetFrame)), nonce: 'push-1' },
			}),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(recoveredTreeWindowFrame)),
					nonce: 'push-1',
				},
			}),
		);

		expect(deliveredFrames).toEqual([[resetFrame], [recoveredTreeWindowFrame]]);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).toContainEqual(
			expect.objectContaining({
				reason: 'drop_sequence_gap',
				receiverReason: 'sequence_gap',
				sequence: 3,
			}),
		);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).not.toContainEqual(
			expect.objectContaining({
				reason: 'drop_reset_required',
				sequence: 4,
			}),
		);
		backend.dispose();
	});

	test('receives native intake frames through the WebKit host port carrier', async () => {
		const commandDetails: unknown[] = [];
		let hostIntakePort: MessagePort | null = null;
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-1');
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
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
		document.addEventListener('__bridge_host_intake_port_request', (): void => {
			const channel = new MessageChannel();
			hostIntakePort = channel.port1;
			hostIntakePort.start();
			window.postMessage(
				{
					type: 'agentstudio.bridge.hostIntakePort',
					version: 1,
				},
				'*',
				[channel.port2],
			);
		});
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			responseTimeoutMilliseconds: 500,
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
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
			});
		await expect.poll(() => hostIntakePort).not.toBeNull();
		const connectedHostIntakePort = requireMessagePort(hostIntakePort);
		connectedHostIntakePort.postMessage({
			type: 'agentstudio.bridge.hostIntakeFrameJSON',
			version: 1,
			json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())),
		});
		connectedHostIntakePort.postMessage({
			type: 'agentstudio.bridge.hostIntakeFrameJSON',
			version: 1,
			json: JSON.stringify(
				makeIntakeEnvelope(makeTreeWindowFrame({ sequence: 1, startIndex: 200 })),
			),
		});

		const surface = await surfacePromise;
		expect(surface.frames[0]).toEqual(makeSnapshotFrame());
		await expect
			.poll((): readonly WorktreeFileProtocolFrame[] => [
				...surface.frames,
				...deliveredFrames.flat(),
			])
			.toEqual([makeSnapshotFrame(), makeTreeWindowFrame({ sequence: 1, startIndex: 200 })]);
		connectedHostIntakePort.close();
		backend.dispose();
	});

	test('does not double-apply native intake delivered through host port and page event carriers', async () => {
		const commandDetails: unknown[] = [];
		let hostIntakePort: MessagePort | null = null;
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-1');
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
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push('detail' in event ? event.detail : null);
		});
		document.addEventListener('__bridge_host_intake_port_request', (): void => {
			const channel = new MessageChannel();
			hostIntakePort = channel.port1;
			hostIntakePort.start();
			window.postMessage(
				{
					type: 'agentstudio.bridge.hostIntakePort',
					version: 1,
				},
				'*',
				[channel.port2],
			);
		});
		const backend = createBridgeAppNativeWorktreeFileBackend({
			createRequestId: () => 'request-1',
			responseTimeoutMilliseconds: 500,
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
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-1', result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
			});
		await expect.poll(() => hostIntakePort).not.toBeNull();
		const connectedHostIntakePort = requireMessagePort(hostIntakePort);
		const snapshotJSON = JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame()));
		const treeWindowJSON = JSON.stringify(
			makeIntakeEnvelope(makeTreeWindowFrame({ sequence: 1, startIndex: 200 })),
		);

		connectedHostIntakePort.postMessage({
			type: 'agentstudio.bridge.hostIntakeFrameJSON',
			version: 1,
			json: snapshotJSON,
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: snapshotJSON, nonce: 'push-1' },
			}),
		);
		connectedHostIntakePort.postMessage({
			type: 'agentstudio.bridge.hostIntakeFrameJSON',
			version: 1,
			json: treeWindowJSON,
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: { json: treeWindowJSON, nonce: 'push-1' },
			}),
		);

		const surface = await surfacePromise;
		await expect
			.poll((): readonly WorktreeFileProtocolFrame[] => [
				...surface.frames,
				...deliveredFrames.flat(),
			])
			.toEqual([makeSnapshotFrame(), makeTreeWindowFrame({ sequence: 1, startIndex: 200 })]);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).not.toContainEqual(
			expect.objectContaining({
				receiverReason: 'duplicate_sequence',
			}),
		);
		connectedHostIntakePort.close();
		backend.dispose();
	});
});
