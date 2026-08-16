import type { BridgeCommWorkerTelemetryRecorder } from './bridge-comm-worker-telemetry.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type {
	WorkerContentPreparationPump,
	WorkerContentPreparationPumpRunResult,
} from './bridge-worker-content-preparation-pump.js';
import type { BridgeWorkerFileViewContentOpen } from './bridge-worker-file-view-content-fetch.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerReviewContentOpen } from './bridge-worker-review-content-fetch.js';

export type BridgeCommWorkerPreparationDrain = () => Promise<WorkerContentPreparationPumpRunResult>;

export interface RegisterBridgeCommWorkerRuntimePortProtocolProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly fileViewBridgeDemandRank?: BridgeWorkerDemandRank;
	readonly fileViewBudget?: BridgeWorkerPierreRenderBudget;
	readonly createSequence?: () => number;
	readonly maxPreparationSliceMs?: number;
	readonly now?: () => number;
	readonly openFileViewContent?: BridgeWorkerFileViewContentOpen;
	readonly openReviewContent?: BridgeWorkerReviewContentOpen;
	readonly pump?: WorkerContentPreparationPump;
	readonly productTransport?: BridgeProductTransportSession;
	readonly renderFulfillmentContext?: {
		readonly paneSessionId: string;
		readonly workerInstanceId: string;
	};
	readonly scheduleRenderFulfillmentWake?: (
		delayMilliseconds: number,
		wake: () => void,
	) => () => void;
	readonly schedulePreparationDrain?: (drain: BridgeCommWorkerPreparationDrain) => void;
	readonly sendProductControl?: BridgeCommWorkerProductControlSender;
	readonly productControlTimeoutMilliseconds?: number;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export type BridgeCommWorkerProductControlSender = (
	command: BridgeProductControlCommand,
) => Promise<unknown>;
