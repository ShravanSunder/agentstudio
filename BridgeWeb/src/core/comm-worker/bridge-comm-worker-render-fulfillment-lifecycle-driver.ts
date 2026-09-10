import type { BridgeCommWorkerRenderFulfillmentLifecycleAdvance } from './bridge-comm-worker-command-handler-contracts.js';

export type BridgeCommWorkerRenderFulfillmentSurface = 'file' | 'review';
type BridgeCommWorkerRenderFulfillmentAdvanceBySurface = Readonly<
	Record<
		BridgeCommWorkerRenderFulfillmentSurface,
		(atMilliseconds: number) => BridgeCommWorkerRenderFulfillmentLifecycleAdvance
	>
>;
type BridgeCommWorkerRenderFulfillmentScheduleWake = (
	delayMilliseconds: number,
	wake: () => void,
) => () => void;

export class BridgeCommWorkerRenderFulfillmentLifecycleDriver {
	readonly #advanceBySurface: BridgeCommWorkerRenderFulfillmentAdvanceBySurface;
	readonly #cancelWakeBySurface: Record<
		BridgeCommWorkerRenderFulfillmentSurface,
		(() => void) | null
	> = { file: null, review: null };
	readonly #needsPreparationDrain: () => boolean;
	readonly #now: () => number;
	readonly #requestPreparationDrain: () => void;
	readonly #scheduleWake: BridgeCommWorkerRenderFulfillmentScheduleWake;

	constructor(props: {
		readonly advanceBySurface: BridgeCommWorkerRenderFulfillmentAdvanceBySurface;
		readonly needsPreparationDrain: () => boolean;
		readonly now: () => number;
		readonly requestPreparationDrain: () => void;
		readonly scheduleWake: BridgeCommWorkerRenderFulfillmentScheduleWake;
	}) {
		this.#advanceBySurface = props.advanceBySurface;
		this.#needsPreparationDrain = props.needsPreparationDrain;
		this.#now = props.now;
		this.#requestPreparationDrain = props.requestPreparationDrain;
		this.#scheduleWake = props.scheduleWake;
	}

	advance(surface: BridgeCommWorkerRenderFulfillmentSurface): void {
		const nowMilliseconds = this.#now();
		const lifecycleAdvance = this.#advanceBySurface[surface](nowMilliseconds);
		this.#cancelWakeBySurface[surface]?.();
		this.#cancelWakeBySurface[surface] = null;
		if (lifecycleAdvance.nextWakeAtMilliseconds === null) return;
		this.#cancelWakeBySurface[surface] = this.#scheduleWake(
			Math.max(0, lifecycleAdvance.nextWakeAtMilliseconds - nowMilliseconds),
			(): void => {
				this.#cancelWakeBySurface[surface] = null;
				this.advance(surface);
				if (this.#needsPreparationDrain()) this.#requestPreparationDrain();
			},
		);
	}
}
