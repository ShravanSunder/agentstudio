import type { Page } from 'playwright';

import { readBridgeWorktreeVerifierTelemetrySamples } from './route-probes.ts';
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
	readonly samples: readonly WorktreeBridgeTelemetrySampleProof[];
}): ReviewWorkerQueueWaitMilliseconds {
	return {
		selected: reviewWorkerQueueWaitMillisecondsForLane({
			command: 'select',
			lane: 'selected',
			sampleCount: props.sampleCount,
			samples: props.samples,
		}),
		visible: reviewWorkerQueueWaitMillisecondsForLane({
			command: 'viewport',
			lane: 'visible',
			sampleCount: props.sampleCount,
			samples: props.samples,
		}),
	};
}

export async function waitForReviewWorkerQueueWaitMilliseconds(props: {
	readonly page: Page;
	readonly sampleCount: number;
	readonly timeoutMilliseconds: number;
}): Promise<ReviewWorkerQueueWaitMilliseconds> {
	try {
		await props.page.waitForFunction(
			(sampleCount: number): boolean => {
				const samples = window.bridgeWorktreeVerifierTelemetrySamples ?? [];
				const matchingCount = (command: string, lane: string): number =>
					samples.filter(
						(sample): boolean =>
							sample.name === 'performance.bridge.worker.task' &&
							sample.workerTaskKind === 'message_handler' &&
							sample.workerCommand === command &&
							sample.workerLane === lane &&
							Number.isFinite(sample.numericAttributes['agentstudio.bridge.worker.queue_wait_ms']),
					).length;
				return (
					matchingCount('select', 'selected') >= sampleCount &&
					matchingCount('viewport', 'visible') >= sampleCount
				);
			},
			props.sampleCount,
			{ timeout: props.timeoutMilliseconds },
		);
	} catch {
		// Return the observed counts so the proof fails with an honest sample deficit.
	}
	return collectReviewWorkerQueueWaitMilliseconds({
		sampleCount: props.sampleCount,
		samples: await readBridgeWorktreeVerifierTelemetrySamples(props.page),
	});
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
