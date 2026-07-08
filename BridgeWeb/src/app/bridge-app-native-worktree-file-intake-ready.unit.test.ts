import { afterEach, describe, expect, test, vi } from 'vitest';

import { RecordingBridgeCommWorker } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.test-support.js';
import { createBridgeAppNativeWorktreeFileIntakeReadyTransport } from './bridge-app-native-worktree-file-intake-ready.js';

describe('Bridge app native Worktree/File intake-ready transport', () => {
	afterEach(() => {
		vi.restoreAllMocks();
		vi.unstubAllGlobals();
		vi.useRealTimers();
		RecordingDefaultBridgeCommWorker.instances = [];
		RecordingDefaultBridgeCommWorker.constructedUrls = [];
	});

	test('sends Worktree/File intake-ready through the default comm-worker transport', async () => {
		vi.stubGlobal('Worker', RecordingDefaultBridgeCommWorker);
		const fetchWorkerSource = vi.fn(
			async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
				new Response('self.onmessage = () => undefined;\n', { status: 200 }),
		);
		vi.stubGlobal('fetch', fetchWorkerSource);
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-comm-worker');
		vi.spyOn(URL, 'revokeObjectURL').mockImplementation((): void => {});
		const transport = createBridgeAppNativeWorktreeFileIntakeReadyTransport();

		const sendPromise = transport.send({
			requestId: 'request-worktree-file-intake-ready',
			generation: 7,
			streamId: 'worktree-file:pane-1',
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();

		expect(fetchWorkerSource).toHaveBeenCalledWith(
			'agentstudio://app/assets/bridge-comm-worker.js',
		);
		expect(RecordingDefaultBridgeCommWorker.constructedUrls).toEqual(['blob:bridge-comm-worker']);
		const worker = RecordingDefaultBridgeCommWorker.instances[0];
		if (worker === undefined) {
			throw new Error('expected default comm worker instance');
		}
		expect(worker.postedMessages).toEqual([
			expect.objectContaining({
				method: 'bridgeCommWorker.bootstrap',
				requestId: 'worktree-file-intake-ready-worker-bootstrap',
			}),
		]);

		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'worktree-file-intake-ready-worker-bootstrap',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();

		expect(worker.postedMessages[1]).toMatchObject({
			kind: 'command',
			command: 'worktreeFileIntakeReady',
			requestId: 'request-worktree-file-intake-ready',
			epoch: 7,
			generation: 7,
			protocolId: 'worktree-file',
			streamId: 'worktree-file:pane-1',
		});
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'request-worktree-file-intake-ready',
			status: 'ready',
			transferDescriptors: [],
		});

		await expect(sendPromise).resolves.toBe(true);
		transport.dispose();
		expect(worker.terminateCount).toBe(1);
	});

	test('resolves pending Worktree/File intake-ready sends as failed on dispose', async () => {
		vi.stubGlobal('Worker', RecordingDefaultBridgeCommWorker);
		vi.stubGlobal(
			'fetch',
			vi.fn(
				async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
					new Response('self.onmessage = () => undefined;\n', { status: 200 }),
			),
		);
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-comm-worker');
		vi.spyOn(URL, 'revokeObjectURL').mockImplementation((): void => {});
		const transport = createBridgeAppNativeWorktreeFileIntakeReadyTransport();

		const sendPromise = transport.send({
			requestId: 'request-worktree-file-intake-ready',
			generation: 7,
			streamId: 'worktree-file:pane-1',
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();
		transport.dispose();

		await expect(sendPromise).resolves.toBe(false);
	});

	test('resolves pending Worktree/File intake-ready sends as failed when worker health never arrives', async () => {
		vi.useFakeTimers();
		vi.stubGlobal('Worker', RecordingDefaultBridgeCommWorker);
		vi.stubGlobal(
			'fetch',
			vi.fn(
				async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> =>
					new Response('self.onmessage = () => undefined;\n', { status: 200 }),
			),
		);
		vi.spyOn(URL, 'createObjectURL').mockReturnValue('blob:bridge-comm-worker');
		vi.spyOn(URL, 'revokeObjectURL').mockImplementation((): void => {});
		const transport = createBridgeAppNativeWorktreeFileIntakeReadyTransport({
			timeoutMilliseconds: 25,
		});

		const sendPromise = transport.send({
			requestId: 'request-worktree-file-intake-ready',
			generation: 7,
			streamId: 'worktree-file:pane-1',
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();
		await vi.advanceTimersByTimeAsync(25);
		await flushWorktreeFileIntakeReadyTransportMicrotasks();

		await expect(
			Promise.race([sendPromise, Promise.resolve('still-pending' as const)]),
		).resolves.toBe(false);
		transport.dispose();
	});
});

class RecordingDefaultBridgeCommWorker extends RecordingBridgeCommWorker {
	static constructedUrls: string[] = [];
	static instances: RecordingDefaultBridgeCommWorker[] = [];

	constructor(url: string | URL, _options?: WorkerOptions) {
		super();
		RecordingDefaultBridgeCommWorker.constructedUrls.push(String(url));
		RecordingDefaultBridgeCommWorker.instances.push(this);
	}
}

async function flushWorktreeFileIntakeReadyTransportMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}
