export interface BridgeReviewSelectionDiagnostic {
	initialSelectionRequestedCount: number;
	initialSelectionSchedulingAcceptedCount: number;
	selectionScheduledCount: number;
	selectionFirstFrameReachedCount: number;
	selectionSecondFrameReachedCount: number;
	selectionSubmittedCount: number;
	selectionDroppedCount: number;
}

export type BridgeReviewSelectionDiagnosticStage =
	| 'initial_selection_requested'
	| 'initial_selection_scheduling_accepted'
	| 'selection_scheduled'
	| 'selection_first_frame_reached'
	| 'selection_second_frame_reached'
	| 'selection_submitted'
	| 'selection_dropped';

declare global {
	interface Window {
		__bridgeReviewSelectionDiagnostic?: BridgeReviewSelectionDiagnostic;
	}
}

const countKeyByStage = {
	initial_selection_requested: 'initialSelectionRequestedCount',
	initial_selection_scheduling_accepted: 'initialSelectionSchedulingAcceptedCount',
	selection_dropped: 'selectionDroppedCount',
	selection_first_frame_reached: 'selectionFirstFrameReachedCount',
	selection_second_frame_reached: 'selectionSecondFrameReachedCount',
	selection_scheduled: 'selectionScheduledCount',
	selection_submitted: 'selectionSubmittedCount',
} as const satisfies Record<
	BridgeReviewSelectionDiagnosticStage,
	keyof BridgeReviewSelectionDiagnostic
>;

export function recordBridgeReviewSelectionDiagnosticStage(
	stage: BridgeReviewSelectionDiagnosticStage,
): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) {
		return;
	}
	diagnostic[countKeyByStage[stage]] += 1;
}

export function readBridgeReviewSelectionDiagnostic(): BridgeReviewSelectionDiagnostic | null {
	const diagnosticWindow = bridgeReviewSelectionDiagnosticWindow();
	if (diagnosticWindow === null) {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge diagnostic surface name.
	return diagnosticWindow.__bridgeReviewSelectionDiagnostic ?? null;
}

export function resetBridgeReviewSelectionDiagnosticForTesting(): void {
	const diagnosticWindow = bridgeReviewSelectionDiagnosticWindow();
	if (diagnosticWindow === null) {
		return;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge diagnostic surface name.
	delete diagnosticWindow.__bridgeReviewSelectionDiagnostic;
}

function ensureBridgeReviewSelectionDiagnostic(): BridgeReviewSelectionDiagnostic | null {
	const diagnosticWindow = bridgeReviewSelectionDiagnosticWindow();
	if (diagnosticWindow === null) {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge diagnostic surface name.
	diagnosticWindow.__bridgeReviewSelectionDiagnostic ??= {
		initialSelectionRequestedCount: 0,
		initialSelectionSchedulingAcceptedCount: 0,
		selectionDroppedCount: 0,
		selectionFirstFrameReachedCount: 0,
		selectionSecondFrameReachedCount: 0,
		selectionScheduledCount: 0,
		selectionSubmittedCount: 0,
	};
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge diagnostic surface name.
	return diagnosticWindow.__bridgeReviewSelectionDiagnostic;
}

function bridgeReviewSelectionDiagnosticWindow(): Window | null {
	const diagnosticWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (diagnosticWindow === undefined || typeof diagnosticWindow !== 'object') {
		return null;
	}
	return diagnosticWindow;
}
