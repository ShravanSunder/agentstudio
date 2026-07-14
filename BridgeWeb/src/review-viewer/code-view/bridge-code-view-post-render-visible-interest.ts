export interface BridgeCodeViewPostRenderVisibleInterestPublisher {
	readonly cancel: () => void;
	readonly schedule: () => void;
}

export interface CreateBridgeCodeViewPostRenderVisibleInterestPublisherProps {
	readonly publishSettledWindow: () => void;
	readonly queueMicrotask: (callback: () => void) => void;
}

/**
 * Coalesces Pierre's per-item post-render callbacks into one settled-window read.
 * Pierre finishes the synchronous CodeView reconciliation before the queued
 * microtask runs, so getRenderedItems() observes the new window rather than the
 * pre-render window exposed to scroll listeners.
 */
export function createBridgeCodeViewPostRenderVisibleInterestPublisher(
	props: CreateBridgeCodeViewPostRenderVisibleInterestPublisherProps,
): BridgeCodeViewPostRenderVisibleInterestPublisher {
	let generation = 0;
	let publishScheduled = false;

	return {
		cancel: (): void => {
			generation += 1;
			publishScheduled = false;
		},
		schedule: (): void => {
			if (publishScheduled) return;
			publishScheduled = true;
			const scheduledGeneration = generation;
			props.queueMicrotask((): void => {
				if (scheduledGeneration !== generation) return;
				publishScheduled = false;
				props.publishSettledWindow();
			});
		},
	};
}
