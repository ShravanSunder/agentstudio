import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeCommWorkerPanePresentationSnapshot } from './bridge-comm-worker-pane-presentation.js';
import type { BridgeWorkerContentAvailabilityPatchPayload } from './bridge-worker-contracts.js';

export type BridgeCommWorkerTelemetryTaskKind =
	| 'content_preparation'
	| 'message_handler'
	| 'product_control'
	| 'store_action';

export type BridgeCommWorkerTelemetryLane =
	| 'background'
	| 'file_view'
	| 'nearby'
	| 'selected'
	| 'speculative'
	| 'visible';

export type BridgeCommWorkerTelemetrySemanticClass =
	| 'demand'
	| 'lifecycle_control'
	| 'settlement'
	| 'urgent_action';

export type BridgeCommWorkerTelemetryAction =
	| 'applyContentReady'
	| 'applyContentTerminalAvailability'
	| 'applyFileViewSourceMutationFact'
	| 'applyFileViewSourceUpdateFact'
	| 'applyReviewInvalidationFact'
	| 'applyReviewRowMutationFact'
	| 'applyReviewSourceUpdateFact'
	| 'applySelectedFact'
	| 'applySelectedSourceChurnFact'
	| 'applyViewportFact';

export type BridgeCommWorkerTelemetryCommand =
	| 'activeViewerModeUpdate'
	| 'annotationCommand'
	| 'annotationOutputInspect'
	| 'annotationProjectionRetry'
	| 'fileDisplayResync'
	| 'fileQueryUpdate'
	| 'fileRefreshRetry'
	| 'fileSelectionReceipt'
	| 'fileCollectionSearch'
	| 'fileSourceDiscovery'
	| 'hover'
	| 'markFileViewed'
	| 'metadataInterestUpdate'
	| 'mode'
	| 'reviewIntakeReady'
	| 'reviewComparisonUpdate'
	| 'reviewComparisonTargetsQuery'
	| 'reviewComparisonTargetsQueryCancel'
	| 'reviewInvalidate'
	| 'reviewProjectionUpdate'
	| 'reviewPublicationInstallAdmit'
	| 'reviewPublicationInstalled'
	| 'renderDisposition'
	| 'select'
	| 'viewport';

export interface BridgeCommWorkerTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export type BridgeCommWorkerFileQueryDiagnosticEvent =
	| {
			readonly phase: 'command_received' | 'projection_published' | 'outcome_published';
	  }
	| { readonly phase: 'chunk_started'; readonly chunkIndex: number }
	| {
			readonly phase: 'chunk_completed';
			readonly chunkIndex: number;
			readonly evaluatedRowCount: number;
	  };

export type RecordBridgeCommWorkerFileQueryDiagnosticPhaseProps =
	BridgeCommWorkerFileQueryDiagnosticEvent & {
		readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder | undefined;
	};

export function recordBridgeCommWorkerFileQueryDiagnosticPhase(
	props: RecordBridgeCommWorkerFileQueryDiagnosticPhaseProps,
): void {
	const numericAttributes: Record<string, number> = {};
	if (props.phase === 'chunk_started' || props.phase === 'chunk_completed') {
		numericAttributes['agentstudio.bridge.worker.file_query.chunk.index'] = props.chunkIndex;
	}
	if (props.phase === 'chunk_completed') {
		numericAttributes['agentstudio.bridge.worker.file_query.evaluated_row.count'] =
			props.evaluatedRowCount;
	}
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.file_query.phase': props.phase,
		},
		numericAttributes,
		booleanAttributes: {},
	});
}

export type BridgeMainFileQueryDiagnosticPhase =
	| 'patch_received'
	| 'applier_batch_accepted'
	| 'applier_batch_rejected_stale'
	| 'applier_batch_rejected_protocol'
	| 'applier_batch_buffered_after_commit'
	| 'transaction_committed'
	| 'snapshot_published'
	| 'tree_stream_received'
	| 'tree_task_started'
	| 'tree_turn_completed'
	| 'tree_dom_commit';

export type BridgeMainFileQueryDiagnosticEvent =
	| {
			readonly phase:
				| 'patch_received'
				| 'applier_batch_accepted'
				| 'applier_batch_rejected_stale'
				| 'applier_batch_rejected_protocol'
				| 'applier_batch_buffered_after_commit'
				| 'transaction_committed';
			readonly batchCount: number;
			readonly batchIndex: number;
	  }
	| {
			readonly phase: 'snapshot_published';
			readonly displayItemCount: number;
			readonly treeRowCount: number;
	  }
	| {
			readonly phase: 'render_consumer_committed';
			readonly displayItemCount: number;
			readonly queryKeyMatchesInput: boolean;
			readonly treeRowCount: number;
	  }
	| {
			readonly phase: 'tree_stream_received' | 'tree_task_started' | 'tree_turn_completed';
	  }
	| {
			readonly phase: 'tree_dom_commit';
			readonly mountedPathRowCount: number;
			readonly viewportMeasured: boolean;
	  };

export type RecordBridgeMainFileQueryDiagnosticPhaseProps = BridgeMainFileQueryDiagnosticEvent & {
	readonly pageHidden: boolean;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder | undefined;
};

export function recordBridgeMainFileQueryDiagnosticPhase(
	props: RecordBridgeMainFileQueryDiagnosticPhaseProps,
): void {
	const numericAttributes: Record<string, number> = {};
	if (
		props.phase === 'patch_received' ||
		props.phase === 'applier_batch_accepted' ||
		props.phase === 'applier_batch_rejected_stale' ||
		props.phase === 'applier_batch_rejected_protocol' ||
		props.phase === 'applier_batch_buffered_after_commit' ||
		props.phase === 'transaction_committed'
	) {
		numericAttributes['agentstudio.bridge.file_query.diagnostic.batch.index'] = props.batchIndex;
		numericAttributes['agentstudio.bridge.file_query.diagnostic.batch.count'] = props.batchCount;
	} else if (props.phase === 'snapshot_published' || props.phase === 'render_consumer_committed') {
		numericAttributes['agentstudio.bridge.file_query.diagnostic.display_item.count'] =
			props.displayItemCount;
		numericAttributes['agentstudio.bridge.file_query.diagnostic.tree_row.count'] =
			props.treeRowCount;
	} else if (props.phase === 'tree_dom_commit') {
		numericAttributes['agentstudio.bridge.file_query.diagnostic.mounted_path_row.count'] =
			props.mountedPathRowCount;
	}
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.web.file_query_diagnostic',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.file_query.diagnostic.phase': props.phase,
		},
		numericAttributes,
		booleanAttributes: {
			'agentstudio.bridge.file_query.diagnostic.page_hidden': props.pageHidden,
			...(props.phase === 'render_consumer_committed'
				? {
						'agentstudio.bridge.file_query.diagnostic.query_key_matches_input':
							props.queryKeyMatchesInput,
					}
				: {}),
			...(props.phase === 'tree_dom_commit'
				? {
						'agentstudio.bridge.file_query.diagnostic.viewport_measured': props.viewportMeasured,
					}
				: {}),
		},
	});
}

type BridgeCommWorkerComparisonAttemptStatus =
	| 'absent'
	| 'pending'
	| 'selection_required'
	| 'settled'
	| 'unavailable';

export interface RecordBridgeCommWorkerPanePresentationTelemetryProps {
	readonly comparisonAttemptStatus: BridgeCommWorkerComparisonAttemptStatus;
	readonly disposition: 'applied' | 'idempotent_replay' | 'published';
	readonly panelOperation?: 'reset' | 'upsert';
	readonly phase: 'pane_presentation_applied' | 'panel_chrome_published';
	readonly presentationRevision: number;
	readonly publicationSequence?: number;
	readonly refreshingReview: boolean;
	readonly reviewGeneration?: number | undefined;
	readonly surface?: 'file' | 'review';
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder | undefined;
	readonly workerDerivationEpoch?: number;
}

export function bridgeCommWorkerComparisonTelemetryFacts(
	presentation: BridgeCommWorkerPanePresentationSnapshot,
): Pick<
	RecordBridgeCommWorkerPanePresentationTelemetryProps,
	'comparisonAttemptStatus' | 'reviewGeneration'
> {
	const attempt = presentation.reviewComparison?.attempt;
	const comparisonAttemptStatus =
		attempt === undefined
			? 'absent'
			: attempt.status === 'selectionRequired'
				? 'selection_required'
				: attempt.status;
	return {
		comparisonAttemptStatus,
		...(attempt?.status === 'pending' || attempt?.status === 'settled'
			? { reviewGeneration: attempt.reviewGeneration }
			: {}),
	};
}

export function recordBridgeCommWorkerPanePresentationTelemetry(
	props: RecordBridgeCommWorkerPanePresentationTelemetryProps,
): void {
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.web.pane_presentation',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.comparison.attempt.status': props.comparisonAttemptStatus,
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.presentation.disposition': props.disposition,
			'agentstudio.bridge.result':
				props.disposition === 'idempotent_replay' ? 'unchanged' : 'success',
			'agentstudio.bridge.slice': 'review_metadata',
			'agentstudio.bridge.transport': 'worker',
			...(props.panelOperation === undefined
				? {}
				: { 'agentstudio.bridge.panel.operation': props.panelOperation }),
			...(props.surface === undefined ? {} : { 'agentstudio.bridge.viewer': props.surface }),
		},
		numericAttributes: {
			'agentstudio.bridge.presentation.revision': props.presentationRevision,
			...(props.publicationSequence === undefined
				? {}
				: {
						'agentstudio.bridge.presentation.publication_sequence': props.publicationSequence,
					}),
			...(props.reviewGeneration === undefined
				? {}
				: { 'agentstudio.bridge.review.generation': props.reviewGeneration }),
			...(props.workerDerivationEpoch === undefined
				? {}
				: {
						'agentstudio.bridge.worker.derivation_epoch': props.workerDerivationEpoch,
					}),
		},
		booleanAttributes: {
			'agentstudio.bridge.refreshing.review': props.refreshingReview,
		},
	});
}

export type BridgeCommWorkerSelectedContentDropReason =
	| 'stale_after_fetch'
	| 'stale_before_fetch'
	| 'stale_before_publish';

export interface RecordBridgeCommWorkerTaskTelemetryProps {
	readonly action?: BridgeCommWorkerTelemetryAction;
	readonly command?: BridgeCommWorkerTelemetryCommand;
	readonly durationMilliseconds: number;
	readonly fileMetadataSelectedPathResolved?: boolean;
	readonly lane: BridgeCommWorkerTelemetryLane;
	readonly payloadClass?: string;
	readonly queueWaitMilliseconds?: number;
	readonly result?: 'failed' | 'success' | 'unavailable';
	readonly resultReason?: BridgeCommWorkerTelemetryResultReason;
	readonly semanticClass?: BridgeCommWorkerTelemetrySemanticClass;
	readonly sourceEpoch?: number;
	readonly taskKind: BridgeCommWorkerTelemetryTaskKind;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly touchedKeyCount?: number;
	readonly patchCount?: number;
	readonly workKind?: string;
}

export function recordBridgeCommWorkerTaskTelemetry(
	props: RecordBridgeCommWorkerTaskTelemetryProps,
): void {
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds: Math.max(0, props.durationMilliseconds),
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': bridgeCommWorkerTaskPriority(props.lane),
			'agentstudio.bridge.result': props.result ?? 'success',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': props.lane,
			'agentstudio.bridge.worker.task_kind': props.taskKind,
			...(props.action === undefined ? {} : { 'agentstudio.bridge.worker.action': props.action }),
			...(props.command === undefined
				? {}
				: { 'agentstudio.bridge.worker.command': props.command }),
			...(props.payloadClass === undefined
				? {}
				: { 'agentstudio.bridge.worker.payload_class': props.payloadClass }),
			...(props.resultReason === undefined
				? {}
				: { 'agentstudio.bridge.result_reason': props.resultReason }),
			...(props.semanticClass === undefined
				? {}
				: { 'agentstudio.bridge.worker.semantic_class': props.semanticClass }),
			...(props.workKind === undefined
				? {}
				: { 'agentstudio.bridge.worker.work_kind': props.workKind }),
		},
		numericAttributes: {
			'agentstudio.bridge.worker.handler_duration_ms': Math.max(0, props.durationMilliseconds),
			...(props.queueWaitMilliseconds === undefined
				? {}
				: {
						'agentstudio.bridge.worker.queue_wait_ms': Math.max(0, props.queueWaitMilliseconds),
					}),
			...(props.sourceEpoch === undefined
				? {}
				: { 'agentstudio.bridge.worker.source_epoch': props.sourceEpoch }),
			...(props.touchedKeyCount === undefined
				? {}
				: {
						'agentstudio.bridge.worker.touched_key_count': props.touchedKeyCount,
					}),
			...(props.patchCount === undefined
				? {}
				: { 'agentstudio.bridge.worker.patch_count': props.patchCount }),
		},
		booleanAttributes:
			props.fileMetadataSelectedPathResolved === undefined
				? {}
				: {
						'agentstudio.bridge.worker.file_metadata_selected_path_resolved':
							props.fileMetadataSelectedPathResolved,
					},
	});
}

export interface RecordBridgeCommWorkerSelectedContentDroppedTelemetryProps {
	readonly dropReason: BridgeCommWorkerSelectedContentDropReason;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export function recordBridgeCommWorkerSelectedContentDroppedTelemetry(
	props: RecordBridgeCommWorkerSelectedContentDroppedTelemetryProps,
): void {
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.web.selected_content_dropped',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.drop_reason': props.dropReason,
			'agentstudio.bridge.phase': 'selected_content_dropped',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'dropped',
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.transport': 'content',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

type BridgeCommWorkerTelemetryResultReason = NonNullable<
	BridgeWorkerContentAvailabilityPatchPayload['reason']
>;

function bridgeCommWorkerTaskPriority(lane: BridgeCommWorkerTelemetryLane): string {
	return lane === 'selected' ? 'hot' : 'warm';
}
