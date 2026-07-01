import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	type BridgeAppNativeWorktreeFileBackend,
	createBridgeAppNativeWorktreeFileBackend,
	createNativeWorktreeFileRequestId,
} from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend', () => {
	afterEach(() => {
		vi.useRealTimers();
		document.documentElement.removeAttribute('data-bridge-worktree-file-source-spec');
		document.body.replaceChildren();
		delete window.__bridgeNativeWorktreeFileProbe;
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

	test('requests native Worktree/File descriptors through RPC and publishes intake frames', async () => {
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
			createRequestId: (() => {
				let sequence = 0;
				return (): string => {
					sequence += 1;
					return `request-${sequence}`;
				};
			})(),
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
			__nonce: 'bridge-1',
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
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-2', result: {}, nonce: 'push-1' },
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
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend();

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
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: 'request-2', nonce: 'push-1' },
			}),
		);

		await expect(requestPromise).rejects.toThrow(
			'Native Worktree/File descriptor request returned invalid acknowledgement',
		);
		backend.dispose();
	});

	test('opens the native source stream without WebCrypto request ids', async () => {
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
			__nonce: 'bridge-1',
		});
		expect(openCommand).toHaveProperty('id');
		const commandId = commandIdFromUnknownCommand(openCommand);
		expect(commandId.startsWith('worktree-file-')).toBe(true);

		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: { id: commandId, result: makeOpenSourceOutcome(), nonce: 'push-1' },
			}),
		);
		await expect
			.poll(() => commandDetails[1])
			.toMatchObject({
				method: 'bridge.intakeReady',
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
		expect(commandDetails[0]).toMatchObject({
			id: 'request-1',
			method: 'worktreeFileSurface.openSourceStream',
		});
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: {
					id: 'request-1',
					error: {
						code: -32_602,
						message: 'worktree_file.root_token_mismatch',
					},
				},
			}),
		);

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

function makeSourceIdentity(
	props: { readonly subscriptionGeneration?: number; readonly sourceCursor?: string } = {},
): WorktreeFileSurfaceSourceIdentity {
	return {
		sourceId: 'source-1',
		repoId: '11111111-1111-4111-8111-111111111111',
		worktreeId: '22222222-2222-4222-8222-222222222222',
		subscriptionGeneration: props.subscriptionGeneration ?? 1,
		sourceCursor: props.sourceCursor ?? 'cursor-1',
		rootRevisionToken: 'root-token',
	};
}

async function installReadyNativeWorktreeFileBackend(): Promise<{
	readonly backend: BridgeAppNativeWorktreeFileBackend;
	readonly commandDetails: unknown[];
}> {
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
		createRequestId: (() => {
			let sequence = 0;
			return (): string => {
				sequence += 1;
				return `request-${sequence}`;
			};
		})(),
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
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: { json: JSON.stringify(makeIntakeEnvelope(makeSnapshotFrame())), nonce: 'push-1' },
		}),
	);
	await expect(surfacePromise).resolves.toMatchObject({
		source: makeSourceIdentity(),
	});
	return { backend, commandDetails };
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
		treeRows: [
			{
				rowId: 'row-1',
				path: 'Sources/App/View.swift',
				name: 'View.swift',
				parentPath: 'Sources/App',
				depth: 2,
				isDirectory: false,
				fileId: 'file-1',
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
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

function commandIdFromUnknownCommand(command: unknown): string {
	if (
		typeof command !== 'object' ||
		command === null ||
		!('id' in command) ||
		typeof command.id !== 'string'
	) {
		throw new Error('expected command with string id');
	}
	return command.id;
}

function requireMessagePort(port: MessagePort | null): MessagePort {
	if (port === null) {
		throw new Error('expected host intake message port');
	}
	return port;
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

function makeResetFrame(props: {
	readonly generation: number;
	readonly sequence: number;
}): Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.reset' }> {
	return {
		kind: 'reset',
		frameKind: 'worktree.reset',
		streamId: 'worktree-file:pane-1',
		generation: props.generation,
		sequence: props.sequence,
		reason: 'sourceChanged',
		source: makeSourceIdentity({
			subscriptionGeneration: props.generation,
			sourceCursor: `cursor-${props.generation}`,
		}),
	};
}

function makeTreeWindowFrame(
	props: {
		readonly generation?: number;
		readonly sequence?: number;
		readonly startIndex?: number;
	} = {},
): Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.treeWindow' }> {
	const generation = props.generation ?? 1;
	const sequence = props.sequence ?? 1;
	const startIndex = props.startIndex ?? 1;
	return {
		kind: 'delta',
		frameKind: 'worktree.treeWindow',
		streamId: 'worktree-file:pane-1',
		generation,
		sequence,
		projectionIdentity: {
			source: makeSourceIdentity({
				subscriptionGeneration: generation,
				sourceCursor: `cursor-${generation}`,
			}),
			pathScope: [],
			sortKey: 'path',
			groupKey: 'none',
			filterKey: 'all',
			treeWindowKey: `tree-window-${startIndex}`,
		},
		windowDescriptor: makeAttachedDescriptor(`tree-window-${startIndex}`),
		rows: [
			{
				rowId: 'row:Sources/App.swift',
				path: 'Sources/App.swift',
				name: 'App.swift',
				parentPath: 'Sources',
				depth: 1,
				isDirectory: false,
				fileId: 'file-1',
				sizeBytes: 42,
				lineCount: 2,
			},
		],
		treeSizeFacts: {
			extentKind: 'exactPathCount',
			pathCount: startIndex + 1,
			rowHeightPixels: 24,
			windowStartIndex: startIndex,
			windowRowCount: 1,
		},
	};
}

function makeIntakeEnvelope(frame: WorktreeFileProtocolFrame): {
	readonly kind: WorktreeFileProtocolFrame['kind'];
	readonly streamId: string;
	readonly generation: number;
	readonly sequence: number;
	readonly payload: WorktreeFileProtocolFrame;
} {
	return {
		kind: frame.kind,
		streamId: frame.streamId,
		generation: frame.generation,
		sequence: frame.sequence,
		payload: frame,
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
