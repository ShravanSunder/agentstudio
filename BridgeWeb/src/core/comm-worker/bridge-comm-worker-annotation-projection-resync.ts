import type { AnnotationProjectionResyncTask } from './bridge-comm-worker-annotation-subscription-controller.js';
import { buildBridgeWorkerReadyHealthEvent } from './bridge-comm-worker-protocol.js';
import { buildBridgeWorkerRuntimeCommandFailedHealthEvent } from './bridge-comm-worker-runtime-health.js';
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';

export type ScheduleAnnotationProjectionResyncDeadline = (
	delayMilliseconds: number,
	deadline: () => void,
) => () => void;

export function runAnnotationProjectionResyncWithDeadline(props: {
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly scheduleDeadline?: ScheduleAnnotationProjectionResyncDeadline;
	readonly task: AnnotationProjectionResyncTask;
	readonly timeoutMilliseconds: number;
}): void {
	let terminalPublished = false;
	const scheduleDeadline = props.scheduleDeadline ?? scheduleDefaultDeadline;
	const cancelDeadline = scheduleDeadline(props.timeoutMilliseconds, (): void => {
		if (terminalPublished) return;
		props.task.invalidate('timeout');
		terminalPublished = true;
		props.publish(
			buildBridgeWorkerRuntimeCommandFailedHealthEvent({
				message: 'Annotation projection resync timed out.',
				requestId: props.task.requestId,
			}),
		);
	});

	void props.task.completion.then(
		(): void => {
			if (terminalPublished) return;
			terminalPublished = true;
			cancelDeadline();
			props.publish(buildBridgeWorkerReadyHealthEvent(props.task.requestId));
		},
		(): void => {
			if (terminalPublished) return;
			props.task.invalidate('commandRejected');
			terminalPublished = true;
			cancelDeadline();
			props.publish(
				buildBridgeWorkerRuntimeCommandFailedHealthEvent({
					message: 'Annotation projection resync failed.',
					requestId: props.task.requestId,
				}),
			);
		},
	);
}

function scheduleDefaultDeadline(delayMilliseconds: number, deadline: () => void): () => void {
	const timeoutId = globalThis.setTimeout(deadline, delayMilliseconds);
	return (): void => globalThis.clearTimeout(timeoutId);
}
