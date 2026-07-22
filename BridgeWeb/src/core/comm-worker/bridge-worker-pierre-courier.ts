import type { BridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';

export interface CreateBridgeWorkerPierreCourierProps {
	readonly submitPierreRenderJob: (job: BridgeWorkerPierreRenderJob) => void;
}

export interface BridgeWorkerPierreCourier {
	readonly submit: (job: BridgeWorkerPierreRenderJob) => void;
}

export function createBridgeWorkerPierreCourier(
	props: CreateBridgeWorkerPierreCourierProps,
): BridgeWorkerPierreCourier {
	return {
		submit: (job: BridgeWorkerPierreRenderJob): void => props.submitPierreRenderJob(job),
	};
}
