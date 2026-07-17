import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

export type BridgeCommWorkerNativePaneActivity =
	BridgeProductPanePresentationFrame['nativeActivity'];
export type BridgeCommWorkerRefreshingLane =
	BridgeProductPanePresentationFrame['refreshingLanes'][number];

export interface BridgeCommWorkerPanePresentationSnapshot {
	readonly activityRevision: number;
	readonly nativeActivity: BridgeCommWorkerNativePaneActivity;
	readonly refreshingLanes: readonly BridgeCommWorkerRefreshingLane[];
	readonly workAdmissionGeneration: number;
}

export type BridgeCommWorkerPanePresentationDisposition = 'applied' | 'idempotentReplay';

export interface BridgeCommWorkerPanePresentationApplyResult {
	readonly disposition: BridgeCommWorkerPanePresentationDisposition;
	readonly enteredForeground: boolean;
	readonly leftForeground: boolean;
	readonly snapshot: BridgeCommWorkerPanePresentationSnapshot;
}

export class BridgeCommWorkerPanePresentationAuthority {
	#activityRevision = 0;
	#nativeActivity: BridgeCommWorkerNativePaneActivity = 'dormant';
	#refreshingLanes: readonly BridgeCommWorkerRefreshingLane[] = [];
	#workAbortController = abortedBridgeCommWorkerWorkController();
	#workAdmissionGeneration = 0;

	get admitsWork(): boolean {
		return this.#nativeActivity === 'foreground';
	}

	get snapshot(): BridgeCommWorkerPanePresentationSnapshot {
		return Object.freeze({
			activityRevision: this.#activityRevision,
			nativeActivity: this.#nativeActivity,
			refreshingLanes: Object.freeze([...this.#refreshingLanes]),
			workAdmissionGeneration: this.#workAdmissionGeneration,
		});
	}

	get workSignal(): AbortSignal {
		return this.#workAbortController.signal;
	}

	apply(frame: BridgeProductPanePresentationFrame): BridgeCommWorkerPanePresentationApplyResult {
		if (frame.activityRevision < this.#activityRevision) {
			throw new Error('Bridge pane presentation revision is stale.');
		}
		if (frame.activityRevision === this.#activityRevision) {
			if (!this.#matchesCurrentFrame(frame)) {
				throw new Error('Bridge pane presentation revision was reused with changed state.');
			}
			return {
				disposition: 'idempotentReplay',
				enteredForeground: false,
				leftForeground: false,
				snapshot: this.snapshot,
			};
		}

		const wasForeground = this.admitsWork;
		const willBeForeground = frame.nativeActivity === 'foreground';
		if (wasForeground && !willBeForeground) {
			this.#workAdmissionGeneration += 1;
			this.#workAbortController.abort();
		} else if (!wasForeground && willBeForeground) {
			this.#workAdmissionGeneration += 1;
			this.#workAbortController = new AbortController();
		}
		this.#activityRevision = frame.activityRevision;
		this.#nativeActivity = frame.nativeActivity;
		this.#refreshingLanes = Object.freeze([...frame.refreshingLanes]);

		return {
			disposition: 'applied',
			enteredForeground: !wasForeground && willBeForeground,
			leftForeground: wasForeground && !willBeForeground,
			snapshot: this.snapshot,
		};
	}

	isCurrentWorkAdmission(generation: number): boolean {
		return this.admitsWork && generation === this.#workAdmissionGeneration;
	}

	#matchesCurrentFrame(frame: BridgeProductPanePresentationFrame): boolean {
		return (
			frame.nativeActivity === this.#nativeActivity &&
			frame.refreshingLanes.length === this.#refreshingLanes.length &&
			frame.refreshingLanes.every((lane, index) => lane === this.#refreshingLanes[index])
		);
	}
}

function abortedBridgeCommWorkerWorkController(): AbortController {
	const controller = new AbortController();
	controller.abort();
	return controller;
}
