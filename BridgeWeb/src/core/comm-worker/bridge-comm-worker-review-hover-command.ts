import type { BridgeCommWorkerDemandExecutionScheduleRequest } from './bridge-comm-worker-command-handler-contracts.js';
import { buildBridgeWorkerUnimplementedHealthEvent } from './bridge-comm-worker-command-support.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerHoverCommand,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

export interface HandleBridgeCommWorkerReviewHoverCommandProps {
	readonly message: BridgeWorkerHoverCommand;
	readonly scheduleDemandExecution?: (
		request: BridgeCommWorkerDemandExecutionScheduleRequest,
	) => void;
	readonly store: BridgeCommWorkerStore;
}

export function handleBridgeCommWorkerReviewHoverCommand(
	props: HandleBridgeCommWorkerReviewHoverCommandProps,
): readonly BridgeWorkerServerToMainMessage[] {
	if (props.message.surface !== 'review') {
		return [buildBridgeWorkerUnimplementedHealthEvent(props.message)];
	}
	props.store.actions.applyHoveredFact({ hoveredItemId: props.message.hoveredItemId });
	props.scheduleDemandExecution?.({
		cause: 'hover',
		epoch: props.message.epoch,
		store: props.store,
	});
	return [buildBridgeWorkerReadyHealthEvent(props.message.requestId)];
}
