import type { BridgeWorkerMainToServerCommand } from './bridge-worker-contracts.js';

type BridgeWorkerRpcCommand = BridgeWorkerMainToServerCommand['command'];
type BridgeWorkerRpcRequestState = 'pending' | 'acked' | 'failed' | 'timed_out' | 'superseded';

const DEFAULT_TERMINAL_HISTORY_CAPACITY_PER_SURFACE = 128;

export type BridgeWorkerRpcSurface = 'fileView' | 'pane' | 'review';

export interface BridgeWorkerRpcRollbackMetadata {
	readonly kind: string;
	readonly previousSelectedItemId?: string;
}

export interface BridgeWorkerRpcRequestEnvelope {
	readonly requestId: string;
	readonly command: BridgeWorkerRpcCommand;
	readonly surface: BridgeWorkerRpcSurface;
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
	readonly surface?: BridgeWorkerRpcSurface;
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

export interface RollbackBridgeWorkerRpcRequestProps {
	readonly requestId: string;
}

export interface BridgeWorkerRpcLifecycleStore {
	readonly dispose: () => void;
	readonly getSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly getServerSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly subscribe: (listener: () => void) => () => void;
	readonly startRequest: (props: StartBridgeWorkerRpcRequestProps) => void;
	readonly ackRequest: (props: AckBridgeWorkerRpcRequestProps) => void;
	readonly failRequest: (props: FailBridgeWorkerRpcRequestProps) => void;
	readonly rollbackRequest: (props: RollbackBridgeWorkerRpcRequestProps) => void;
	readonly timeoutRequest: (props: TimeoutBridgeWorkerRpcRequestProps) => void;
}

export interface CreateBridgeWorkerRpcLifecycleStoreProps {
	readonly terminalHistoryCapacityPerSurface?: number;
}

export function createBridgeWorkerRpcLifecycleStore(
	options: CreateBridgeWorkerRpcLifecycleStoreProps = {},
): BridgeWorkerRpcLifecycleStore {
	const terminalHistoryCapacityPerSurface =
		options.terminalHistoryCapacityPerSurface ?? DEFAULT_TERMINAL_HISTORY_CAPACITY_PER_SURFACE;
	if (
		!Number.isSafeInteger(terminalHistoryCapacityPerSurface) ||
		terminalHistoryCapacityPerSurface <= 0
	) {
		throw new Error(
			'Bridge worker RPC lifecycle store requires a positive safe terminal history capacity.',
		);
	}
	let snapshot: BridgeWorkerRpcLifecycleSnapshot = { requestsById: {} };
	const listeners = new Set<() => void>();
	const terminalRequestIdsBySurface: Record<BridgeWorkerRpcSurface, string[]> = {
		fileView: [],
		pane: [],
		review: [],
	};
	let isDisposed = false;

	const publish = (nextRequest: BridgeWorkerRpcRequestEnvelope): void => {
		const nextRequestsById = {
			...snapshot.requestsById,
			[nextRequest.requestId]: nextRequest,
		};
		if (nextRequest.state !== 'pending') {
			const terminalRequestIds = terminalRequestIdsBySurface[nextRequest.surface];
			const existingTerminalIndex = terminalRequestIds.indexOf(nextRequest.requestId);
			if (existingTerminalIndex >= 0) terminalRequestIds.splice(existingTerminalIndex, 1);
			terminalRequestIds.push(nextRequest.requestId);
			while (terminalRequestIds.length > terminalHistoryCapacityPerSurface) {
				const oldestTerminalRequestId = terminalRequestIds.shift();
				if (oldestTerminalRequestId !== undefined) delete nextRequestsById[oldestTerminalRequestId];
			}
		}
		snapshot = {
			requestsById: nextRequestsById,
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
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			listeners.clear();
			terminalRequestIdsBySurface.fileView.length = 0;
			terminalRequestIdsBySurface.pane.length = 0;
			terminalRequestIdsBySurface.review.length = 0;
			snapshot = { requestsById: {} };
		},
		getSnapshot: (): BridgeWorkerRpcLifecycleSnapshot => snapshot,
		getServerSnapshot: (): BridgeWorkerRpcLifecycleSnapshot => snapshot,
		subscribe: (listener: () => void): (() => void) => {
			if (isDisposed) return (): void => {};
			listeners.add(listener);
			return (): void => {
				listeners.delete(listener);
			};
		},
		startRequest: (props: StartBridgeWorkerRpcRequestProps): void => {
			if (isDisposed) return;
			if (snapshot.requestsById[props.requestId] !== undefined) {
				throw new Error(`Bridge worker RPC request ${props.requestId} is already tracked.`);
			}
			const request: BridgeWorkerRpcRequestEnvelope = {
				requestId: props.requestId,
				command: props.command,
				surface: props.surface ?? 'pane',
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
			if (isDisposed) return;
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'acked',
				acknowledgedAtSequence: props.acknowledgedAtSequence,
			});
		},
		failRequest: (props: FailBridgeWorkerRpcRequestProps): void => {
			if (isDisposed) return;
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'failed',
				reason: props.reason,
			});
		},
		rollbackRequest: (props: RollbackBridgeWorkerRpcRequestProps): void => {
			if (isDisposed) return;
			const existing = snapshot.requestsById[props.requestId];
			if (existing === undefined) return;
			const terminalRequestIds = terminalRequestIdsBySurface[existing.surface];
			const terminalIndex = terminalRequestIds.indexOf(props.requestId);
			if (terminalIndex >= 0) terminalRequestIds.splice(terminalIndex, 1);
			const nextRequestsById = { ...snapshot.requestsById };
			delete nextRequestsById[props.requestId];
			snapshot = { requestsById: nextRequestsById };
			for (const listener of listeners) listener();
		},
		timeoutRequest: (props: TimeoutBridgeWorkerRpcRequestProps): void => {
			if (isDisposed) return;
			const existing = readRequest(props.requestId);
			publish({
				...existing,
				state: 'timed_out',
			});
		},
	};
}
