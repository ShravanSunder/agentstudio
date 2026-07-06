import type { BridgeWorkerMainToServerCommand } from './bridge-worker-contracts.js';

type BridgeWorkerRpcCommand = BridgeWorkerMainToServerCommand['command'];
type BridgeWorkerRpcRequestState = 'pending' | 'acked' | 'failed' | 'timed_out' | 'superseded';

export interface BridgeWorkerRpcRollbackMetadata {
	readonly kind: string;
	readonly previousSelectedItemId?: string;
}

export interface BridgeWorkerRpcRequestEnvelope {
	readonly requestId: string;
	readonly command: BridgeWorkerRpcCommand;
	readonly state: BridgeWorkerRpcRequestState;
	readonly optimisticIntentId?: string;
	readonly rollbackMetadata?: BridgeWorkerRpcRollbackMetadata;
	readonly acknowledgedAtSequence?: number;
	readonly reason?: string;
}

export interface BridgeWorkerRpcLifecycleSnapshot {
	readonly requestsById: Readonly<Record<string, BridgeWorkerRpcRequestEnvelope>>;
}

export interface StartBridgeWorkerRpcRequestProps {
	readonly requestId: string;
	readonly command: BridgeWorkerRpcCommand;
	readonly optimisticIntentId?: string;
	readonly rollbackMetadata?: BridgeWorkerRpcRollbackMetadata;
}

export interface AckBridgeWorkerRpcRequestProps {
	readonly requestId: string;
	readonly acknowledgedAtSequence: number;
}

export interface FailBridgeWorkerRpcRequestProps {
	readonly requestId: string;
	readonly reason: string;
}

export interface TimeoutBridgeWorkerRpcRequestProps {
	readonly requestId: string;
}

export interface BridgeWorkerRpcLifecycleStore {
	readonly getSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly getServerSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly subscribe: (listener: () => void) => () => void;
	readonly startRequest: (props: StartBridgeWorkerRpcRequestProps) => void;
	readonly ackRequest: (props: AckBridgeWorkerRpcRequestProps) => void;
	readonly failRequest: (props: FailBridgeWorkerRpcRequestProps) => void;
	readonly timeoutRequest: (props: TimeoutBridgeWorkerRpcRequestProps) => void;
}

export function createBridgeWorkerRpcLifecycleStore(): BridgeWorkerRpcLifecycleStore {
	let snapshot: BridgeWorkerRpcLifecycleSnapshot = { requestsById: {} };
	const listeners = new Set<() => void>();

	const publish = (nextRequest: BridgeWorkerRpcRequestEnvelope): void => {
		snapshot = {
			requestsById: {
				...snapshot.requestsById,
				[nextRequest.requestId]: nextRequest,
			},
		};
		for (const listener of listeners) {
			listener();
		}
	};

	const readRequest = (requestId: string): BridgeWorkerRpcRequestEnvelope => {
		const existing = snapshot.requestsById[requestId];
		if (existing === undefined) {
			throw new Error(`Bridge worker RPC request ${requestId} is not tracked.`);
		}
		return existing;
	};

	return {
		getSnapshot: (): BridgeWorkerRpcLifecycleSnapshot => snapshot,
		getServerSnapshot: (): BridgeWorkerRpcLifecycleSnapshot => snapshot,
		subscribe: (listener: () => void): (() => void) => {
			listeners.add(listener);
			return (): void => {
				listeners.delete(listener);
			};
		},
		startRequest: (props: StartBridgeWorkerRpcRequestProps): void => {
			const request: BridgeWorkerRpcRequestEnvelope = {
				requestId: props.requestId,
				command: props.command,
				state: 'pending',
				...(props.optimisticIntentId === undefined
					? {}
					: { optimisticIntentId: props.optimisticIntentId }),
				...(props.rollbackMetadata === undefined
					? {}
					: { rollbackMetadata: props.rollbackMetadata }),
			};
			publish({
				...request,
			});
		},
		ackRequest: (props: AckBridgeWorkerRpcRequestProps): void => {
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'acked',
				acknowledgedAtSequence: props.acknowledgedAtSequence,
			});
		},
		failRequest: (props: FailBridgeWorkerRpcRequestProps): void => {
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'failed',
				reason: props.reason,
			});
		},
		timeoutRequest: (props: TimeoutBridgeWorkerRpcRequestProps): void => {
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'timed_out',
			});
		},
	};
}
