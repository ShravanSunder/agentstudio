import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerActiveViewerModeUpdateCommandSchema,
	bridgeWorkerFileDisplayResyncCommandSchema,
	bridgeWorkerFileQueryUpdateCommandSchema,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerMetadataInterestUpdateCommandSchema,
	bridgeWorkerModeCommandSchema,
	bridgeWorkerRenderDispositionCommandSchema,
	bridgeWorkerReviewIntakeReadyCommandSchema,
	bridgeWorkerReviewInvalidateCommandSchema,
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	type BridgeWorkerHealthEvent,
	type BridgeWorkerActiveViewerModeUpdateCommand,
	type BridgeWorkerFileDisplayResyncCommand,
	type BridgeWorkerFileQueryUpdateCommand,
	type BridgeWorkerHoverCommand,
	type BridgeWorkerMainToServerCommand,
	type BridgeWorkerMarkFileViewedCommand,
	type BridgeWorkerMetadataInterestRequest,
	type BridgeWorkerMetadataInterestUpdateCommand,
	type BridgeWorkerModeCommand,
	type BridgeWorkerRenderDispositionCommand,
	type BridgeWorkerReviewIntakeReadyCommand,
	type BridgeWorkerReviewInvalidateCommand,
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
	readonly surface: BridgeWorkerSelectCommand['surface'];
	readonly selectedItemId: string;
	readonly selectedSource: BridgeWorkerSelectCommand['selectedSource'];
}

export interface EncodeBridgeWorkerViewportCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly surface: BridgeWorkerViewportCommand['surface'];
	readonly visibleItemIds: readonly string[];
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly phase: BridgeWorkerViewportCommand['phase'];
}

export interface EncodeBridgeWorkerHoverCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly surface: BridgeWorkerHoverCommand['surface'];
	readonly hoveredItemId: string | null;
}

export interface EncodeBridgeWorkerMarkFileViewedCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly fileId: string;
}

export interface EncodeBridgeWorkerMetadataInterestUpdateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly request: BridgeWorkerMetadataInterestRequest;
}

export interface EncodeBridgeWorkerReviewIntakeReadyCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly reason?: BridgeWorkerReviewIntakeReadyCommand['reason'];
	readonly streamId: BridgeWorkerReviewIntakeReadyCommand['streamId'];
}

export interface EncodeBridgeWorkerActiveViewerModeUpdateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly update: BridgeWorkerActiveViewerModeUpdateCommand['update'];
}

export interface EncodeBridgeWorkerModeCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly mode: BridgeWorkerModeCommand['mode'];
}

export type EncodeBridgeWorkerFileQueryUpdateCommandProps = EncodeBridgeWorkerCommandBaseProps &
	BridgeWorkerFileQueryUpdateCommand['query'];

export interface EncodeBridgeWorkerFileDisplayResyncCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly reason: BridgeWorkerFileDisplayResyncCommand['reason'];
	readonly transactionId: string | null;
}

export interface EncodeBridgeWorkerReviewInvalidateCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly scope: BridgeWorkerReviewInvalidateCommand['scope'];
	readonly itemIds: readonly string[];
	readonly pathHints: readonly string[];
	readonly reason: BridgeWorkerReviewInvalidateCommand['reason'];
}

export interface EncodeBridgeWorkerRenderDispositionCommandProps extends EncodeBridgeWorkerCommandBaseProps {
	readonly receipt: BridgeWorkerRenderDispositionCommand['receipt'];
}

export function encodeBridgeWorkerSelectCommand(
	props: EncodeBridgeWorkerSelectCommandProps,
): BridgeWorkerSelectCommand {
	return bridgeWorkerSelectCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'select'),
		surface: props.surface,
		selectedItemId: props.selectedItemId,
		selectedSource: props.selectedSource,
	});
}

export function encodeBridgeWorkerViewportCommand(
	props: EncodeBridgeWorkerViewportCommandProps,
): BridgeWorkerViewportCommand {
	return bridgeWorkerViewportCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'viewport'),
		surface: props.surface,
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
		surface: props.surface,
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

export function encodeBridgeWorkerReviewIntakeReadyCommand(
	props: EncodeBridgeWorkerReviewIntakeReadyCommandProps,
): BridgeWorkerReviewIntakeReadyCommand {
	return bridgeWorkerReviewIntakeReadyCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'reviewIntakeReady'),
		protocolId: 'review',
		streamId: props.streamId,
		reason: props.reason ?? null,
	});
}

export function encodeBridgeWorkerActiveViewerModeUpdateCommand(
	props: EncodeBridgeWorkerActiveViewerModeUpdateCommandProps,
): BridgeWorkerActiveViewerModeUpdateCommand {
	return bridgeWorkerActiveViewerModeUpdateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'activeViewerModeUpdate'),
		update: props.update,
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

export function encodeBridgeWorkerFileQueryUpdateCommand(
	props: EncodeBridgeWorkerFileQueryUpdateCommandProps,
): BridgeWorkerFileQueryUpdateCommand {
	return bridgeWorkerFileQueryUpdateCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'fileQueryUpdate'),
		query: {
			filterMode: props.filterMode,
			searchMode: props.searchMode,
			searchText: props.searchText,
		},
	});
}

export function encodeBridgeWorkerFileDisplayResyncCommand(
	props: EncodeBridgeWorkerFileDisplayResyncCommandProps,
): BridgeWorkerFileDisplayResyncCommand {
	return bridgeWorkerFileDisplayResyncCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'fileDisplayResync'),
		reason: props.reason,
		transactionId: props.transactionId,
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

export function encodeBridgeWorkerRenderDispositionCommand(
	props: EncodeBridgeWorkerRenderDispositionCommandProps,
): BridgeWorkerRenderDispositionCommand {
	return bridgeWorkerRenderDispositionCommandSchema.parse({
		...bridgeWorkerCommandEnvelope(props, 'renderDisposition'),
		receipt: props.receipt,
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
