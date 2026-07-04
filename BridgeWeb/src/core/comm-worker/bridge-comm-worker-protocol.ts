import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerModeCommandSchema,
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	type BridgeWorkerHealthEvent,
	type BridgeWorkerHoverCommand,
	type BridgeWorkerMainToServerCommand,
	type BridgeWorkerMarkFileViewedCommand,
	type BridgeWorkerModeCommand,
	type BridgeWorkerSelectCommand,
	type BridgeWorkerViewportCommand,
} from './bridge-worker-contracts.js';

export type BridgeWorkerCommandName = BridgeWorkerMainToServerCommand['command'];

export interface EncodeBridgeWorkerCommandBaseProps {
	readonly requestId: string;
	readonly epoch: number;
}

export interface EncodeBridgeWorkerSelectCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly selectedItemId: string;
	readonly selectedSource: BridgeWorkerSelectCommand['selectedSource'];
}

export interface EncodeBridgeWorkerViewportCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly visibleItemIds: readonly string[];
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly phase: BridgeWorkerViewportCommand['phase'];
}

export interface EncodeBridgeWorkerHoverCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly hoveredItemId: string | null;
}

export interface EncodeBridgeWorkerMarkFileViewedCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly filePathHash: string;
	readonly viewedAtSequence: number;
}

export interface EncodeBridgeWorkerModeCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly mode: BridgeWorkerModeCommand['mode'];
}

export function encodeBridgeWorkerSelectCommand(
	props: EncodeBridgeWorkerSelectCommandProps,
): BridgeWorkerSelectCommand {
	return bridgeWorkerSelectCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'select'),
		selectedItemId: props.selectedItemId,
		selectedSource: props.selectedSource,
	});
}

export function encodeBridgeWorkerViewportCommand(
	props: EncodeBridgeWorkerViewportCommandProps,
): BridgeWorkerViewportCommand {
	return bridgeWorkerViewportCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'viewport'),
		visibleItemIds: props.visibleItemIds,
		firstVisibleIndex: props.firstVisibleIndex,
		lastVisibleIndex: props.lastVisibleIndex,
		phase: props.phase,
	});
}

export function encodeBridgeWorkerHoverCommand(
	props: EncodeBridgeWorkerHoverCommandProps,
): BridgeWorkerHoverCommand {
	return bridgeWorkerHoverCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'hover'),
		hoveredItemId: props.hoveredItemId,
	});
}

export function encodeBridgeWorkerMarkFileViewedCommand(
	props: EncodeBridgeWorkerMarkFileViewedCommandProps,
): BridgeWorkerMarkFileViewedCommand {
	return bridgeWorkerMarkFileViewedCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'markFileViewed'),
		filePathHash: props.filePathHash,
		viewedAtSequence: props.viewedAtSequence,
	});
}

export function encodeBridgeWorkerModeCommand(
	props: EncodeBridgeWorkerModeCommandProps,
): BridgeWorkerModeCommand {
	return bridgeWorkerModeCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'mode'),
		mode: props.mode,
	});
}

export function buildBridgeWorkerReadyHealthEvent(requestId?: string): BridgeWorkerHealthEvent {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		kind: 'health',
		...(requestId === undefined ? {} : { requestId }),
		status: 'ready',
	};
}

function bridgeWorkerCommandEnvelope(
	props: EncodeBridgeWorkerCommandBaseProps,
	command: BridgeWorkerCommandName,
): Omit<BridgeWorkerMainToServerCommand, 'command'> & {
	readonly command: BridgeWorkerCommandName;
} {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'mainToServerWorker',
		kind: 'command',
		requestId: props.requestId,
		epoch: props.epoch,
		command,
	};
}
