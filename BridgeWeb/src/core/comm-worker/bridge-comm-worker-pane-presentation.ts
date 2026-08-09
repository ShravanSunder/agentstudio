import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

export type BridgeCommWorkerNativePaneActivity =
	BridgeProductPanePresentationFrame['nativeActivity'];
export type BridgeCommWorkerRefreshingLane =
	BridgeProductPanePresentationFrame['refreshingLanes'][number];

export interface BridgeCommWorkerPanePresentationSnapshot {
	readonly nativeActivity: BridgeCommWorkerNativePaneActivity;
	readonly presentationRevision: number;
	readonly refreshingLanes: readonly BridgeCommWorkerRefreshingLane[];
	readonly reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'];
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
	#nativeActivity: BridgeCommWorkerNativePaneActivity = 'dormant';
	#presentationRevision = 0;
	#refreshingLanes: readonly BridgeCommWorkerRefreshingLane[] = [];
	#reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'] = null;
	#workAbortController = abortedBridgeCommWorkerWorkController();
	#workAdmissionGeneration = 0;

	get admitsWork(): boolean {
		return this.#nativeActivity === 'foreground';
	}

	get snapshot(): BridgeCommWorkerPanePresentationSnapshot {
		return Object.freeze({
			nativeActivity: this.#nativeActivity,
			presentationRevision: this.#presentationRevision,
			refreshingLanes: Object.freeze([...this.#refreshingLanes]),
			reviewComparison: this.#reviewComparison,
			workAdmissionGeneration: this.#workAdmissionGeneration,
		});
	}

	get workSignal(): AbortSignal {
		return this.#workAbortController.signal;
	}

	apply(frame: BridgeProductPanePresentationFrame): BridgeCommWorkerPanePresentationApplyResult {
		if (frame.presentationRevision < this.#presentationRevision) {
			throw new Error('Bridge pane presentation revision is stale.');
		}
		if (frame.presentationRevision === this.#presentationRevision) {
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
		this.#nativeActivity = frame.nativeActivity;
		this.#presentationRevision = frame.presentationRevision;
		this.#refreshingLanes = Object.freeze([...frame.refreshingLanes]);
		this.#reviewComparison = immutableReviewComparison(frame.reviewComparison);

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
			frame.refreshingLanes.every((lane, index) => lane === this.#refreshingLanes[index]) &&
			reviewComparisonSignature(frame.reviewComparison) ===
				reviewComparisonSignature(this.#reviewComparison)
		);
	}
}

function immutableReviewComparison(
	reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'],
): BridgeProductPanePresentationFrame['reviewComparison'] {
	if (reviewComparison === null) return null;
	const targetCatalog = immutableTargetCatalog(reviewComparison.targetCatalog);
	return Object.freeze({
		activeTarget:
			reviewComparison.activeTarget === null
				? null
				: Object.freeze({ ...reviewComparison.activeTarget }),
		attempt: Object.freeze({ ...reviewComparison.attempt }),
		displayedSnapshot: Object.freeze({ ...reviewComparison.displayedSnapshot }),
		targetCatalog,
	});
}

function immutableTargetCatalog(
	targetCatalog: NonNullable<
		BridgeProductPanePresentationFrame['reviewComparison']
	>['targetCatalog'],
): NonNullable<BridgeProductPanePresentationFrame['reviewComparison']>['targetCatalog'] {
	if (targetCatalog === null) return null;
	const branches = targetCatalog.branches.map((branch) => Object.freeze({ ...branch }));
	Object.freeze(branches);
	return Object.freeze({
		branches,
		defaultTarget:
			targetCatalog.defaultTarget === null
				? null
				: Object.freeze({ ...targetCatalog.defaultTarget }),
	});
}

function reviewComparisonSignature(
	reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'],
): string {
	return JSON.stringify(reviewComparison);
}

function abortedBridgeCommWorkerWorkController(): AbortController {
	const controller = new AbortController();
	controller.abort();
	return controller;
}
