import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerFileViewSourceUpdateCommandSchema,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerMetadataInterestUpdateCommandSchema,
	bridgeWorkerModeCommandSchema,
	bridgeWorkerReviewInvalidateCommandSchema,
	bridgeWorkerReviewSourceUpdateCommandSchema,
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	type BridgeWorkerHealthEvent,
	type BridgeWorkerFileViewSourceUpdateCommand,
	type BridgeWorkerHoverCommand,
	type BridgeWorkerMainToServerCommand,
	type BridgeWorkerMarkFileViewedCommand,
	type BridgeWorkerMetadataInterestRequest,
	type BridgeWorkerMetadataInterestUpdateCommand,
	type BridgeWorkerModeCommand,
	type BridgeWorkerReviewInvalidateCommand,
	type BridgeWorkerReviewSourceUpdateCommand,
	type BridgeWorkerSelectCommand,
	type BridgeWorkerViewportCommand,
} from './bridge-worker-contracts.js';

export type BridgeWorkerCommandName = BridgeWorkerMainToServerCommand['command'];

export interface EncodeBridgeWorkerCommandBaseProps {
	readonly requestId: string;
	readonly epoch: number;
	readonly issuedAtMilliseconds?: number;
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
	readonly fileId: string;
}

export interface EncodeBridgeWorkerMetadataInterestUpdateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly request: BridgeWorkerMetadataInterestRequest;
}

export interface EncodeBridgeWorkerModeCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly mode: BridgeWorkerModeCommand['mode'];
}

export interface EncodeBridgeWorkerReviewInvalidateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly scope: BridgeWorkerReviewInvalidateCommand['scope'];
	readonly itemIds: readonly string[];
	readonly pathHints: readonly string[];
	readonly reason: BridgeWorkerReviewInvalidateCommand['reason'];
}

export interface EncodeBridgeWorkerReviewSourceUpdateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly contentItems: BridgeWorkerReviewSourceUpdateCommand['contentItems'];
	readonly contentRequestDescriptors: BridgeWorkerReviewSourceUpdateCommand['contentRequestDescriptors'];
	readonly renderSemantics: BridgeWorkerReviewSourceUpdateCommand['renderSemantics'];
	readonly rows: BridgeWorkerReviewSourceUpdateCommand['rows'];
}

export interface EncodeBridgeWorkerFileViewSourceUpdateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly contentItems: BridgeWorkerFileViewSourceUpdateCommand['contentItems'];
	readonly contentRequestDescriptors: BridgeWorkerFileViewSourceUpdateCommand['contentRequestDescriptors'];
	readonly rows: BridgeWorkerFileViewSourceUpdateCommand['rows'];
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
		fileId: props.fileId,
	});
}

export function encodeBridgeWorkerMetadataInterestUpdateCommand(
	props: EncodeBridgeWorkerMetadataInterestUpdateCommandProps,
): BridgeWorkerMetadataInterestUpdateCommand {
	return bridgeWorkerMetadataInterestUpdateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'metadataInterestUpdate'),
		request: props.request,
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

export function encodeBridgeWorkerReviewInvalidateCommand(
	props: EncodeBridgeWorkerReviewInvalidateCommandProps,
): BridgeWorkerReviewInvalidateCommand {
	return bridgeWorkerReviewInvalidateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'reviewInvalidate'),
		scope: props.scope,
		itemIds: props.itemIds,
		pathHints: props.pathHints,
		reason: props.reason,
	});
}

export function encodeBridgeWorkerReviewSourceUpdateCommand(
	props: EncodeBridgeWorkerReviewSourceUpdateCommandProps,
): BridgeWorkerReviewSourceUpdateCommand {
	return bridgeWorkerReviewSourceUpdateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'reviewSourceUpdate'),
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics,
		rows: props.rows,
	});
}

export function encodeBridgeWorkerFileViewSourceUpdateCommand(
	props: EncodeBridgeWorkerFileViewSourceUpdateCommandProps,
): BridgeWorkerFileViewSourceUpdateCommand {
	return bridgeWorkerFileViewSourceUpdateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'fileViewSourceUpdate'),
		contentItems: props.contentItems,
		contentRequestDescriptors: props.contentRequestDescriptors,
		rows: props.rows,
	});
}

export function buildBridgeWorkerReadyHealthEvent(requestId?: string): BridgeWorkerHealthEvent {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'health',
		...(requestId === undefined ? {} : { requestId }),
		status: 'ready',
	};
}

function bridgeWorkerCommandEnvelope(
	props: EncodeBridgeWorkerCommandBaseProps,
	command: BridgeWorkerCommandName,
): Pick<
	BridgeWorkerMainToServerCommand,
	| 'wireVersion'
	| 'direction'
	| 'kind'
	| 'requestId'
	| 'epoch'
	| 'issuedAtMilliseconds'
	| 'transferDescriptors'
> & {
	readonly command: BridgeWorkerCommandName;
} {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'mainToServerWorker',
		kind: 'command',
		requestId: props.requestId,
		epoch: props.epoch,
		...(props.issuedAtMilliseconds === undefined
			? {}
			: { issuedAtMilliseconds: props.issuedAtMilliseconds }),
		transferDescriptors: [],
		command,
	};
}
