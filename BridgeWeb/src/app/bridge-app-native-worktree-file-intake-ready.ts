import { encodeBridgeWorkerWorktreeFileIntakeReadyCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeCommWorkerBootstrapRequestSchema } from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
import { createBridgeReviewCommWorkerTransportDispatcher } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.js';

export type BridgeAppNativeWorktreeFileIntakeReadySender = (props: {
	readonly requestId: string;
	readonly generation: number;
	readonly streamId: string;
}) => Promise<boolean>;

export interface BridgeAppNativeWorktreeFileIntakeReadyTransport {
	readonly send: BridgeAppNativeWorktreeFileIntakeReadySender;
	readonly dispose: () => void;
}

export interface CreateBridgeAppNativeWorktreeFileIntakeReadyTransportProps {
	readonly timeoutMilliseconds?: number;
}

interface PendingWorktreeFileIntakeReadyRequest {
	readonly resolve: (didSend: boolean) => void;
	readonly timeoutId: ReturnType<typeof setTimeout> | null;
}

export async function sendWorktreeFileIntakeReady(props: {
	readonly generation: number;
	readonly send: BridgeAppNativeWorktreeFileIntakeReadySender;
	readonly streamId: string;
}): Promise<void> {
	const requestId = `${props.streamId}:generation-${props.generation}:intake-ready`;
	try {
		const didSend = await props.send({
			requestId,
			generation: props.generation,
			streamId: props.streamId,
		});
		if (!didSend) {
			throw new Error('Native Worktree/File intake-ready command failed');
		}
	} catch (error) {
		if (error instanceof Error) {
			throw error;
		}
		throw new Error('Native Worktree/File intake-ready command failed', { cause: error });
	}
}

export function createBridgeAppNativeWorktreeFileIntakeReadyTransport(
	options: CreateBridgeAppNativeWorktreeFileIntakeReadyTransportProps = {},
): BridgeAppNativeWorktreeFileIntakeReadyTransport {
	const pendingRequestsByRequestId = new Map<string, PendingWorktreeFileIntakeReadyRequest>();
	const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
		bootstrapRequest: bridgeAppNativeWorktreeFileCommWorkerBootstrapRequest(),
		publishWorkerMessages: (messages): void => {
			resolveWorktreeFileIntakeReadyRequests({
				messages,
				pendingRequestsByRequestId,
			});
		},
	});
	return {
		send: (sendProps): Promise<boolean> => {
			const completion = new Promise<boolean>((resolve): void => {
				const timeoutId =
					options.timeoutMilliseconds === undefined
						? null
						: setTimeout((): void => {
								resolveWorktreeFileIntakeReadyRequest({
									didSend: false,
									pendingRequestsByRequestId,
									requestId: sendProps.requestId,
								});
							}, options.timeoutMilliseconds);
				pendingRequestsByRequestId.set(sendProps.requestId, { resolve, timeoutId });
			});
			try {
				dispatcher.dispatch(
					encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
						requestId: sendProps.requestId,
						epoch: sendProps.generation,
						generation: sendProps.generation,
						streamId: sendProps.streamId,
					}),
				);
			} catch {
				resolveWorktreeFileIntakeReadyRequest({
					didSend: false,
					pendingRequestsByRequestId,
					requestId: sendProps.requestId,
				});
			}
			return completion;
		},
		dispose: (): void => {
			dispatcher.dispose();
			resolveAllWorktreeFileIntakeReadyRequests({
				didSend: false,
				pendingRequestsByRequestId,
			});
		},
	};
}

function bridgeAppNativeWorktreeFileCommWorkerBootstrapRequest(): BridgeCommWorkerBootstrapRequest {
	return bridgeCommWorkerBootstrapRequestSchema.parse({
		schemaVersion: 1,
		method: 'bridgeCommWorker.bootstrap',
		requestId: 'worktree-file-intake-ready-worker-bootstrap',
		runtime: {
			bridgeDemandRank: {
				lane: 'selected',
				priority: 0,
			},
			budget: bridgeWorkerPierreRenderPolicy.interactiveRenderBudget,
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
		},
	});
}

function resolveWorktreeFileIntakeReadyRequests(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileIntakeReadyRequest>;
}): void {
	for (const message of props.messages) {
		if (message.kind !== 'health' || message.requestId === undefined) {
			continue;
		}
		resolveWorktreeFileIntakeReadyRequest({
			didSend: message.status === 'ready',
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId: message.requestId,
		});
	}
}

function resolveWorktreeFileIntakeReadyRequest(props: {
	readonly didSend: boolean;
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileIntakeReadyRequest>;
	readonly requestId: string;
}): void {
	const pendingRequest = props.pendingRequestsByRequestId.get(props.requestId);
	if (pendingRequest === undefined) {
		return;
	}
	props.pendingRequestsByRequestId.delete(props.requestId);
	if (pendingRequest.timeoutId !== null) {
		clearTimeout(pendingRequest.timeoutId);
	}
	pendingRequest.resolve(props.didSend);
}

function resolveAllWorktreeFileIntakeReadyRequests(props: {
	readonly didSend: boolean;
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileIntakeReadyRequest>;
}): void {
	for (const [requestId] of props.pendingRequestsByRequestId) {
		resolveWorktreeFileIntakeReadyRequest({
			didSend: props.didSend,
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId,
		});
	}
}
