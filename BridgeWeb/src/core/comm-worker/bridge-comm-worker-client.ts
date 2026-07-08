// oxlint-disable unicorn/require-post-message-target-origin -- The inert client posts through a MessagePort-like worker transport, not Window.postMessage.
import {
	buildBridgeWorkerReadyHealthEvent,
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
	encodeBridgeWorkerWorktreeFileIntakeReadyCommand,
	type EncodeBridgeWorkerHoverCommandProps,
	type EncodeBridgeWorkerMarkFileViewedCommandProps,
	type EncodeBridgeWorkerMetadataInterestUpdateCommandProps,
	type EncodeBridgeWorkerActiveViewerModeUpdateCommandProps,
	type EncodeBridgeWorkerModeCommandProps,
	type EncodeBridgeWorkerReviewIntakeReadyCommandProps,
	type EncodeBridgeWorkerSelectCommandProps,
	type EncodeBridgeWorkerViewportCommandProps,
	type EncodeBridgeWorkerWorktreeFileIntakeReadyCommandProps,
} from './bridge-comm-worker-protocol.js';
import type {
	BridgeWorkerHealthEvent,
	BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

export interface InertBridgeCommWorkerClientSideEffectGuards {
	readonly onSwiftFetch?: () => void;
	readonly onTelemetryFlush?: () => void;
	readonly onDemandSideEffect?: () => void;
}

export interface CreateInertBridgeCommWorkerClientProps extends InertBridgeCommWorkerClientSideEffectGuards {
	readonly postMessage: (message: BridgeWorkerMainToServerMessage) => void;
	readonly waitForHealth?: (
		message: BridgeWorkerMainToServerMessage,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly createRequestId?: () => string;
}

export interface InertBridgeCommWorkerClient {
	readonly select: (
		props: Omit<EncodeBridgeWorkerSelectCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly viewport: (
		props: Omit<EncodeBridgeWorkerViewportCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly hover: (
		props: Omit<EncodeBridgeWorkerHoverCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly markFileViewed: (
		props: Omit<EncodeBridgeWorkerMarkFileViewedCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly metadataInterestUpdate: (
		props: Omit<EncodeBridgeWorkerMetadataInterestUpdateCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly reviewIntakeReady: (
		props: Omit<EncodeBridgeWorkerReviewIntakeReadyCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly worktreeFileIntakeReady: (
		props: Omit<EncodeBridgeWorkerWorktreeFileIntakeReadyCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly activeViewerModeUpdate: (
		props: Omit<EncodeBridgeWorkerActiveViewerModeUpdateCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
	readonly mode: (
		props: Omit<EncodeBridgeWorkerModeCommandProps, 'requestId'>,
	) => Promise<BridgeWorkerHealthEvent>;
}

export function createInertBridgeCommWorkerClient(
	props: CreateInertBridgeCommWorkerClientProps,
): InertBridgeCommWorkerClient {
	const createRequestId = props.createRequestId ?? defaultBridgeCommWorkerRequestIdFactory;
	const waitForHealth =
		props.waitForHealth ??
		((message: BridgeWorkerMainToServerMessage): Promise<BridgeWorkerHealthEvent> =>
			Promise.resolve(buildBridgeWorkerReadyHealthEvent(message.requestId)));

	const postAndWait = (
		message: BridgeWorkerMainToServerMessage,
	): Promise<BridgeWorkerHealthEvent> => {
		props.postMessage(message);
		return waitForHealth(message);
	};

	return {
		select: (selectProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerSelectCommand({
					...selectProps,
					requestId: createRequestId(),
				}),
			),
		viewport: (viewportProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerViewportCommand({
					...viewportProps,
					requestId: createRequestId(),
				}),
			),
		hover: (hoverProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerHoverCommand({
					...hoverProps,
					requestId: createRequestId(),
				}),
			),
		markFileViewed: (markFileViewedProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerMarkFileViewedCommand({
					...markFileViewedProps,
					requestId: createRequestId(),
				}),
			),
		metadataInterestUpdate: (metadataInterestUpdateProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerMetadataInterestUpdateCommand({
					...metadataInterestUpdateProps,
					requestId: createRequestId(),
				}),
			),
		reviewIntakeReady: (reviewIntakeReadyProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerReviewIntakeReadyCommand({
					...reviewIntakeReadyProps,
					requestId: createRequestId(),
				}),
			),
		worktreeFileIntakeReady: (worktreeFileIntakeReadyProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
					...worktreeFileIntakeReadyProps,
					requestId: createRequestId(),
				}),
			),
		activeViewerModeUpdate: (activeViewerModeUpdateProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerActiveViewerModeUpdateCommand({
					...activeViewerModeUpdateProps,
					requestId: createRequestId(),
				}),
			),
		mode: (modeProps): Promise<BridgeWorkerHealthEvent> =>
			postAndWait(
				encodeBridgeWorkerModeCommand({
					...modeProps,
					requestId: createRequestId(),
				}),
			),
	};
}

function defaultBridgeCommWorkerRequestIdFactory(): string {
	return `bridge_comm_worker_${crypto.randomUUID()}`;
}
