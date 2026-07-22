import type { WorktreeBridgeTelemetrySampleProof } from './types.ts';

export interface ReviewWorkerQueueWaitMilliseconds {
	readonly selected: readonly number[];
	readonly visible: readonly number[];
}

export const reviewFirstVisibleContentStates: readonly string[] = ['hydrated', 'windowed'];

export function parseNullableNumericAttribute(value: string | null): number | null {
	if (value === null || value.length === 0) {
		return null;
	}
	const parsedValue = Number(value);
	return Number.isFinite(parsedValue) && parsedValue >= 0 ? parsedValue : null;
}

export function reviewContentStateCanRenderFirstVisibleWindow(
	contentState: string | null,
): boolean {
	return contentState !== null && reviewFirstVisibleContentStates.includes(contentState);
}

export function collectReviewWorkerQueueWaitMilliseconds(props: {
	readonly sampleCount: number;
	readonly selectedPhaseSamples: readonly WorktreeBridgeTelemetrySampleProof[];
	readonly visiblePhaseSamples: readonly WorktreeBridgeTelemetrySampleProof[];
}): ReviewWorkerQueueWaitMilliseconds {
	return {
		selected: reviewWorkerQueueWaitMillisecondsForLane({
			command: 'select',
			lane: 'selected',
			sampleCount: props.sampleCount,
			samples: props.selectedPhaseSamples,
		}),
		visible: reviewWorkerQueueWaitMillisecondsForLane({
			command: 'viewport',
			lane: 'visible',
			sampleCount: props.sampleCount,
			samples: props.visiblePhaseSamples,
		}),
	};
}

function reviewWorkerQueueWaitMillisecondsForLane(props: {
	readonly command: 'select' | 'viewport';
	readonly lane: 'selected' | 'visible';
	readonly sampleCount: number;
	readonly samples: readonly WorktreeBridgeTelemetrySampleProof[];
}): readonly number[] {
	return props.samples
		.filter(
			(sample): boolean =>
				sample.name === 'performance.bridge.worker.task' &&
				sample.workerTaskKind === 'message_handler' &&
				sample.workerCommand === props.command &&
				sample.workerLane === props.lane,
		)
		.flatMap((sample): readonly number[] => {
			const queueWaitMilliseconds =
				sample.numericAttributes['agentstudio.bridge.worker.queue_wait_ms'];
			return queueWaitMilliseconds !== undefined &&
				Number.isFinite(queueWaitMilliseconds) &&
				queueWaitMilliseconds >= 0
				? [queueWaitMilliseconds]
				: [];
		})
		.slice(-props.sampleCount);
}
