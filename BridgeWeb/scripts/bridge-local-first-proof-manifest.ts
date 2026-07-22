export const bridgeLocalFirstProofFamilies = [
	'review-selection-feedback',
	'review-selected-readable',
	'review-terminal-availability',
	'review-rail-scroll',
	'review-code-view-scroll',
	'file-selection-feedback',
	'file-selected-readable',
	'file-terminal-availability',
	'file-rail-scroll',
	'file-content-scroll',
] as const;

export const bridgeLocalFirstProofSourceCacheStates = [
	'fresh-display',
	'worker-cache',
	'cold-miss',
	'cached-terminal',
	'cold-terminal',
	'resident-rows',
	'resident-window',
	'continuation-miss',
	'resident-prefix',
] as const;

export const bridgeLocalFirstProofRuntimes = [
	'controlled_dev_chromium',
	'packaged_wkwebview',
] as const;

export const bridgeLocalFirstProofTelemetryStates = ['off', 'on'] as const;

export const bridgeLocalFirstProofInternalSlo = Object.freeze({
	commQueueP95Milliseconds: 16,
	commQueueP99Milliseconds: 32,
	mainToPierreP95Milliseconds: 4,
	mainToPierreP99Milliseconds: 8,
	maximumOwnedSynchronousSliceMilliseconds: 8,
	mainThreadLongTaskMilliseconds: 50,
});

export type BridgeLocalFirstProofFamily = (typeof bridgeLocalFirstProofFamilies)[number];
export type BridgeLocalFirstProofSourceCacheState =
	(typeof bridgeLocalFirstProofSourceCacheStates)[number];
export type BridgeLocalFirstProofRuntime = (typeof bridgeLocalFirstProofRuntimes)[number];
export type BridgeLocalFirstProofTelemetryState =
	(typeof bridgeLocalFirstProofTelemetryStates)[number];

export type BridgeLocalFirstProofEndpointKind =
	| 'selection_feedback'
	| 'selected_readable'
	| 'terminal_availability'
	| 'rail_scroll'
	| 'content_scroll';

export type BridgeLocalFirstProofCachePreparationRequirement =
	| 'painted_residency'
	| 'worker_cache_seeded'
	| 'cold_cache_reset'
	| 'terminal_residency'
	| 'resident_rows'
	| 'resident_window'
	| 'continuation_reset'
	| 'resident_prefix';

export interface BridgeLocalFirstProofManifestRow {
	readonly manifestRowId: string;
	readonly family: BridgeLocalFirstProofFamily;
	readonly sourceCacheState: BridgeLocalFirstProofSourceCacheState;
}

export interface BridgeLocalFirstProofCellContract extends BridgeLocalFirstProofManifestRow {
	readonly cellId: string;
	readonly p99BudgetMilliseconds: number;
	readonly attemptDeadlineMilliseconds: number;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly telemetryState: BridgeLocalFirstProofTelemetryState;
}

export interface BridgeLocalFirstProofCellApplicability {
	readonly cellId: string;
	readonly endpointKind: BridgeLocalFirstProofEndpointKind;
	readonly lifecycleVariant: BridgeLocalFirstProofSourceCacheState;
	readonly cachePreparationRequirement: BridgeLocalFirstProofCachePreparationRequirement;
	readonly selectedCommQueue: 'forbidden' | 'required';
	readonly pierreSubmission: 'forbidden' | 'required';
}

function manifestRow(
	family: BridgeLocalFirstProofFamily,
	sourceCacheState: BridgeLocalFirstProofSourceCacheState,
): BridgeLocalFirstProofManifestRow {
	return Object.freeze({
		manifestRowId: `${family}--${sourceCacheState}`,
		family,
		sourceCacheState,
	});
}

export const bridgeLocalFirstProofManifestRows: readonly BridgeLocalFirstProofManifestRow[] =
	Object.freeze([
		manifestRow('review-selection-feedback', 'fresh-display'),
		manifestRow('review-selection-feedback', 'worker-cache'),
		manifestRow('review-selection-feedback', 'cold-miss'),
		manifestRow('review-selected-readable', 'fresh-display'),
		manifestRow('review-selected-readable', 'worker-cache'),
		manifestRow('review-selected-readable', 'cold-miss'),
		manifestRow('review-terminal-availability', 'cached-terminal'),
		manifestRow('review-terminal-availability', 'cold-terminal'),
		manifestRow('review-rail-scroll', 'resident-rows'),
		manifestRow('review-code-view-scroll', 'resident-window'),
		manifestRow('review-code-view-scroll', 'continuation-miss'),
		manifestRow('file-selection-feedback', 'fresh-display'),
		manifestRow('file-selection-feedback', 'worker-cache'),
		manifestRow('file-selection-feedback', 'cold-miss'),
		manifestRow('file-selected-readable', 'fresh-display'),
		manifestRow('file-selected-readable', 'worker-cache'),
		manifestRow('file-selected-readable', 'cold-miss'),
		manifestRow('file-terminal-availability', 'cached-terminal'),
		manifestRow('file-terminal-availability', 'cold-terminal'),
		manifestRow('file-rail-scroll', 'resident-rows'),
		manifestRow('file-content-scroll', 'resident-prefix'),
	]);

export function bridgeLocalFirstProofCellId(props: {
	readonly manifestRowId: string;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly telemetryState: BridgeLocalFirstProofTelemetryState;
}): string {
	return `${props.manifestRowId}--${props.runtime}--telemetry-${props.telemetryState}`;
}

export function bridgeLocalFirstProofP99BudgetMilliseconds(props: {
	readonly family: BridgeLocalFirstProofFamily;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly sourceCacheState: BridgeLocalFirstProofSourceCacheState;
}): number {
	if (props.family.endsWith('selection-feedback')) {
		return 32;
	}
	if (
		props.family.endsWith('selected-readable') &&
		(props.sourceCacheState === 'fresh-display' || props.sourceCacheState === 'worker-cache')
	) {
		return 32;
	}
	return props.runtime === 'controlled_dev_chromium' ? 100 : 200;
}

export function bridgeLocalFirstProofAttemptDeadlineMilliseconds(
	p99BudgetMilliseconds: number,
): number {
	return Math.max(1_000, 5 * p99BudgetMilliseconds);
}

export const bridgeLocalFirstProofCells: readonly BridgeLocalFirstProofCellContract[] =
	Object.freeze(
		bridgeLocalFirstProofManifestRows.flatMap((row) =>
			bridgeLocalFirstProofRuntimes.flatMap((runtime) =>
				bridgeLocalFirstProofTelemetryStates.map((telemetryState) => {
					const p99BudgetMilliseconds = bridgeLocalFirstProofP99BudgetMilliseconds({
						family: row.family,
						runtime,
						sourceCacheState: row.sourceCacheState,
					});
					return Object.freeze({
						...row,
						cellId: bridgeLocalFirstProofCellId({
							manifestRowId: row.manifestRowId,
							runtime,
							telemetryState,
						}),
						p99BudgetMilliseconds,
						attemptDeadlineMilliseconds:
							bridgeLocalFirstProofAttemptDeadlineMilliseconds(p99BudgetMilliseconds),
						runtime,
						telemetryState,
					});
				}),
			),
		),
	);

function endpointKindForFamily(
	family: BridgeLocalFirstProofFamily,
): BridgeLocalFirstProofEndpointKind {
	if (family.endsWith('selection-feedback')) return 'selection_feedback';
	if (family.endsWith('selected-readable')) return 'selected_readable';
	if (family.endsWith('terminal-availability')) return 'terminal_availability';
	if (family.endsWith('rail-scroll')) return 'rail_scroll';
	return 'content_scroll';
}

// oxlint-disable-next-line typescript/consistent-return -- The closed union is exhausted below.
function cachePreparationRequirementForState(
	sourceCacheState: BridgeLocalFirstProofSourceCacheState,
): BridgeLocalFirstProofCachePreparationRequirement {
	switch (sourceCacheState) {
		case 'fresh-display':
			return 'painted_residency';
		case 'worker-cache':
			return 'worker_cache_seeded';
		case 'cold-miss':
		case 'cold-terminal':
			return 'cold_cache_reset';
		case 'cached-terminal':
			return 'terminal_residency';
		case 'resident-rows':
			return 'resident_rows';
		case 'resident-window':
			return 'resident_window';
		case 'continuation-miss':
			return 'continuation_reset';
		case 'resident-prefix':
			return 'resident_prefix';
	}
}

function pierreSubmissionForRow(
	row: BridgeLocalFirstProofManifestRow,
): BridgeLocalFirstProofCellApplicability['pierreSubmission'] {
	if (
		row.family.endsWith('selected-readable') &&
		(row.sourceCacheState === 'worker-cache' || row.sourceCacheState === 'cold-miss')
	) {
		return 'required';
	}
	if (row.family === 'review-code-view-scroll' && row.sourceCacheState === 'continuation-miss') {
		return 'required';
	}
	return 'forbidden';
}

function selectedCommQueueForFamily(
	family: BridgeLocalFirstProofFamily,
): BridgeLocalFirstProofCellApplicability['selectedCommQueue'] {
	return family.includes('selection') ||
		family.includes('selected') ||
		family.includes('terminal-availability')
		? 'required'
		: 'forbidden';
}

export const bridgeLocalFirstProofApplicabilityByCellId: ReadonlyMap<
	string,
	BridgeLocalFirstProofCellApplicability
> = new Map(
	bridgeLocalFirstProofCells.map((cell) => [
		cell.cellId,
		Object.freeze({
			cellId: cell.cellId,
			endpointKind: endpointKindForFamily(cell.family),
			lifecycleVariant: cell.sourceCacheState,
			cachePreparationRequirement: cachePreparationRequirementForState(cell.sourceCacheState),
			selectedCommQueue: selectedCommQueueForFamily(cell.family),
			pierreSubmission: pierreSubmissionForRow(cell),
		}),
	]),
);

export const bridgeLocalFirstProofRequiredCellCount = 84;
export const bridgeLocalFirstProofRequiredLaunchesPerCell = 3;
export const bridgeLocalFirstProofRequiredLaunchCount = 252;
export const bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch = 100;
export const bridgeLocalFirstProofMinimumMeasuredAttemptCount = 25_200;
