import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeMainReviewRefreshLifecycleEvent } from './bridge-main-review-presentation-installation-gate.js';

export function recordBridgeReviewRefreshLifecycleTelemetry(props: {
	readonly event: BridgeMainReviewRefreshLifecycleEvent;
	readonly recorder?: BridgeTelemetryRecorder | undefined;
}): void {
	const phase = telemetryPhase(props.event);
	const stringAttributes: Record<string, string> = {
		'agentstudio.bridge.phase': phase,
		'agentstudio.bridge.plane': 'control',
		'agentstudio.bridge.priority': 'hot',
		'agentstudio.bridge.result': telemetryResult(props.event),
		'agentstudio.bridge.result_reason': telemetryResultReason(props.event),
		'agentstudio.bridge.slice': 'review_metadata',
		'agentstudio.bridge.transport': 'worker',
	};
	const numericAttributes: Record<string, number> = {};
	if ('generation' in props.event) {
		stringAttributes['agentstudio.bridge.review.refresh.presentation_class'] =
			props.event.presentationClass.kind;
		stringAttributes['agentstudio.bridge.review.refresh.promotion_reason'] =
			props.event.presentationClass.kind === 'promoted'
				? props.event.presentationClass.reason
				: 'none';
		numericAttributes['agentstudio.bridge.review.generation'] = props.event.generation;
		numericAttributes['agentstudio.bridge.review.refresh.affected_stable_file.count'] =
			props.event.affectedStableFileCount;
	}
	if (props.event.phase === 'installRequested' || props.event.phase === 'installTerminal') {
		stringAttributes['agentstudio.bridge.review.refresh.install_trigger'] =
			props.event.trigger === 'applyNow' ? 'apply_now' : 'automatic';
	}
	if (props.event.phase === 'cleanup') {
		numericAttributes['agentstudio.bridge.review.refresh.active_bank.count'] =
			props.event.activeBankCount;
		numericAttributes['agentstudio.bridge.review.refresh.candidate_bank.count'] =
			props.event.candidateBankCount;
	}
	props.recorder?.record({
		booleanAttributes: {},
		durationMilliseconds: null,
		name: 'performance.bridge.web.review_refresh_lifecycle',
		numericAttributes,
		scope: 'web',
		stringAttributes,
		traceContext: null,
	});
}

function telemetryPhase(event: BridgeMainReviewRefreshLifecycleEvent): string {
	switch (event.phase) {
		case 'candidateReady':
			return 'review_refresh_candidate_ready';
		case 'candidateHeld':
			return 'review_refresh_candidate_held';
		case 'candidateFailed':
			return 'review_refresh_candidate_failed';
		case 'installRequested':
			return 'review_refresh_install_requested';
		case 'installTerminal':
			return 'review_refresh_install_terminal';
		case 'candidateSuperseded':
			return 'review_refresh_candidate_superseded';
		case 'receiptFailed':
			return 'review_refresh_receipt_failed';
		case 'cleanup':
			return 'review_refresh_cleanup_terminal';
	}
	return unreachableReviewRefreshLifecycleEvent(event);
}

function telemetryResult(event: BridgeMainReviewRefreshLifecycleEvent): string {
	switch (event.phase) {
		case 'installRequested':
			return 'started';
		case 'installTerminal':
			return event.result;
		case 'receiptFailed':
			return 'failure';
		case 'candidateFailed':
			return 'failure';
		case 'candidateReady':
		case 'candidateHeld':
		case 'candidateSuperseded':
		case 'cleanup':
			return 'success';
	}
	return unreachableReviewRefreshLifecycleEvent(event);
}

function telemetryResultReason(event: BridgeMainReviewRefreshLifecycleEvent): string {
	switch (event.phase) {
		case 'installRequested':
			return event.trigger === 'applyNow' ? 'apply_now' : 'automatic';
		case 'installTerminal':
			switch (event.resultReason) {
				case 'admissionFailed':
					return 'admission_failed';
				case 'admissionRejected':
					return 'admission_rejected';
				case 'promotionStale':
					return 'promotion_stale';
				case 'none':
					return 'none';
			}
		case 'receiptFailed':
			return 'receipt_failed';
		case 'candidateFailed':
			return event.retryable ? 'retryable' : 'not_retryable';
		case 'cleanup':
			return event.reason === 'workerReplacement' ? 'worker_replacement' : 'close';
		case 'candidateReady':
		case 'candidateHeld':
		case 'candidateSuperseded':
			return 'none';
	}
	return unreachableReviewRefreshLifecycleEvent(event);
}

function unreachableReviewRefreshLifecycleEvent(value: never): never {
	throw new Error(`Unexpected Bridge Review refresh lifecycle event: ${String(value)}`);
}
