import { afterEach, describe, expect, test } from 'vitest';

import type { WorktreeFileProtocolFrame } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	cleanupNativeWorktreeFileBackendBrowserTest,
	installReadyNativeWorktreeFileBackend,
	makeIntakeEnvelope,
	makeOpenSourceOutcome,
	makeResetFrame,
	makeSnapshotFrame,
	makeSourceIdentity,
	makeTreeWindowFrame,
	requireMessagePort,
} from './bridge-app-native-worktree-file.browser.test-support.js';
import { createBridgeAppNativeWorktreeFileBackend } from './bridge-app-native-worktree-file.js';

describe('Bridge app native Worktree/File backend recovery', () => {
	afterEach(() => {
		cleanupNativeWorktreeFileBackendBrowserTest();
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

	test('signals one stream reset for a resolved generation mismatch episode', async () => {
		const { backend } = await installReadyNativeWorktreeFileBackend();
		let resetRequiredNotificationCount = 0;
		const unregisterResetRequiredCallback = backend.registerWorktreeFileStreamResetRequiredCallback(
			(): void => {
				resetRequiredNotificationCount += 1;
			},
		);

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(
							makeTreeWindowFrame({ generation: 2, sequence: 1, startIndex: 200 }),
						),
					),
					nonce: 'push-1',
				},
			}),
		);
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(
							makeTreeWindowFrame({ generation: 2, sequence: 2, startIndex: 300 }),
						),
					),
					nonce: 'push-1',
				},
			}),
		);

		await expect.poll(() => resetRequiredNotificationCount).toBe(1);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).toContainEqual(
			expect.objectContaining({
				reason: 'drop_identity_mismatch',
				receiverReason: 'generation_mismatch',
				generation: 2,
				receiverGeneration: 1,
				reopenSignaled: true,
				streamIdMatches: true,
			}),
		);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).toContainEqual(
			expect.objectContaining({
				reason: 'drop_identity_mismatch',
				receiverReason: 'generation_mismatch',
				generation: 2,
				receiverGeneration: 1,
				reopenSignaled: false,
				streamIdMatches: true,
			}),
		);
		unregisterResetRequiredCallback();
		backend.dispose();
	});

	test('suppresses mismatch reset loops while a reopen is in flight', async () => {
		const { backend, commandDetails } = await installReadyNativeWorktreeFileBackend();
		let resetRequiredNotificationCount = 0;
		const unregisterResetRequiredCallback = backend.registerWorktreeFileStreamResetRequiredCallback(
			(): void => {
				resetRequiredNotificationCount += 1;
			},
		);

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(
							makeTreeWindowFrame({ generation: 2, sequence: 1, startIndex: 200 }),
						),
					),
					nonce: 'push-1',
				},
			}),
		);
		await expect.poll(() => resetRequiredNotificationCount).toBe(1);

		const reopenSurfacePromise = backend.loadWorktreeFileSurface();
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(
							makeTreeWindowFrame({ generation: 2, sequence: 2, startIndex: 300 }),
						),
					),
					nonce: 'push-1',
				},
			}),
		);

		await expect.poll(() => resetRequiredNotificationCount).toBe(1);
		document.dispatchEvent(
			new CustomEvent('__bridge_response', {
				detail: {
					id: 'request-2',
					result: {
						...makeOpenSourceOutcome(),
						generation: 2,
					},
					nonce: 'push-1',
				},
			}),
		);
		await expect
			.poll(() => commandDetails[3])
			.toMatchObject({
				method: 'bridge.intakeReady',
			});
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(makeResetFrame({ generation: 2, sequence: 0 }))),
					nonce: 'push-1',
				},
			}),
		);
		// The reopened stream advances to generation 2 via the reset baseline, then delivers the
		// fresh snapshot that resolves loadWorktreeFileSurface (the reset alone is buffered, not a
		// surface resolution). Without this the reopen promise never settles.
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(makeSnapshotFrame({ generation: 2, sequence: 1 })),
					),
					nonce: 'push-1',
				},
			}),
		);
		await expect(reopenSurfacePromise).resolves.toMatchObject({
			source: makeSourceIdentity({ subscriptionGeneration: 2, sourceCursor: 'cursor-2' }),
		});

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(
						makeIntakeEnvelope(
							makeTreeWindowFrame({ generation: 3, sequence: 1, startIndex: 400 }),
						),
					),
					nonce: 'push-1',
				},
			}),
		);

		await expect.poll(() => resetRequiredNotificationCount).toBe(2);
		unregisterResetRequiredCallback();
		backend.dispose();
	});

	test('signals stream reset for stream identity mismatch after open resolution', async () => {
		const { backend } = await installReadyNativeWorktreeFileBackend();
		let resetRequiredNotificationCount = 0;
		const unregisterResetRequiredCallback = backend.registerWorktreeFileStreamResetRequiredCallback(
			(): void => {
				resetRequiredNotificationCount += 1;
			},
		);
		const mismatchedFrame = {
			...makeTreeWindowFrame({ sequence: 1, startIndex: 200 }),
			streamId: 'worktree-file:pane-2',
		};

		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					json: JSON.stringify(makeIntakeEnvelope(mismatchedFrame)),
					nonce: 'push-1',
				},
			}),
		);

		await expect.poll(() => resetRequiredNotificationCount).toBe(1);
		expect(window.__bridgeNativeWorktreeFileProbe ?? []).toContainEqual(
			expect.objectContaining({
				reason: 'drop_identity_mismatch',
				receiverReason: 'stream_mismatch',
				receiverGeneration: 1,
				reopenSignaled: true,
				streamIdMatches: false,
			}),
		);
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
