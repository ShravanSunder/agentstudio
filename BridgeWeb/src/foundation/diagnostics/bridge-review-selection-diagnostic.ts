export interface BridgeReviewSelectionDiagnostic {
	fileModeSendAttemptCount?: number;
	fileModeSendSynchronousFailureCount?: number;
	initialSelectionRequestedCount: number;
	initialSelectionSchedulingAcceptedCount: number;
	latestFileModeDispatchDisposition?: BridgeDiagnosticDispatchDisposition | null;
	latestFileSelectDispatchDisposition?: BridgeDiagnosticDispatchDisposition | null;
	latestFileSelectLifecycleState?: BridgeSelectLifecycleState;
	latestReviewSelectDispatchDisposition?: BridgeDiagnosticDispatchDisposition | null;
	latestReviewSelectLifecycleState?: BridgeSelectLifecycleState;
	nativeBootstrapInstallAcceptedCount?: number;
	nativeBootstrapInstallAttemptCount?: number;
	nativeBootstrapInstallCount?: number;
	nativeBootstrapInstallRejectedCount?: number;
	queuedCommandCount?: number;
	replacementRequestCount?: number;
	pageReadyState?: BridgePageReadyState;
	selectionScheduledCount: number;
	selectionFirstFrameReachedCount: number;
	selectionSecondFrameReachedCount: number;
	selectionSubmittedCount: number;
	selectionDroppedCount: number;
	sessionState?: BridgePaneCommWorkerSessionDiagnosticState;
}

export type BridgeDiagnosticDispatchDisposition =
	| 'dropped_detached'
	| 'queued_not_ready'
	| 'posted';

export type BridgeSelectLifecycleState =
	| 'not_sent'
	| 'pending'
	| 'acked'
	| 'failed'
	| 'timed_out'
	| 'superseded';

export type BridgePageReadyState = 'awaiting' | 'ready' | 'failed';

export type BridgePaneCommWorkerSessionDiagnosticState =
	| 'awaiting_bootstrap'
	| 'bootstrapping'
	| 'ready'
	| 'replacement_requested'
	| 'disposed';

export interface BridgePaneCommWorkerSessionDiagnosticSnapshot {
	readonly latestFileModeDispatchDisposition: BridgeDiagnosticDispatchDisposition | null;
	readonly latestFileSelectDispatchDisposition: BridgeDiagnosticDispatchDisposition | null;
	readonly latestReviewSelectDispatchDisposition: BridgeDiagnosticDispatchDisposition | null;
	readonly nativeBootstrapInstallCount: number;
	readonly queuedCommandCount: number;
	readonly replacementRequestCount: number;
	readonly state: BridgePaneCommWorkerSessionDiagnosticState;
}

export interface BridgePaneRuntimeDiagnosticSnapshot {
	readonly nativeBootstrapInstallAcceptedCount: number;
	readonly nativeBootstrapInstallAttemptCount: number;
	readonly nativeBootstrapInstallRejectedCount: number;
}

interface BridgeSelectionLifecycleRequestSnapshot {
	readonly command: string;
	readonly state: string;
	readonly surface: string;
}

export interface BridgeSelectionLifecycleSnapshot {
	readonly requestsById: Readonly<Record<string, BridgeSelectionLifecycleRequestSnapshot>>;
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

export function recordBridgeFileModeSendAttempt(): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	diagnostic.fileModeSendAttemptCount = (diagnostic.fileModeSendAttemptCount ?? 0) + 1;
	diagnostic.fileModeSendSynchronousFailureCount ??= 0;
}

export function recordBridgeFileModeSendSynchronousFailure(): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	diagnostic.fileModeSendSynchronousFailureCount =
		(diagnostic.fileModeSendSynchronousFailureCount ?? 0) + 1;
}

export function recordBridgePageReadyState(state: BridgePageReadyState): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	diagnostic.fileModeSendAttemptCount ??= 0;
	diagnostic.fileModeSendSynchronousFailureCount ??= 0;
	diagnostic.pageReadyState = state;
}

export function recordBridgeSelectionLifecycleSnapshot(props: {
	readonly requestId: string | null;
	readonly snapshot: BridgeSelectionLifecycleSnapshot;
	readonly surface: 'fileView' | 'review';
}): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	const request =
		props.requestId === null ? undefined : props.snapshot.requestsById[props.requestId];
	const state = bridgeSelectLifecycleState(
		request?.command === 'select' && request.surface === props.surface ? request.state : undefined,
	);
	if (props.surface === 'fileView') {
		diagnostic.latestFileSelectLifecycleState = state;
		return;
	}
	diagnostic.latestReviewSelectLifecycleState = state;
}

export function recordBridgePaneCommWorkerSessionDiagnosticSnapshot(
	snapshot: BridgePaneCommWorkerSessionDiagnosticSnapshot,
): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	diagnostic.latestFileModeDispatchDisposition = snapshot.latestFileModeDispatchDisposition;
	diagnostic.latestFileSelectDispatchDisposition = snapshot.latestFileSelectDispatchDisposition;
	diagnostic.latestReviewSelectDispatchDisposition = snapshot.latestReviewSelectDispatchDisposition;
	diagnostic.nativeBootstrapInstallCount = snapshot.nativeBootstrapInstallCount;
	diagnostic.queuedCommandCount = snapshot.queuedCommandCount;
	diagnostic.replacementRequestCount = snapshot.replacementRequestCount;
	diagnostic.sessionState = snapshot.state;
}

export function recordBridgePaneRuntimeDiagnosticSnapshot(
	snapshot: BridgePaneRuntimeDiagnosticSnapshot,
): void {
	const diagnostic = ensureBridgeReviewSelectionDiagnostic();
	if (diagnostic === null) return;
	diagnostic.nativeBootstrapInstallAcceptedCount = snapshot.nativeBootstrapInstallAcceptedCount;
	diagnostic.nativeBootstrapInstallAttemptCount = snapshot.nativeBootstrapInstallAttemptCount;
	diagnostic.nativeBootstrapInstallRejectedCount = snapshot.nativeBootstrapInstallRejectedCount;
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

function bridgeSelectLifecycleState(state: string | undefined): BridgeSelectLifecycleState {
	switch (state) {
		case 'pending':
		case 'acked':
		case 'failed':
		case 'timed_out':
		case 'superseded':
			return state;
		case undefined:
		default:
			return 'not_sent';
	}
}

function bridgeReviewSelectionDiagnosticWindow(): Window | null {
	const diagnosticWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (diagnosticWindow === undefined || typeof diagnosticWindow !== 'object') {
		return null;
	}
	return diagnosticWindow;
}
