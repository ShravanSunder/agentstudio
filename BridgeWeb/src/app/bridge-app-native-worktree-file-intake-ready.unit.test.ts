import { afterEach, describe, expect, test, vi } from 'vitest';

import { RecordingBridgeCommWorker } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.test-support.js';
import {
	createBridgeAppNativeWorktreeFileIntakeReadyTransport,
	createBridgeAppNativeWorktreeFileWorkerRpcTransport,
} from './bridge-app-native-worktree-file-intake-ready.js';

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

	test('resolves pending Worktree/File intake-ready sends as failed on degraded health', async () => {
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
		const worker = RecordingDefaultBridgeCommWorker.instances[0];
		if (worker === undefined) {
			throw new Error('expected default comm worker instance');
		}
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'request-worktree-file-intake-ready',
			status: 'degraded',
			message: 'Bridge comm worker failed to forward bridge.intakeReady.',
			transferDescriptors: [],
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();

		await expect(
			Promise.race([sendPromise, Promise.resolve('still-pending' as const)]),
		).resolves.toBe(false);
		transport.dispose();
	});

	test('uses monotonic epochs for repeated open-source stream commands after intake-ready', async () => {
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
		const transport = createBridgeAppNativeWorktreeFileWorkerRpcTransport();

		const firstOpenPromise = transport.sendOpenSourceStream({
			requestId: 'request-worktree-file-open-source-1',
			sourceSpec: makeWorktreeFileSourceSpec('client-open-1'),
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();
		const worker = RecordingDefaultBridgeCommWorker.instances[0];
		if (worker === undefined) {
			throw new Error('expected default comm worker instance');
		}
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
			command: 'worktreeFileOpenSourceStream',
			requestId: 'request-worktree-file-open-source-1',
			epoch: 1,
		});
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'worktreeFileOpenSourceStreamResult',
			requestId: 'request-worktree-file-open-source-1',
			outcome: {
				status: 'accepted',
				protocol: 'worktree-file',
				streamId: 'worktree-file:pane-1',
				generation: 4,
			},
			transferDescriptors: [],
		});
		await expect(firstOpenPromise).resolves.toMatchObject({
			status: 'accepted',
			generation: 4,
		});

		const intakeReadyPromise = transport.sendIntakeReady({
			requestId: 'request-worktree-file-intake-ready',
			generation: 4,
			streamId: 'worktree-file:pane-1',
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();
		expect(worker.postedMessages[2]).toMatchObject({
			kind: 'command',
			command: 'worktreeFileIntakeReady',
			requestId: 'request-worktree-file-intake-ready',
			epoch: 4,
		});
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'request-worktree-file-intake-ready',
			status: 'ready',
			transferDescriptors: [],
		});
		await expect(intakeReadyPromise).resolves.toBe(true);

		const secondOpenPromise = transport.sendOpenSourceStream({
			requestId: 'request-worktree-file-open-source-2',
			sourceSpec: makeWorktreeFileSourceSpec('client-open-2'),
		});
		await flushWorktreeFileIntakeReadyTransportMicrotasks();
		expect(worker.postedMessages[3]).toMatchObject({
			kind: 'command',
			command: 'worktreeFileOpenSourceStream',
			requestId: 'request-worktree-file-open-source-2',
			epoch: 5,
		});
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'worktreeFileOpenSourceStreamResult',
			requestId: 'request-worktree-file-open-source-2',
			outcome: {
				status: 'accepted',
				protocol: 'worktree-file',
				streamId: 'worktree-file:pane-1',
				generation: 5,
			},
			transferDescriptors: [],
		});
		await expect(secondOpenPromise).resolves.toMatchObject({
			status: 'accepted',
			generation: 5,
		});
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

function makeWorktreeFileSourceSpec(clientRequestId: string): {
	readonly clientRequestId: string;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly rootPathToken: string;
	readonly includeStatuses: true;
	readonly includeComments: false;
	readonly includeAgentComms: false;
	readonly freshness: 'live';
} {
	return {
		clientRequestId,
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		rootPathToken: 'root-token-1',
		includeStatuses: true,
		includeComments: false,
		includeAgentComms: false,
		freshness: 'live',
	};
}
