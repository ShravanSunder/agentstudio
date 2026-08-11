import { expect } from 'vitest';

import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';

export interface PendingReviewContentAttempt {
	readonly abortSignal: AbortSignal;
	readonly descriptorId: string;
}

export function makePendingReviewContentStream(props: {
	readonly abortSignal: AbortSignal;
	readonly attempts: PendingReviewContentAttempt[];
	readonly descriptorId: string;
}): BridgeProductContentStream<'review.content'> {
	props.attempts.push({
		abortSignal: props.abortSignal,
		descriptorId: props.descriptorId,
	});
	return {
		contentKind: 'review.content',
		contentRequestId: `review-content-request-${props.attempts.length}`,
		frames: emptyReviewContentFrames(),
		terminal: new Promise((_, reject): void => {
			props.abortSignal.addEventListener('abort', (): void => reject(props.abortSignal.reason), {
				once: true,
			});
		}),
	};
}

export async function drainUntilReviewAttemptCount(props: {
	readonly attempts: readonly PendingReviewContentAttempt[];
	readonly expectedCount: number;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
	readonly flushContinuations: () => Promise<void>;
}): Promise<void> {
	const activeAttempts = props.attempts.filter(({ abortSignal }) => !abortSignal.aborted);
	if (activeAttempts.length >= props.expectedCount || props.scheduledDrains.length === 0) {
		expect(activeAttempts).toHaveLength(props.expectedCount);
		return;
	}
	const drain = props.scheduledDrains.shift();
	if (drain === undefined) throw new Error('Expected scheduled Review preparation drain.');
	void drain();
	await props.flushContinuations();
	await drainUntilReviewAttemptCount(props);
}

export function expectOriginalReviewContentAttemptsRemainActive(
	attempts: readonly PendingReviewContentAttempt[],
): void {
	expect(attempts.map(({ descriptorId }) => descriptorId)).toEqual([
		'review-descriptor-item-1-base',
		'review-descriptor-item-1-head',
	]);
	expect(attempts.every(({ abortSignal }) => !abortSignal.aborted)).toBe(true);
}

export async function drainBridgeCommWorkerPreparationUntilIdle(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
	flushContinuations: () => Promise<void>,
): Promise<void> {
	const drainCompletions: Array<ReturnType<BridgeCommWorkerPreparationDrain>> = [];
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = scheduledDrains.splice(0);
		if (drainsForRound.length > 0) {
			drainCompletions.push(...drainsForRound.map((drain) => drain()));
		}
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes the event-scheduled follow-up drains for the next round.
		await flushContinuations();
		if (scheduledDrains.length === 0) break;
	}
	expect(scheduledDrains).toEqual([]);
	await Promise.all(drainCompletions);
	await flushContinuations();
}

export async function startBridgeCommWorkerPreparationDrains(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
	flushContinuations: () => Promise<void>,
): Promise<void> {
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		for (const drain of scheduledDrains.splice(0)) void drain();
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes event-scheduled follow-up drains.
		await flushContinuations();
		if (scheduledDrains.length === 0) return;
	}
	expect(scheduledDrains).toEqual([]);
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}
