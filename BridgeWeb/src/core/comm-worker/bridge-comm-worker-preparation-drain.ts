import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol-contracts.js';
import type { WorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

export async function drainBridgeCommWorkerPreparations(props: {
	readonly advanceRenderFulfillmentLifecycle: (surface: 'file' | 'review') => void;
	readonly pendingCompletions: Promise<void>[];
	readonly pump: WorkerContentPreparationPump;
	readonly requestPreparationDrain: () => void;
}): ReturnType<BridgeCommWorkerPreparationDrain> {
	const completions = props.pendingCompletions.splice(0, props.pendingCompletions.length);
	const runResult = props.pump.runUntilBudget();
	props.advanceRenderFulfillmentLifecycle('file');
	props.advanceRenderFulfillmentLifecycle('review');
	if (props.pump.getPendingWorkIds().length > 0) props.requestPreparationDrain();
	const completionResults = await Promise.allSettled(completions);
	const rejectedCompletion = completionResults.find(
		(result): result is PromiseRejectedResult => result.status === 'rejected',
	);
	if (rejectedCompletion !== undefined) throw rejectedCompletion.reason;
	return runResult;
}
