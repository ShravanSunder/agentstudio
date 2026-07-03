import { z } from 'zod';

import {
	bridgePierreWorkerContentDescriptorSource,
	writeBridgePierreWorkerContentFetchProbeSnapshotToDataset,
} from './bridge-pierre-worker-content-descriptor.js';

export interface BridgePierreWorkerDiagnosticDataset {
	bridgePierreWorkerDiagnosticBootstrapState?: string;
	bridgePierreWorkerDiagnosticErrorCount?: string;
	bridgePierreWorkerDiagnosticDiffSuccessCount?: string;
	bridgePierreWorkerDiagnosticFileSuccessCount?: string;
	bridgePierreWorkerDiagnosticForwardedMessageCount?: string;
	bridgePierreWorkerDiagnosticInitializeRequestIdState?: string;
	bridgePierreWorkerDiagnosticInitializeSuccessCount?: string;
	bridgePierreWorkerDiagnosticLastErrorKind?: string;
	bridgePierreWorkerDiagnosticLastForwardResult?: string;
	bridgePierreWorkerDiagnosticLastMessageType?: string;
	bridgePierreWorkerDiagnosticLastRequestType?: string;
	bridgePierreWorkerDiagnosticLastFileRequestCacheKey?: string;
	bridgePierreWorkerDiagnosticLastFileSuccessCacheKey?: string;
	bridgePierreWorkerDiagnosticLastSuccessMatchesInitializeRequest?: string;
	bridgePierreWorkerDiagnosticLastSuccessIdPrefix?: string;
	bridgePierreWorkerDiagnosticLastSuccessIdState?: string;
	bridgePierreWorkerDiagnosticLastSuccessRequestType?: string;
	bridgePierreWorkerDiagnosticSuccessCount?: string;
	bridgePierreWorkerContentFetchProbeFailureCount?: string;
	bridgePierreWorkerContentFetchProbeFailureReason?: string;
	bridgePierreWorkerContentFetchProbeResult?: string;
	bridgePierreWorkerContentFetchProbeSuccessCount?: string;
}

export interface BridgePierreWorkerDiagnosticDatasetTarget {
	readonly dataset: BridgePierreWorkerDiagnosticDataset;
}

const bridgePierreWorkerDiagnosticMessageSchema = z
	.object({
		type: z.string().min(1).max(80),
		phase: z.string().min(1).max(80).optional(),
		requestType: z.string().min(1).max(80).optional(),
	})
	.passthrough();
const bridgePierreWorkerDiagnosticInitializeRequestSchema = z
	.object({
		id: z.string().min(1).max(80),
		type: z.literal('initialize'),
	})
	.passthrough();
const bridgePierreWorkerDiagnosticFileRequestSchema = z
	.object({
		id: z.string().min(1).max(80),
		type: z.literal('file'),
		file: z
			.object({
				cacheKey: z.string().min(1).max(240).optional(),
			})
			.passthrough(),
	})
	.passthrough();
const bridgePierreWorkerDiagnosticInitializeRequestIdByWorker = new WeakMap<Worker, string>();
const bridgePierreWorkerDiagnosticFileRequestByWorker = new WeakMap<
	Worker,
	Map<string, { readonly cacheKey: string }>
>();
const bridgePierreWorkerDiagnosticEventListenerWrappedWorkers = new WeakSet<Worker>();
const bridgePierreWorkerDiagnosticPostMessageWrappedWorkers = new WeakSet<Worker>();

export function wrapBridgePierreWorkerSourceWithDiagnostics(workerSource: string): string {
	return `${bridgePierreWorkerBootstrapDiagnosticSource}\n${bridgePierreWorkerContentDescriptorSource}\n${workerSource}`;
}

export function attachBridgePierreWorkerDiagnostics(
	worker: Worker,
	rootElement: BridgePierreWorkerDiagnosticDatasetTarget = document.documentElement,
): () => void {
	const handleWorkerError = (): void => {
		incrementBridgePierreWorkerDiagnosticError({
			rootElement,
			errorKind: 'worker-error',
		});
	};

	if (!bridgePierreWorkerDiagnosticEventListenerWrappedWorkers.has(worker)) {
		bridgePierreWorkerDiagnosticEventListenerWrappedWorkers.add(worker);
		const originalAddEventListener = worker.addEventListener.bind(worker);
		const originalRemoveEventListener = worker.removeEventListener.bind(worker);
		const wrappedMessageListenerByOriginal = new WeakMap<
			EventListenerOrEventListenerObject,
			EventListenerOrEventListenerObject
		>();

		function wrappedAddEventListener<KEventName extends keyof WorkerEventMap>(
			type: KEventName,
			listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
			options?: boolean | AddEventListenerOptions,
		): void;
		function wrappedAddEventListener(
			type: string,
			listener: EventListenerOrEventListenerObject | null,
			options?: boolean | AddEventListenerOptions,
		): void;
		function wrappedAddEventListener(
			type: string,
			listener: EventListenerOrEventListenerObject | null,
			options?: boolean | AddEventListenerOptions,
		): void {
			if (listener === null) {
				return;
			}
			if (type !== 'message') {
				originalAddEventListener(type, listener, options);
				return;
			}

			const wrappedListener = createBridgePierreDiagnosticMessageListener({
				worker,
				rootElement,
				listener,
			});
			wrappedMessageListenerByOriginal.set(listener, wrappedListener);
			originalAddEventListener(type, wrappedListener, options);
		}

		function wrappedRemoveEventListener<KEventName extends keyof WorkerEventMap>(
			type: KEventName,
			listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
			options?: boolean | EventListenerOptions,
		): void;
		function wrappedRemoveEventListener(
			type: string,
			listener: EventListenerOrEventListenerObject | null,
			options?: boolean | EventListenerOptions,
		): void;
		function wrappedRemoveEventListener(
			type: string,
			listener: EventListenerOrEventListenerObject | null,
			options?: boolean | EventListenerOptions,
		): void {
			if (listener === null) {
				return;
			}
			if (type !== 'message') {
				originalRemoveEventListener(type, listener, options);
				return;
			}

			originalRemoveEventListener(
				type,
				wrappedMessageListenerByOriginal.get(listener) ?? listener,
				options,
			);
		}

		worker.addEventListener = wrappedAddEventListener;
		worker.removeEventListener = wrappedRemoveEventListener;
	}

	worker.addEventListener('error', handleWorkerError);

	return (): void => {
		worker.removeEventListener('error', handleWorkerError);
	};
}

export function attachBridgePierreWorkerRequestDiagnostics(
	worker: Worker,
	rootElement: BridgePierreWorkerDiagnosticDatasetTarget = document.documentElement,
): void {
	if (bridgePierreWorkerDiagnosticPostMessageWrappedWorkers.has(worker)) {
		return;
	}
	bridgePierreWorkerDiagnosticPostMessageWrappedWorkers.add(worker);
	const originalPostMessage = worker.postMessage.bind(worker);

	function wrappedPostMessage(message: unknown, transfer: Transferable[]): void;
	function wrappedPostMessage(message: unknown, options?: StructuredSerializeOptions): void;
	function wrappedPostMessage(
		message: unknown,
		transferOrOptions?: StructuredSerializeOptions | Transferable[],
	): void {
		recordBridgePierreWorkerRequestDiagnostic({
			worker,
			rootElement,
			messageData: message,
		});
		if (transferOrOptions === undefined) {
			originalPostMessage(message);
			return;
		}
		if (Array.isArray(transferOrOptions)) {
			originalPostMessage(message, transferOrOptions);
			return;
		}
		originalPostMessage(message, transferOrOptions);
	}

	worker.postMessage = wrappedPostMessage;
}

function createBridgePierreDiagnosticMessageListener(props: {
	readonly worker: Worker;
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly listener: EventListenerOrEventListenerObject;
}): EventListenerOrEventListenerObject {
	return function bridgePierreDiagnosticMessageListener(this: Worker, event: Event): void {
		recordBridgePierreWorkerMessageDiagnostic({
			worker: props.worker,
			rootElement: props.rootElement,
			messageData: event instanceof MessageEvent ? event.data : Reflect.get(event, 'data'),
		});

		try {
			if (typeof props.listener === 'function') {
				props.listener.call(this, event);
			} else {
				props.listener.handleEvent(event);
			}
			recordBridgePierreWorkerMessageForwardDiagnostic({
				rootElement: props.rootElement,
				result: 'ok',
			});
		} catch (error) {
			recordBridgePierreWorkerMessageForwardDiagnostic({
				rootElement: props.rootElement,
				result: error instanceof Error ? error.name : 'thrown',
			});
			throw error;
		}
	};
}

function recordBridgePierreWorkerMessageDiagnostic(props: {
	readonly worker: Worker;
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly messageData: unknown;
}): void {
	const parsedMessage = bridgePierreWorkerDiagnosticMessageSchema.safeParse(props.messageData);
	if (!parsedMessage.success) {
		return;
	}

	const dataset = props.rootElement.dataset;
	const messageType = bridgePierreWorkerDiagnosticToken(parsedMessage.data.type);
	if (messageType !== null) {
		dataset.bridgePierreWorkerDiagnosticLastMessageType = messageType;
	}

	const requestType = bridgePierreWorkerDiagnosticToken(parsedMessage.data.requestType);
	if (requestType !== null) {
		dataset.bridgePierreWorkerDiagnosticLastRequestType = requestType;
	}

	if (messageType === 'success') {
		recordBridgePierreWorkerSuccessDiagnostic({
			worker: props.worker,
			rootElement: props.rootElement,
			requestType,
			responseId: Reflect.get(parsedMessage.data, 'id'),
		});
	}

	if (parsedMessage.data.type !== 'bridge-diagnostic') {
		return;
	}

	if (parsedMessage.data.requestType === 'bridge-worker-bootstrap') {
		const phase = bridgePierreWorkerDiagnosticToken(parsedMessage.data.phase);
		if (phase !== null) {
			dataset.bridgePierreWorkerDiagnosticBootstrapState = phase;
		}
		return;
	}

	if (parsedMessage.data.requestType === 'bridge-worker-content-fetch-probe') {
		const result = bridgePierreWorkerDiagnosticToken(Reflect.get(parsedMessage.data, 'result'));
		const failureReason =
			bridgePierreWorkerDiagnosticToken(Reflect.get(parsedMessage.data, 'failureReason')) ?? '';
		writeBridgePierreWorkerContentFetchProbeSnapshotToDataset({
			rootElement: props.rootElement,
			result: result === 'success' ? 'success' : 'failed',
			failureReason,
		});
		return;
	}

	if (
		parsedMessage.data.requestType === 'bridge-worker-error' ||
		parsedMessage.data.requestType === 'bridge-worker-unhandled-rejection'
	) {
		incrementBridgePierreWorkerDiagnosticError({
			rootElement: props.rootElement,
			errorKind: parsedMessage.data.requestType,
		});
	}
}

function recordBridgePierreWorkerRequestDiagnostic(props: {
	readonly worker: Worker;
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly messageData: unknown;
}): void {
	const parsedInitializeMessage = bridgePierreWorkerDiagnosticInitializeRequestSchema.safeParse(
		props.messageData,
	);
	if (parsedInitializeMessage.success) {
		bridgePierreWorkerDiagnosticInitializeRequestIdByWorker.set(
			props.worker,
			parsedInitializeMessage.data.id,
		);
		props.rootElement.dataset.bridgePierreWorkerDiagnosticInitializeRequestIdState = 'present';
		return;
	}

	const parsedFileMessage = bridgePierreWorkerDiagnosticFileRequestSchema.safeParse(
		props.messageData,
	);
	if (!parsedFileMessage.success || parsedFileMessage.data.file.cacheKey === undefined) {
		return;
	}

	let fileRequestById = bridgePierreWorkerDiagnosticFileRequestByWorker.get(props.worker);
	if (fileRequestById === undefined) {
		fileRequestById = new Map();
		bridgePierreWorkerDiagnosticFileRequestByWorker.set(props.worker, fileRequestById);
	}
	fileRequestById.set(parsedFileMessage.data.id, {
		cacheKey: parsedFileMessage.data.file.cacheKey,
	});
	props.rootElement.dataset.bridgePierreWorkerDiagnosticLastFileRequestCacheKey =
		parsedFileMessage.data.file.cacheKey;
}

function recordBridgePierreWorkerMessageForwardDiagnostic(props: {
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly result: string;
}): void {
	const dataset = props.rootElement.dataset;
	incrementBridgePierreWorkerDiagnosticCounter({
		dataset,
		key: 'bridgePierreWorkerDiagnosticForwardedMessageCount',
	});
	dataset.bridgePierreWorkerDiagnosticLastForwardResult =
		bridgePierreWorkerDiagnosticToken(props.result) ?? 'unknown';
}

function recordBridgePierreWorkerSuccessDiagnostic(props: {
	readonly worker: Worker;
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly responseId: unknown;
	readonly requestType: string | null;
}): void {
	const dataset = props.rootElement.dataset;
	const requestType = props.requestType ?? 'unknown';
	const idDiagnostic = bridgePierreWorkerSuccessIdDiagnostic(props.responseId);
	dataset.bridgePierreWorkerDiagnosticLastSuccessRequestType = requestType;
	dataset.bridgePierreWorkerDiagnosticLastSuccessIdState = idDiagnostic.state;
	dataset.bridgePierreWorkerDiagnosticLastSuccessIdPrefix = idDiagnostic.prefix;
	dataset.bridgePierreWorkerDiagnosticLastSuccessMatchesInitializeRequest =
		bridgePierreWorkerInitializeRequestMatchDiagnostic({
			worker: props.worker,
			requestType,
			responseId: props.responseId,
		});
	incrementBridgePierreWorkerDiagnosticCounter({
		dataset,
		key: 'bridgePierreWorkerDiagnosticSuccessCount',
	});
	initializeBridgePierreWorkerDiagnosticSuccessCounters(dataset);

	if (requestType === 'initialize') {
		incrementBridgePierreWorkerDiagnosticCounter({
			dataset,
			key: 'bridgePierreWorkerDiagnosticInitializeSuccessCount',
		});
		return;
	}

	if (requestType === 'diff') {
		incrementBridgePierreWorkerDiagnosticCounter({
			dataset,
			key: 'bridgePierreWorkerDiagnosticDiffSuccessCount',
		});
		return;
	}

	if (requestType === 'file') {
		const fileRequest =
			typeof props.responseId === 'string'
				? bridgePierreWorkerDiagnosticFileRequestByWorker.get(props.worker)?.get(props.responseId)
				: undefined;
		if (fileRequest !== undefined) {
			dataset.bridgePierreWorkerDiagnosticLastFileSuccessCacheKey = fileRequest.cacheKey;
		}
		incrementBridgePierreWorkerDiagnosticCounter({
			dataset,
			key: 'bridgePierreWorkerDiagnosticFileSuccessCount',
		});
	}
}

function bridgePierreWorkerInitializeRequestMatchDiagnostic(props: {
	readonly worker: Worker;
	readonly requestType: string;
	readonly responseId: unknown;
}): string {
	if (props.requestType !== 'initialize') {
		return 'not-initialize';
	}
	if (typeof props.responseId !== 'string' || props.responseId.length === 0) {
		return 'invalid';
	}
	const lastInitializeRequestId = bridgePierreWorkerDiagnosticInitializeRequestIdByWorker.get(
		props.worker,
	);
	if (lastInitializeRequestId === undefined) {
		return 'unknown';
	}
	return lastInitializeRequestId === props.responseId ? 'yes' : 'no';
}

function bridgePierreWorkerSuccessIdDiagnostic(responseId: unknown): {
	readonly state: 'invalid' | 'missing' | 'present';
	readonly prefix: string;
} {
	if (responseId === null || responseId === undefined) {
		return { state: 'missing', prefix: 'none' };
	}
	if (typeof responseId !== 'string' || responseId.length === 0) {
		return { state: 'invalid', prefix: 'none' };
	}

	const prefixMatch = /^[A-Za-z]+/u.exec(responseId);
	const prefix =
		prefixMatch === null ? 'opaque' : bridgePierreWorkerDiagnosticToken(prefixMatch[0]);
	return {
		state: 'present',
		prefix: prefix ?? 'opaque',
	};
}

function initializeBridgePierreWorkerDiagnosticSuccessCounters(
	dataset: BridgePierreWorkerDiagnosticDataset,
): void {
	dataset.bridgePierreWorkerDiagnosticInitializeSuccessCount ??= '0';
	dataset.bridgePierreWorkerDiagnosticDiffSuccessCount ??= '0';
	dataset.bridgePierreWorkerDiagnosticFileSuccessCount ??= '0';
}

function incrementBridgePierreWorkerDiagnosticError(props: {
	readonly rootElement: BridgePierreWorkerDiagnosticDatasetTarget;
	readonly errorKind: string;
}): void {
	const dataset = props.rootElement.dataset;
	incrementBridgePierreWorkerDiagnosticCounter({
		dataset,
		key: 'bridgePierreWorkerDiagnosticErrorCount',
	});
	dataset.bridgePierreWorkerDiagnosticLastErrorKind =
		bridgePierreWorkerDiagnosticToken(props.errorKind) ?? 'worker-error';
}

function incrementBridgePierreWorkerDiagnosticCounter(props: {
	readonly dataset: BridgePierreWorkerDiagnosticDataset;
	readonly key: keyof BridgePierreWorkerDiagnosticDataset;
}): void {
	const previousCount = Number.parseInt(props.dataset[props.key] ?? '0', 10);
	const nextCount = Number.isFinite(previousCount) ? previousCount + 1 : 1;
	props.dataset[props.key] = String(nextCount);
}

function bridgePierreWorkerDiagnosticToken(value: unknown): string | null {
	if (typeof value !== 'string' || value.length === 0) {
		return null;
	}
	const normalizedValue = value.replace(/[^A-Za-z0-9_.-]/gu, '_').slice(0, 64);
	return normalizedValue.length > 0 ? normalizedValue : null;
}

const bridgePierreWorkerBootstrapDiagnosticSource = `
;(() => {
  const bridgePostDiagnostic = (payload) => {
    try {
      self.postMessage({ type: 'bridge-diagnostic', ...payload });
    } catch {}
  };
  setTimeout(() => {
    bridgePostDiagnostic({
      requestType: 'bridge-worker-bootstrap',
      phase: 'started',
    });
  }, 0);
  self.addEventListener('error', () => {
    bridgePostDiagnostic({
      requestType: 'bridge-worker-error',
      phase: 'error',
    });
  });
  self.addEventListener('unhandledrejection', () => {
    bridgePostDiagnostic({
      requestType: 'bridge-worker-unhandled-rejection',
      phase: 'unhandledrejection',
    });
  });
})();
`.trim();
