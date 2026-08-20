import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

export type BridgeCommWorkerNativePaneActivity =
	BridgeProductPanePresentationFrame['nativeActivity'];
export type BridgeCommWorkerRefreshingLane =
	BridgeProductPanePresentationFrame['refreshingLanes'][number];

export interface BridgeCommWorkerPanePresentationSnapshot {
	readonly nativeActivity: BridgeCommWorkerNativePaneActivity;
	readonly fileRefreshFailure: BridgeProductPanePresentationFrame['fileRefreshFailure'];
	readonly presentationRevision: number;
	readonly refreshingLanes: readonly BridgeCommWorkerRefreshingLane[];
	readonly reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'];
	readonly workAdmissionGeneration: number;
}

export type BridgeCommWorkerPanePresentationDisposition = 'applied' | 'idempotentReplay';
export type BridgeCommWorkerReviewComparisonDisposition = 'applied' | 'idempotentReplay' | 'stale';

export interface BridgeCommWorkerPanePresentationApplyResult {
	readonly disposition: BridgeCommWorkerPanePresentationDisposition;
	readonly enteredForeground: boolean;
	readonly leftForeground: boolean;
	readonly snapshot: BridgeCommWorkerPanePresentationSnapshot;
}

export class BridgeCommWorkerPanePresentationAuthority {
	#nativeActivity: BridgeCommWorkerNativePaneActivity = 'dormant';
	#fileRefreshFailure: BridgeProductPanePresentationFrame['fileRefreshFailure'] = null;
	#presentationRevision = 0;
	#reviewComparisonRevision = 0;
	#refreshingLanes: readonly BridgeCommWorkerRefreshingLane[] = [];
	#reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'] = null;
	#workAbortController = abortedBridgeCommWorkerWorkController();
	#workAdmissionGeneration = 0;

	get admitsWork(): boolean {
		return this.#nativeActivity === 'foreground';
	}

	get snapshot(): BridgeCommWorkerPanePresentationSnapshot {
		return Object.freeze({
			fileRefreshFailure: this.#fileRefreshFailure,
			nativeActivity: this.#nativeActivity,
			presentationRevision: Math.max(this.#presentationRevision, this.#reviewComparisonRevision),
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
			if (
				!this.#matchesCurrentFrameActivity(frame) ||
				(frame.presentationRevision === this.#reviewComparisonRevision &&
					reviewComparisonSignature(frame.reviewComparison) !==
						reviewComparisonSignature(this.#reviewComparison))
			) {
				throw new Error('Bridge pane presentation revision was reused with changed state.');
			}
			this.reconcileReviewComparison(frame.presentationRevision, frame.reviewComparison);
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
		this.#fileRefreshFailure = immutableFileRefreshFailure(frame.fileRefreshFailure);
		this.reconcileReviewComparison(frame.presentationRevision, frame.reviewComparison);

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

	reconcileReviewComparison(
		presentationRevision: number,
		reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'],
	): BridgeCommWorkerReviewComparisonDisposition {
		if (presentationRevision < this.#reviewComparisonRevision) return 'stale';
		if (presentationRevision === this.#reviewComparisonRevision) {
			if (
				reviewComparisonSignature(reviewComparison) !==
				reviewComparisonSignature(this.#reviewComparison)
			) {
				throw new Error('Bridge Review comparison revision was reused with changed state.');
			}
			return 'idempotentReplay';
		}
		this.#reviewComparisonRevision = presentationRevision;
		this.#reviewComparison = immutableReviewComparison(reviewComparison);
		return 'applied';
	}

	#matchesCurrentFrameActivity(frame: BridgeProductPanePresentationFrame): boolean {
		return (
			frame.nativeActivity === this.#nativeActivity &&
			JSON.stringify(frame.fileRefreshFailure) === JSON.stringify(this.#fileRefreshFailure) &&
			frame.refreshingLanes.length === this.#refreshingLanes.length &&
			frame.refreshingLanes.every((lane, index) => lane === this.#refreshingLanes[index])
		);
	}
}

function immutableFileRefreshFailure(
	failure: BridgeProductPanePresentationFrame['fileRefreshFailure'],
): BridgeProductPanePresentationFrame['fileRefreshFailure'] {
	return failure === null ? null : Object.freeze({ ...failure });
}

function immutableReviewComparison(
	reviewComparison: BridgeProductPanePresentationFrame['reviewComparison'],
): BridgeProductPanePresentationFrame['reviewComparison'] {
	if (reviewComparison === null) return null;
	return Object.freeze({
		activeTarget:
			reviewComparison.activeTarget === null
				? null
				: Object.freeze({ ...reviewComparison.activeTarget }),
		attempt: Object.freeze({ ...reviewComparison.attempt }),
		displayedSnapshot: Object.freeze({ ...reviewComparison.displayedSnapshot }),
		repositoryDefaultTarget:
			reviewComparison.repositoryDefaultTarget === null
				? null
				: Object.freeze({ ...reviewComparison.repositoryDefaultTarget }),
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
