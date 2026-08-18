import type { BridgePaneCommWorkerSessionDiagnosticSnapshot } from '../diagnostics/bridge-review-selection-diagnostic.js';
import type { BridgeTelemetryRecorder } from './bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';

export type BridgeViewerActivationCause =
	| 'context_switcher'
	| 'native_request'
	| 'review_file_corner';

export interface RecordBridgeViewerActivationRequestedTelemetrySampleProps {
	readonly activationSequence: number;
	readonly cause: BridgeViewerActivationCause;
	readonly fromViewer: 'file' | 'review';
	readonly sourceAvailable: boolean;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly traceContext: BridgeTraceContext | null;
	readonly viewer: 'file' | 'review';
}

export function recordBridgeViewerActivationRequestedTelemetrySample(
	props: RecordBridgeViewerActivationRequestedTelemetrySampleProps,
): void {
	if (props.telemetryRecorder === undefined || !props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.viewer_activation',
		durationMilliseconds: null,
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.activation.cause': props.cause,
			'agentstudio.bridge.activation.from_viewer': props.fromViewer,
			'agentstudio.bridge.phase': 'viewer_activation_requested',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'started',
			'agentstudio.bridge.slice': 'review_rpc',
			'agentstudio.bridge.transport': 'local',
			'agentstudio.bridge.viewer': props.viewer,
		},
		numericAttributes: {
			'agentstudio.bridge.activation.sequence': props.activationSequence,
		},
		booleanAttributes: {
			'agentstudio.bridge.activation.source_available': props.sourceAvailable,
		},
	});
}

export interface RecordBridgeFileSelectionCommitTelemetrySampleProps {
	readonly activationSequence: number;
	readonly selectionOrigin: BridgeViewerActivationCause;
	readonly sourceGeneration: number;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly traceContext: BridgeTraceContext | null;
}

export function recordBridgeFileSelectionCommitTelemetrySample(
	props: RecordBridgeFileSelectionCommitTelemetrySampleProps,
): void {
	if (props.telemetryRecorder === undefined || !props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.selection_commit',
		durationMilliseconds: null,
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': 'selection_commit',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.result_reason': 'none',
			'agentstudio.bridge.selection.origin': props.selectionOrigin,
			'agentstudio.bridge.slice': 'tree_prepare_input',
			'agentstudio.bridge.transport': 'local',
			'agentstudio.bridge.viewer': 'file',
		},
		numericAttributes: {
			'agentstudio.bridge.activation.sequence': props.activationSequence,
			'agentstudio.bridge.source.generation': props.sourceGeneration,
		},
		booleanAttributes: {},
	});
}

export function recordBridgeCommWorkerSessionTelemetrySample(props: {
	readonly snapshot: BridgePaneCommWorkerSessionDiagnosticSnapshot;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
}): void {
	if (props.telemetryRecorder === undefined || !props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.comm_worker_session',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'comm_worker_session_snapshot',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'local',
			'agentstudio.bridge.worker.file_mode_dispatch':
				props.snapshot.latestFileModeDispatchDisposition ?? 'none',
			'agentstudio.bridge.worker.file_select_dispatch':
				props.snapshot.latestFileSelectDispatchDisposition ?? 'none',
			'agentstudio.bridge.worker.review_select_dispatch':
				props.snapshot.latestReviewSelectDispatchDisposition ?? 'none',
			'agentstudio.bridge.worker.session_state': props.snapshot.state,
		},
		numericAttributes: {
			'agentstudio.bridge.worker.native_bootstrap_install.count':
				props.snapshot.nativeBootstrapInstallCount,
			'agentstudio.bridge.worker.queued_command.count': props.snapshot.queuedCommandCount,
			'agentstudio.bridge.worker.replacement_request.count': props.snapshot.replacementRequestCount,
		},
		booleanAttributes: {},
	});
}
