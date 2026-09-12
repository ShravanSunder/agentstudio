import type { BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest } from './bridge-comm-worker-command-handler-contracts.js';
import type { BridgeWorkerFileViewContentPreparationOutcome } from './bridge-comm-worker-file-view-runtime.js';
import type { BridgeSelectedFileContentOperation } from './bridge-comm-worker-selected-file-content-operation.js';
import type { BridgeCommWorkerSelectedFileContentOperationController } from './bridge-comm-worker-selected-file-content-operation.js';
import {
	recordBridgeOperationLifecycleTelemetry,
	type BridgeOperationLifecyclePhase,
	type BridgeOperationLifecycleTelemetryRecorder,
} from './bridge-operation-lifecycle-telemetry.js';
import type { BridgeWorkerRenderDisposition } from './bridge-worker-render-fulfillment.js';

export class BridgeCommWorkerSelectedFileLifecycleTelemetry {
	readonly #recorder: BridgeOperationLifecycleTelemetryRecorder | undefined;

	constructor(recorder?: BridgeOperationLifecycleTelemetryRecorder) {
		this.#recorder = recorder;
	}

	admitted(operation: BridgeSelectedFileContentOperation): void {
		for (const phase of [
			'worker_application_started',
			'file_content_operation_started',
			'file_descriptor_wait_started',
		] as const) {
			this.#record(operation, phase, 'started');
		}
	}

	descriptorReady(operation: BridgeSelectedFileContentOperation): void {
		this.#record(operation, 'file_descriptor_wait_terminal', 'success');
		this.#record(operation, 'content_operation_started', 'started');
	}

	contentReady(operation: BridgeSelectedFileContentOperation): void {
		this.#record(operation, 'content_operation_terminal', 'success');
	}

	handlePreparationOutcome(props: {
		readonly controller: BridgeCommWorkerSelectedFileContentOperationController;
		readonly operation: BridgeSelectedFileContentOperation;
		readonly outcome: BridgeWorkerFileViewContentPreparationOutcome;
	}): boolean {
		if (props.outcome.kind === 'renderPublication') {
			this.contentReady(props.operation);
			props.controller.bindRenderReceipt({
				generation: props.operation.generation,
				receiptIdentity: props.outcome.publication.receiptIdentity,
			});
			const renderOperation = props.controller.current;
			if (renderOperation !== null) this.renderStarted(renderOperation);
			return false;
		}
		if (props.outcome.kind === 'paintedResidency') this.paintedResidency(props.operation);
		if (props.outcome.kind === 'terminal') this.preparationFailed(props.operation);
		return props.controller.settle(props.operation.generation);
	}

	renderStarted(operation: BridgeSelectedFileContentOperation): void {
		for (const phase of [
			'render_operation_started',
			'main_thread_install_started',
			'paint_fulfillment_started',
		] as const) {
			this.#record(operation, phase, 'started', operation.renderStageAttempt);
		}
	}

	paintedResidency(operation: BridgeSelectedFileContentOperation): void {
		for (const phase of [
			'main_thread_install_terminal',
			'render_operation_terminal',
			'paint_fulfillment_terminal',
			'file_content_operation_terminal',
			'worker_application_terminal',
		] as const) {
			this.#record(operation, phase, 'success', operation.renderStageAttempt);
		}
	}

	preparationFailed(operation: BridgeSelectedFileContentOperation): void {
		for (const phase of [
			'content_operation_terminal',
			'file_content_operation_terminal',
			'worker_application_terminal',
		] as const) {
			this.#record(operation, phase, 'failure');
		}
	}

	descriptorMissing(operation: BridgeSelectedFileContentOperation): void {
		for (const phase of [
			'file_descriptor_wait_terminal',
			'file_content_operation_terminal',
			'worker_application_terminal',
		] as const) {
			this.#record(operation, phase, 'failure');
		}
	}

	cancelled(operation: BridgeSelectedFileContentOperation): void {
		const activeTerminals =
			operation.phase === 'preparingDescriptor'
				? (['file_descriptor_wait_terminal'] as const)
				: operation.phase === 'preparingContent'
					? (['content_operation_terminal'] as const)
					: ([
							'main_thread_install_terminal',
							'render_operation_terminal',
							'paint_fulfillment_terminal',
						] as const);
		for (const phase of [
			...activeTerminals,
			'file_content_operation_terminal',
			'worker_application_terminal',
		] as const) {
			this.#record(
				operation,
				phase,
				'cancelled',
				operation.phase === 'preparingRender' ? operation.renderStageAttempt : 0,
			);
		}
	}

	disposition(
		operation: BridgeSelectedFileContentOperation,
		disposition: BridgeWorkerRenderDisposition,
	): void {
		const result =
			disposition === 'superseded' ? 'stale' : disposition === 'rejected' ? 'failure' : 'success';
		if (disposition === 'queued') {
			this.#record(operation, 'main_thread_install_terminal', result, operation.renderStageAttempt);
			return;
		}
		if (disposition === 'applied') {
			this.#record(operation, 'render_operation_terminal', result, operation.renderStageAttempt);
			return;
		}
		const terminalPhases =
			disposition === 'painted'
				? (['paint_fulfillment_terminal'] as const)
				: ([
						'main_thread_install_terminal',
						'render_operation_terminal',
						'paint_fulfillment_terminal',
					] as const);
		for (const phase of [
			...terminalPhases,
			'file_content_operation_terminal',
			'worker_application_terminal',
		] as const) {
			this.#record(operation, phase, result, operation.renderStageAttempt);
		}
	}

	#record(
		operation: BridgeSelectedFileContentOperation,
		phase: BridgeOperationLifecyclePhase,
		result: 'cancelled' | 'failure' | 'stale' | 'started' | 'success',
		stageAttempt = 0,
	): void {
		recordBridgeOperationLifecycleTelemetry({
			operationCorrelationId: operation.operationCorrelationId,
			phase,
			recorder: this.#recorder,
			result,
			stageAttempt,
			viewer: 'file',
		});
	}
}

export function trackSelectedFilePreparationCompletion(props: {
	readonly abortController: AbortController;
	readonly abortControllerByItemId: Map<string, AbortController>;
	readonly completion: Promise<void>;
	readonly isPaneWorkAdmitted: () => boolean;
	readonly isRequestLatest: () => boolean;
	readonly onClearLatest: () => void;
	readonly request: BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest;
	readonly requestDrain: () => void;
	readonly retriedRequests: WeakSet<BridgeCommWorkerSelectedFileViewContentReadyPreparationRequest>;
	readonly retry: () => void;
}): Promise<void> {
	return props.completion.finally((): void => {
		if (props.abortControllerByItemId.get(props.request.itemId) !== props.abortController) return;
		props.abortControllerByItemId.delete(props.request.itemId);
		if (!props.isRequestLatest()) return;
		if (props.abortController.signal.aborted || !props.isPaneWorkAdmitted()) return;
		if (props.request.store.getState().selectedId !== props.request.itemId) {
			props.onClearLatest();
			return;
		}
		const selectedContentFailed =
			props.request.store.getState().availabilityByItemId.get(props.request.itemId) === 'failed';
		if (selectedContentFailed && !props.retriedRequests.has(props.request)) {
			props.retriedRequests.add(props.request);
			props.retry();
			props.requestDrain();
			return;
		}
		props.onClearLatest();
	});
}
