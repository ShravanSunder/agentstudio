import type { BridgeViewerProductOnlyJourneyFailureCheckpoint } from './product-only-real-router-contract.ts';

export class BridgeViewerProductOnlyJourneyFailure extends Error {
	readonly checkpoint: BridgeViewerProductOnlyJourneyFailureCheckpoint;

	constructor(props: {
		readonly cause: unknown;
		readonly checkpoint: BridgeViewerProductOnlyJourneyFailureCheckpoint;
	}) {
		super(props.cause instanceof Error ? props.cause.message : String(props.cause));
		this.name = 'BridgeViewerProductOnlyJourneyFailure';
		this.checkpoint = props.checkpoint;
	}
}

export function bridgeViewerProductOnlyJourneyFailureFromError(
	error: unknown,
): BridgeViewerProductOnlyJourneyFailureCheckpoint | null {
	return error instanceof BridgeViewerProductOnlyJourneyFailure ? error.checkpoint : null;
}

export function bridgeViewerJourneyFailureCode(error: unknown): string {
	const message = error instanceof Error ? error.message : String(error);
	return /^[A-Z][A-Z0-9_]+/u.exec(message)?.[0] ?? 'UNCLASSIFIED_JOURNEY_FAILURE';
}
