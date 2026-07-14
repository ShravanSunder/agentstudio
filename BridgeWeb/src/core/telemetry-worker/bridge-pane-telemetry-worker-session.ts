import {
	bridgeTelemetryWorkerDrainedAndClosedResultSchema,
	bridgeTelemetryWorkerDrainedResultSchema,
	bridgeTelemetryWorkerSnapshotResultSchema,
	type BridgeTelemetryWorkerBootstrap,
	type BridgeTelemetryWorkerDrainResult,
	type BridgeTelemetryWorkerSnapshot,
} from './bridge-telemetry-worker-contracts.js';
import {
	createBridgeTelemetryWorkerProducer,
	type BridgeTelemetryWorkerProducer,
} from './bridge-telemetry-worker-producer.js';

export interface BridgeTelemetryWorkerLike {
	readonly postMessage: (message: unknown, transfer: Transferable[]) => void;
	readonly terminate: () => void;
	readonly addEventListener?: (
		type: 'error' | 'message' | 'messageerror',
		listener: (event: Event | MessageEvent<unknown>) => void,
	) => void;
}

export type BridgePaneTelemetryWorkerSessionStatus =
	| 'active'
	| 'closed'
	| 'draining'
	| 'failed'
	| 'starting';

export interface BridgePaneTelemetryWorkerSession {
	readonly telemetrySessionId: string;
	readonly producerPreReadyBufferMaxBytes: number;
	readonly producerPreReadyBufferMaxSamples: number;
	readonly mainProducer: BridgeTelemetryWorkerProducer;
	readonly commProducerPort: MessagePort;
	readonly status: () => BridgePaneTelemetryWorkerSessionStatus;
	readonly replaceCommProducerPort: () => MessagePort;
	readonly snapshot: () => Promise<BridgeTelemetryWorkerSnapshot>;
	readonly drain: () => Promise<BridgeTelemetryWorkerDrainResult>;
	readonly drainAndClose: () => Promise<BridgeTelemetryWorkerDrainResult>;
	readonly dispose: () => void;
}

export interface CreateBridgePaneTelemetryWorkerSessionProps {
	readonly bootstrap: BridgeTelemetryWorkerBootstrap | null;
	readonly createWorker: () => BridgeTelemetryWorkerLike;
	readonly createMessageChannel?: () => MessageChannel;
	readonly scheduleDrainTimeout?: (callback: () => void, delayMilliseconds: number) => () => void;
}

type PendingControlOperation =
	| {
			readonly kind: 'snapshot';
			readonly requestId: string;
			readonly promise: Promise<BridgeTelemetryWorkerSnapshot>;
			readonly resolve: (snapshot: BridgeTelemetryWorkerSnapshot) => void;
			readonly reject: (error: Error) => void;
			cancelTimeout: (() => void) | null;
	  }
	| {
			readonly kind: 'drain' | 'drainAndClose';
			readonly requestId: string;
			readonly promise: Promise<BridgeTelemetryWorkerDrainResult>;
			readonly resolve: (result: BridgeTelemetryWorkerDrainResult) => void;
			readonly reject: (error: Error) => void;
			cancelTimeout: (() => void) | null;
	  };

export function createBridgePaneTelemetryWorkerSession(
	props: CreateBridgePaneTelemetryWorkerSessionProps,
): BridgePaneTelemetryWorkerSession | null {
	if (props.bootstrap === null) {
		return null;
	}
	const bootstrap = props.bootstrap;
	const createMessageChannel = props.createMessageChannel ?? (() => new MessageChannel());
	const scheduleDrainTimeout = props.scheduleDrainTimeout ?? defaultScheduleDrainTimeout;
	const worker = props.createWorker();
	const mainChannel = createMessageChannel();
	const commChannel = createMessageChannel();
	const mainProducer = createBridgeTelemetryWorkerProducer({
		initialSampleCredits: 0,
		initialControlCredits: 0,
		preReadyRequiredSampleCapacity: bootstrap.policy.producerPreReadyBufferMaxSamples,
		preReadyRequiredSampleMaxEncodedBytes: bootstrap.policy.producerPreReadyBufferMaxBytes,
		send: (message): void => {
			mainChannel.port2.postMessage(message);
		},
	});
	let sessionStatus: BridgePaneTelemetryWorkerSessionStatus = 'starting';
	let nextRequestSequence = 0;
	let activeControl: PendingControlOperation | null = null;
	const controlQueue: PendingControlOperation[] = [];

	mainChannel.port2.addEventListener('message', (event: MessageEvent<unknown>): void => {
		mainProducer.acceptWorkerCommand(event.data);
	});
	mainChannel.port2.start();

	const failSession = (message: string): void => {
		if (sessionStatus === 'closed') {
			return;
		}
		sessionStatus = 'failed';
		mainProducer.close();
		mainChannel.port2.close();
		commChannel.port2.close();
		const failure = new Error(message);
		activeControl?.cancelTimeout?.();
		activeControl?.reject(failure);
		activeControl = null;
		for (const operation of controlQueue.splice(0)) {
			operation.cancelTimeout?.();
			operation.reject(failure);
		}
		worker.terminate();
	};
	worker.addEventListener?.('error', (): void => failSession('Telemetry worker failed.'));
	worker.addEventListener?.('messageerror', (): void =>
		failSession('Telemetry worker returned an unreadable message.'),
	);
	worker.addEventListener?.('message', (event): void => {
		if (!(event instanceof MessageEvent) || typeof event.data !== 'object' || event.data === null) {
			return;
		}
		if ('type' in event.data && event.data.type === 'telemetry.health') {
			if ('status' in event.data && event.data.status === 'ready') {
				sessionStatus = 'active';
			} else {
				failSession('Telemetry worker reported degraded health.');
				return;
			}
			startNextControlOperation();
			return;
		}
		const decodedSnapshot = bridgeTelemetryWorkerSnapshotResultSchema.safeParse(event.data);
		if (
			decodedSnapshot.success &&
			activeControl?.kind === 'snapshot' &&
			activeControl.requestId === decodedSnapshot.data.requestId
		) {
			const completedSnapshot = activeControl;
			completeActiveControl();
			completedSnapshot.resolve(decodedSnapshot.data.snapshot);
			startNextControlOperation();
			return;
		}
		const decodedDrain = bridgeTelemetryWorkerDrainedResultSchema.safeParse(event.data);
		const decodedClose = bridgeTelemetryWorkerDrainedAndClosedResultSchema.safeParse(event.data);
		const decodedControlResult = decodedDrain.success
			? { closesSession: false, data: decodedDrain.data }
			: decodedClose.success
				? { closesSession: true, data: decodedClose.data }
				: null;
		if (
			decodedControlResult === null ||
			(activeControl?.kind !== 'drain' && activeControl?.kind !== 'drainAndClose') ||
			activeControl.requestId !== decodedControlResult.data.requestId ||
			(activeControl.kind === 'drainAndClose') !== decodedControlResult.closesSession
		) {
			return;
		}
		const completedDrain = activeControl;
		if (completedDrain === null) {
			return;
		}
		const closesSession = completedDrain.kind === 'drainAndClose';
		completeActiveControl();
		if (closesSession) {
			sessionStatus = 'closed';
			mainProducer.close();
			mainChannel.port2.close();
			commChannel.port2.close();
			worker.terminate();
		} else {
			sessionStatus = 'active';
		}
		completedDrain.resolve(decodedControlResult.data.result);
		if (!closesSession) {
			startNextControlOperation();
		}
	});

	worker.postMessage(
		{
			type: 'telemetry.bootstrap',
			bootstrap,
			mainPort: mainChannel.port1,
			commPort: commChannel.port1,
		},
		[mainChannel.port1, commChannel.port1],
	);

	return {
		telemetrySessionId: bootstrap.telemetrySessionId,
		producerPreReadyBufferMaxBytes: bootstrap.policy.producerPreReadyBufferMaxBytes,
		producerPreReadyBufferMaxSamples: bootstrap.policy.producerPreReadyBufferMaxSamples,
		mainProducer,
		commProducerPort: commChannel.port2,
		status: (): BridgePaneTelemetryWorkerSessionStatus => sessionStatus,
		replaceCommProducerPort: (): MessagePort => {
			if (
				sessionStatus !== 'active' ||
				activeControl?.kind === 'drain' ||
				activeControl?.kind === 'drainAndClose' ||
				controlQueue.some(
					(operation) => operation.kind === 'drain' || operation.kind === 'drainAndClose',
				)
			) {
				throw new Error('Telemetry worker must be active before replacing a producer.');
			}
			const replacementChannel = createMessageChannel();
			nextRequestSequence += 1;
			worker.postMessage(
				{
					type: 'telemetry.producer.replace',
					requestId: `telemetry-producer-replace-${nextRequestSequence.toString(36)}`,
					producerId: 'comm',
					producerPort: replacementChannel.port1,
				},
				[replacementChannel.port1],
			);
			return replacementChannel.port2;
		},
		snapshot: (): Promise<BridgeTelemetryWorkerSnapshot> => enqueueSnapshot(),
		drain: (): Promise<BridgeTelemetryWorkerDrainResult> => enqueueDrain('drain'),
		drainAndClose: (): Promise<BridgeTelemetryWorkerDrainResult> => enqueueDrain('drainAndClose'),
		dispose: (): void => {
			sessionStatus = 'closed';
			mainProducer.close();
			mainChannel.port2.close();
			commChannel.port2.close();
			const disposalError = new Error('Telemetry worker session was disposed.');
			activeControl?.cancelTimeout?.();
			activeControl?.reject(disposalError);
			activeControl = null;
			for (const operation of controlQueue.splice(0)) {
				operation.cancelTimeout?.();
				operation.reject(disposalError);
			}
			worker.terminate();
		},
	};

	function enqueueSnapshot(): Promise<BridgeTelemetryWorkerSnapshot> {
		const terminalError = terminalSessionError();
		if (terminalError !== null) {
			return Promise.reject(terminalError);
		}
		const existing = findControlOperation('snapshot');
		if (existing?.kind === 'snapshot') {
			return existing.promise;
		}
		nextRequestSequence += 1;
		let resolveOperation!: (snapshot: BridgeTelemetryWorkerSnapshot) => void;
		let rejectOperation!: (error: Error) => void;
		const promise = new Promise<BridgeTelemetryWorkerSnapshot>((resolve, reject): void => {
			resolveOperation = resolve;
			rejectOperation = reject;
		});
		const operation: PendingControlOperation = {
			kind: 'snapshot',
			requestId: `telemetry-snapshot-${nextRequestSequence.toString(36)}`,
			promise,
			resolve: resolveOperation,
			reject: rejectOperation,
			cancelTimeout: null,
		};
		controlQueue.push(operation);
		startNextControlOperation();
		return promise;
	}

	function enqueueDrain(
		kind: 'drain' | 'drainAndClose',
	): Promise<BridgeTelemetryWorkerDrainResult> {
		const terminalError = terminalSessionError();
		if (terminalError !== null) {
			return Promise.reject(terminalError);
		}
		const existing = findControlOperation(kind);
		if (existing !== null && existing.kind !== 'snapshot') {
			return existing.promise;
		}
		if (
			kind === 'drain' &&
			(activeControl?.kind === 'drainAndClose' ||
				controlQueue.some((operation) => operation.kind === 'drainAndClose'))
		) {
			return Promise.reject(new Error('Telemetry worker terminal drain is already queued.'));
		}
		nextRequestSequence += 1;
		let resolveDrain!: (result: BridgeTelemetryWorkerDrainResult) => void;
		let rejectDrain!: (error: Error) => void;
		const promise = new Promise<BridgeTelemetryWorkerDrainResult>((resolve, reject): void => {
			resolveDrain = resolve;
			rejectDrain = reject;
		});
		const operation: PendingControlOperation = {
			kind,
			requestId: `telemetry-drain-${nextRequestSequence.toString(36)}`,
			promise,
			resolve: resolveDrain,
			reject: rejectDrain,
			cancelTimeout: null,
		};
		controlQueue.push(operation);
		startNextControlOperation();
		return promise;
	}

	function findControlOperation(
		kind: PendingControlOperation['kind'],
	): PendingControlOperation | null {
		const queuedTail = controlQueue.at(-1);
		if (queuedTail?.kind === kind) {
			return queuedTail;
		}
		if (controlQueue.length === 0 && activeControl?.kind === kind) {
			return activeControl;
		}
		return null;
	}

	function terminalSessionError(): Error | null {
		if (sessionStatus === 'closed') {
			return new Error('Telemetry worker session is closed.');
		}
		if (sessionStatus === 'failed') {
			return new Error('Telemetry worker session has failed.');
		}
		return null;
	}

	function startNextControlOperation(): void {
		if (activeControl !== null || sessionStatus !== 'active') {
			return;
		}
		const operation = controlQueue.shift();
		if (operation === undefined) {
			return;
		}
		activeControl = operation;
		if (operation.kind !== 'snapshot') {
			sessionStatus = 'draining';
		}
		operation.cancelTimeout = scheduleDrainTimeout(
			(): void =>
				failSession(
					operation.kind === 'snapshot'
						? 'Telemetry worker snapshot acknowledgement timed out.'
						: 'Telemetry worker drain acknowledgement timed out.',
				),
			bootstrap.policy.drainTimeoutMilliseconds,
		);
		worker.postMessage(
			{
				type:
					operation.kind === 'snapshot'
						? 'telemetry.snapshot'
						: operation.kind === 'drain'
							? 'telemetry.drain'
							: 'telemetry.drainAndClose',
				requestId: operation.requestId,
			},
			[],
		);
	}

	function completeActiveControl(): void {
		activeControl?.cancelTimeout?.();
		activeControl = null;
	}
}

function defaultScheduleDrainTimeout(callback: () => void, delayMilliseconds: number): () => void {
	const timeout = globalThis.setTimeout(callback, delayMilliseconds);
	return (): void => globalThis.clearTimeout(timeout);
}
