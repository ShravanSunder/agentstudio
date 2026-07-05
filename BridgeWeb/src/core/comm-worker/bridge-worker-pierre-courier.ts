import type {
	BridgeWorkerPierreBudgetClass,
	BridgeWorkerPierreRenderJob,
} from './bridge-worker-pierre-render-job.js';

export interface BridgeWorkerPierreCourierReceipt {
	readonly status: 'enqueued';
	readonly itemId: string;
	readonly payloadByteLength: number;
	readonly budgetClass: BridgeWorkerPierreBudgetClass;
}

export interface CreateBridgeWorkerPierreCourierProps {
	readonly enqueuePierreRenderJob: (
		job: BridgeWorkerPierreRenderJob,
	) => BridgeWorkerPierreCourierReceipt;
}

export interface BridgeWorkerPierreCourier {
	readonly enqueue: (job: BridgeWorkerPierreRenderJob) => BridgeWorkerPierreCourierReceipt;
}

export function createBridgeWorkerPierreCourier(
	props: CreateBridgeWorkerPierreCourierProps,
): BridgeWorkerPierreCourier {
	return {
		enqueue: (job: BridgeWorkerPierreRenderJob): BridgeWorkerPierreCourierReceipt =>
			props.enqueuePierreRenderJob(job),
	};
}
