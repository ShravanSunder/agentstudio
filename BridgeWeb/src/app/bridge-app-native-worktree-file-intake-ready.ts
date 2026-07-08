import {
	encodeBridgeWorkerWorktreeFileIntakeReadyCommand,
	encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand,
	encodeBridgeWorkerWorktreeFileRequestDescriptorCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeCommWorkerBootstrapRequestSchema } from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
import type {
	WorktreeFileDescriptorRequest,
	WorktreeFileSurfaceOpenSourceOutcome,
	WorktreeFileSurfaceSourceSpec,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { createBridgeReviewCommWorkerTransportDispatcher } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.js';

export type BridgeAppNativeWorktreeFileIntakeReadySender = (props: {
	readonly requestId: string;
	readonly generation: number;
	readonly streamId: string;
}) => Promise<boolean>;

export type BridgeAppNativeWorktreeFileOpenSourceStreamSender = (props: {
	readonly requestId: string;
	readonly sourceSpec: WorktreeFileSurfaceSourceSpec;
}) => Promise<WorktreeFileSurfaceOpenSourceOutcome>;

export type BridgeAppNativeWorktreeFileRequestDescriptorSender = (props: {
	readonly request: WorktreeFileDescriptorRequest;
	readonly requestId: string;
}) => Promise<void>;

export interface BridgeAppNativeWorktreeFileIntakeReadyTransport {
	readonly send: BridgeAppNativeWorktreeFileIntakeReadySender;
	readonly dispose: () => void;
}

export interface BridgeAppNativeWorktreeFileWorkerRpcTransport {
	readonly sendIntakeReady: BridgeAppNativeWorktreeFileIntakeReadySender;
	readonly sendOpenSourceStream: BridgeAppNativeWorktreeFileOpenSourceStreamSender;
	readonly sendRequestDescriptor: BridgeAppNativeWorktreeFileRequestDescriptorSender;
	readonly dispose: () => void;
}

export interface CreateBridgeAppNativeWorktreeFileIntakeReadyTransportProps {
	readonly timeoutMilliseconds?: number;
}

type PendingWorktreeFileWorkerRpcRequest =
	| {
			readonly kind: 'intakeReady';
			readonly resolve: (didSend: boolean) => void;
			readonly reject: null;
			readonly timeoutId: ReturnType<typeof setTimeout> | null;
	  }
	| {
			readonly kind: 'openSourceStream';
			readonly resolve: (outcome: WorktreeFileSurfaceOpenSourceOutcome) => void;
			readonly reject: (error: Error) => void;
			readonly timeoutId: ReturnType<typeof setTimeout> | null;
	  }
	| {
			readonly kind: 'requestDescriptor';
			readonly resolve: () => void;
			readonly reject: (error: Error) => void;
			readonly timeoutId: ReturnType<typeof setTimeout> | null;
	  };

interface WorktreeFileWorkerRpcPendingMapProps {
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileWorkerRpcRequest>;
}

interface WorktreeFileWorkerRpcEpochTrackerProps {
	readonly recordEpoch: (epoch: number) => number;
}

interface WorktreeFileWorkerRpcRequestProps extends WorktreeFileWorkerRpcPendingMapProps {
	readonly requestId: string;
}

interface WorktreeFileWorkerRpcRejectProps extends WorktreeFileWorkerRpcRequestProps {
	readonly error: Error;
}

interface WorktreeFileWorkerRpcOpenResolveProps
	extends WorktreeFileWorkerRpcRequestProps, WorktreeFileWorkerRpcEpochTrackerProps {
	readonly outcome: WorktreeFileSurfaceOpenSourceOutcome;
}

interface WorktreeFileWorkerRpcDescriptorResolveProps extends WorktreeFileWorkerRpcRequestProps {}

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
	const workerRpcTransport = createBridgeAppNativeWorktreeFileWorkerRpcTransport(options);
	return {
		send: workerRpcTransport.sendIntakeReady,
		dispose: workerRpcTransport.dispose,
	};
}

export function createBridgeAppNativeWorktreeFileWorkerRpcTransport(
	options: CreateBridgeAppNativeWorktreeFileIntakeReadyTransportProps = {},
): BridgeAppNativeWorktreeFileWorkerRpcTransport {
	const pendingRequestsByRequestId = new Map<string, PendingWorktreeFileWorkerRpcRequest>();
	let latestWorkerRpcEpoch = 0;
	const recordEpoch = (epoch: number): number => {
		latestWorkerRpcEpoch = Math.max(latestWorkerRpcEpoch, epoch);
		return latestWorkerRpcEpoch;
	};
	const reserveNextEpoch = (): number => {
		latestWorkerRpcEpoch += 1;
		return latestWorkerRpcEpoch;
	};
	const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
		bootstrapRequest: bridgeAppNativeWorktreeFileCommWorkerBootstrapRequest(),
		publishWorkerMessages: (messages): void => {
			resolveWorktreeFileWorkerRpcRequests({
				messages,
				pendingRequestsByRequestId,
				recordEpoch,
			});
		},
	});
	return {
		sendIntakeReady: (sendProps): Promise<boolean> => {
			const completion = new Promise<boolean>((resolve): void => {
				pendingRequestsByRequestId.set(sendProps.requestId, {
					kind: 'intakeReady',
					resolve,
					reject: null,
					timeoutId: createWorktreeFileWorkerRpcTimeout({
						onTimeout: (): void => {
							resolveWorktreeFileIntakeReadyRequest({
								didSend: false,
								pendingRequestsByRequestId,
								requestId: sendProps.requestId,
							});
						},
						timeoutMilliseconds: options.timeoutMilliseconds,
					}),
				});
			});
			try {
				const commandEpoch = recordEpoch(sendProps.generation);
				dispatcher.dispatch(
					encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
						requestId: sendProps.requestId,
						epoch: commandEpoch,
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
		sendOpenSourceStream: (sendProps): Promise<WorktreeFileSurfaceOpenSourceOutcome> => {
			const completion = new Promise<WorktreeFileSurfaceOpenSourceOutcome>(
				(resolve, reject): void => {
					pendingRequestsByRequestId.set(sendProps.requestId, {
						kind: 'openSourceStream',
						resolve,
						reject,
						timeoutId: createWorktreeFileWorkerRpcTimeout({
							onTimeout: (): void => {
								rejectWorktreeFileWorkerRpcRequest({
									error: new Error('Native Worktree/File open stream timed out'),
									pendingRequestsByRequestId,
									requestId: sendProps.requestId,
								});
							},
							timeoutMilliseconds: options.timeoutMilliseconds,
						}),
					});
				},
			);
			try {
				const commandEpoch = reserveNextEpoch();
				dispatcher.dispatch(
					encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
						requestId: sendProps.requestId,
						epoch: commandEpoch,
						sourceSpec: sendProps.sourceSpec,
					}),
				);
			} catch (error) {
				rejectWorktreeFileWorkerRpcRequest({
					error:
						error instanceof Error ? error : new Error('Native Worktree/File open stream failed'),
					pendingRequestsByRequestId,
					requestId: sendProps.requestId,
				});
			}
			return completion;
		},
		sendRequestDescriptor: (sendProps): Promise<void> => {
			const completion = new Promise<void>((resolve, reject): void => {
				pendingRequestsByRequestId.set(sendProps.requestId, {
					kind: 'requestDescriptor',
					resolve,
					reject,
					timeoutId: createWorktreeFileWorkerRpcTimeout({
						onTimeout: (): void => {
							rejectWorktreeFileWorkerRpcRequest({
								error: new Error('Native Worktree/File descriptor request timed out'),
								pendingRequestsByRequestId,
								requestId: sendProps.requestId,
							});
						},
						timeoutMilliseconds: options.timeoutMilliseconds,
					}),
				});
			});
			try {
				const commandEpoch = recordEpoch(sendProps.request.sourceIdentity.subscriptionGeneration);
				dispatcher.dispatch(
					encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
						requestId: sendProps.requestId,
						epoch: commandEpoch,
						descriptorRequest: sendProps.request,
					}),
				);
			} catch (error) {
				rejectWorktreeFileWorkerRpcRequest({
					error:
						error instanceof Error
							? error
							: new Error('Native Worktree/File descriptor request failed'),
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

function resolveWorktreeFileWorkerRpcRequests(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileWorkerRpcRequest>;
	readonly recordEpoch: (epoch: number) => number;
}): void {
	for (const message of props.messages) {
		if (message.kind === 'worktreeFileOpenSourceStreamResult') {
			resolveWorktreeFileOpenSourceStreamRequest({
				outcome: message.outcome,
				pendingRequestsByRequestId: props.pendingRequestsByRequestId,
				recordEpoch: props.recordEpoch,
				requestId: message.requestId,
			});
			continue;
		}
		if (message.kind !== 'health' || message.requestId === undefined) {
			continue;
		}
		if (message.status === 'degraded') {
			resolveWorktreeFileIntakeReadyRequest({
				didSend: false,
				pendingRequestsByRequestId: props.pendingRequestsByRequestId,
				requestId: message.requestId,
			});
			rejectWorktreeFileWorkerRpcRequest({
				error: new Error(message.message ?? 'Native Worktree/File worker command failed'),
				pendingRequestsByRequestId: props.pendingRequestsByRequestId,
				requestId: message.requestId,
			});
			continue;
		}
		resolveWorktreeFileIntakeReadyRequest({
			didSend: true,
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId: message.requestId,
		});
		resolveWorktreeFileRequestDescriptorRequest({
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId: message.requestId,
		});
	}
}

function resolveWorktreeFileIntakeReadyRequest(props: {
	readonly didSend: boolean;
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileWorkerRpcRequest>;
	readonly requestId: string;
}): void {
	const pendingRequest = props.pendingRequestsByRequestId.get(props.requestId);
	if (pendingRequest === undefined || pendingRequest.kind !== 'intakeReady') {
		return;
	}
	props.pendingRequestsByRequestId.delete(props.requestId);
	if (pendingRequest.timeoutId !== null) {
		clearTimeout(pendingRequest.timeoutId);
	}
	pendingRequest.resolve(props.didSend);
}

function resolveWorktreeFileOpenSourceStreamRequest(
	props: WorktreeFileWorkerRpcOpenResolveProps,
): void {
	const pendingRequest = props.pendingRequestsByRequestId.get(props.requestId);
	if (pendingRequest === undefined || pendingRequest.kind !== 'openSourceStream') {
		return;
	}
	props.pendingRequestsByRequestId.delete(props.requestId);
	if (pendingRequest.timeoutId !== null) {
		clearTimeout(pendingRequest.timeoutId);
	}
	props.recordEpoch(props.outcome.generation);
	pendingRequest.resolve(props.outcome);
}

function resolveWorktreeFileRequestDescriptorRequest(
	props: WorktreeFileWorkerRpcDescriptorResolveProps,
): void {
	const pendingRequest = props.pendingRequestsByRequestId.get(props.requestId);
	if (pendingRequest === undefined || pendingRequest.kind !== 'requestDescriptor') {
		return;
	}
	props.pendingRequestsByRequestId.delete(props.requestId);
	if (pendingRequest.timeoutId !== null) {
		clearTimeout(pendingRequest.timeoutId);
	}
	pendingRequest.resolve();
}

function rejectWorktreeFileWorkerRpcRequest(props: WorktreeFileWorkerRpcRejectProps): void {
	const pendingRequest = props.pendingRequestsByRequestId.get(props.requestId);
	if (pendingRequest === undefined || pendingRequest.kind === 'intakeReady') {
		return;
	}
	props.pendingRequestsByRequestId.delete(props.requestId);
	if (pendingRequest.timeoutId !== null) {
		clearTimeout(pendingRequest.timeoutId);
	}
	pendingRequest.reject(props.error);
}

function resolveAllWorktreeFileIntakeReadyRequests(props: {
	readonly didSend: boolean;
	readonly pendingRequestsByRequestId: Map<string, PendingWorktreeFileWorkerRpcRequest>;
}): void {
	for (const [requestId] of props.pendingRequestsByRequestId) {
		resolveWorktreeFileIntakeReadyRequest({
			didSend: props.didSend,
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId,
		});
		rejectWorktreeFileWorkerRpcRequest({
			error: new Error('Native Worktree/File worker transport disposed'),
			pendingRequestsByRequestId: props.pendingRequestsByRequestId,
			requestId,
		});
	}
}

function createWorktreeFileWorkerRpcTimeout(props: {
	readonly onTimeout: () => void;
	readonly timeoutMilliseconds: number | undefined;
}): ReturnType<typeof setTimeout> | null {
	if (props.timeoutMilliseconds === undefined) {
		return null;
	}
	return setTimeout(props.onTimeout, props.timeoutMilliseconds);
}
