export type BridgeViewerRecoverySurface = 'comments' | 'file' | 'review';

export interface BridgeViewerRecoveryActionDisplaySpec {
	readonly accessibleName: 'Retry';
	readonly label: 'Retry';
	readonly tooltip: string;
}

const bridgeViewerRecoveryActionDisplaySpecs = {
	comments: {
		accessibleName: 'Retry',
		label: 'Retry',
		tooltip: 'Retry Comments recovery',
	},
	file: {
		accessibleName: 'Retry',
		label: 'Retry',
		tooltip: 'Retry File view recovery',
	},
	review: {
		accessibleName: 'Retry',
		label: 'Retry',
		tooltip: 'Retry Review metadata recovery',
	},
} as const satisfies Readonly<
	Record<BridgeViewerRecoverySurface, BridgeViewerRecoveryActionDisplaySpec>
>;

export function bridgeViewerRecoveryActionDisplaySpec(
	surface: BridgeViewerRecoverySurface,
): BridgeViewerRecoveryActionDisplaySpec {
	return bridgeViewerRecoveryActionDisplaySpecs[surface];
}
