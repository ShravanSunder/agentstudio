import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useEffect } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import { resolveBridgeMarkdownPreviewDecision } from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import type {
	BridgeMarkdownRenderWorkerClient,
	BridgeMarkdownRenderWorkerClientCompletion,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import type { SelectedMarkdownPreviewState } from './bridge-app-review-selection-state.js';
import { makeSelectedContentResourcesKey } from './bridge-app-review-selection-state.js';
import {
	isOversizedMarkdownPreviewOutput,
	recordMarkdownPreviewFallbackTelemetry,
	recordMarkdownRenderCompletionTelemetry,
	recordMarkdownRenderQueueTelemetry,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';

const bridgeMarkdownPreviewAbortKey = 'bridge-review-markdown-preview';

export interface UseBridgeReviewMarkdownPreviewControllerProps {
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly isActive: boolean;
	readonly markdownWorkerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly renderModeKind: 'codeView' | 'markdownPreview';
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
	readonly selectedItemId: string | null;
	readonly selectedMarkdownPreviewStateRef: MutableRefObject<SelectedMarkdownPreviewState | null>;
	readonly setRenderModeCodeView: () => void;
	readonly setSelectedMarkdownPreviewState: Dispatch<
		SetStateAction<SelectedMarkdownPreviewState | null>
	>;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export function useBridgeReviewMarkdownPreviewController(
	props: UseBridgeReviewMarkdownPreviewControllerProps,
): void {
	const {
		currentReviewPackageTelemetryContextRef,
		isActive,
		markdownWorkerClient,
		renderModeKind,
		reviewPackage,
		selectedContentResources,
		selectedItemId,
		selectedMarkdownPreviewStateRef,
		setRenderModeCodeView,
		setSelectedMarkdownPreviewState,
		telemetryRecorderRef,
	} = props;
	useEffect((): (() => void) => {
		let didCancel = false;
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		if (!isActive) {
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			setSelectedMarkdownPreviewState(
				(currentState: SelectedMarkdownPreviewState | null): SelectedMarkdownPreviewState | null =>
					currentState?.status === 'rendering' ? null : currentState,
			);
			return (): void => {
				didCancel = true;
			};
		}
		if (reviewPackage === null || selectedItemId === null) {
			setRenderModeCodeView();
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		const selectedContentKey = makeSelectedContentResourcesKey(reviewPackage, selectedItemId);
		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId,
			resources: selectedContentResources,
		});
		const selectedMarkdownPreviewSnapshot = selectedMarkdownPreviewStateRef.current;

		if (decision.kind === 'codeView') {
			if (decision.reason === 'contentPending' && renderModeKind === 'markdownPreview') {
				setSelectedMarkdownPreviewState(null);
				return (): void => {
					didCancel = true;
				};
			}
			setRenderModeCodeView();
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			if (decision.reason !== 'contentPending') {
				recordMarkdownPreviewFallbackTelemetry({
					telemetryRecorder: telemetryRecorderRef.current,
					parentTraceContext,
					reason: decision.reason,
				});
			}
			return (): void => {
				didCancel = true;
			};
		}

		if (
			selectedMarkdownPreviewSnapshot !== null &&
			selectedMarkdownPreviewSnapshot.itemId === selectedItemId &&
			selectedMarkdownPreviewSnapshot.contentKey === selectedContentKey &&
			selectedMarkdownPreviewSnapshot.status === 'failed'
		) {
			setRenderModeCodeView();
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		if (markdownWorkerClient === null) {
			setRenderModeCodeView();
			setSelectedMarkdownPreviewState(null);
			recordMarkdownPreviewFallbackTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				reason: 'workerUnavailable',
			});
			return (): void => {
				didCancel = true;
			};
		}

		if (renderModeKind !== 'markdownPreview') {
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		if (
			selectedMarkdownPreviewSnapshot !== null &&
			selectedMarkdownPreviewSnapshot.itemId === selectedItemId &&
			selectedMarkdownPreviewSnapshot.contentKey === selectedContentKey &&
			(selectedMarkdownPreviewSnapshot.status === 'rendering' ||
				selectedMarkdownPreviewSnapshot.status === 'ready')
		) {
			return (): void => {
				didCancel = true;
			};
		}

		const source = decision.source;
		const task = markdownWorkerClient.startRender({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			itemId: source.itemId,
			itemVersion: source.itemVersion,
			contentCacheKey: source.contentCacheKey,
			contentHash: source.contentHash,
			markdownText: source.markdownText,
			sourcePath: source.sourcePath,
			abortKey: bridgeMarkdownPreviewAbortKey,
		});
		setSelectedMarkdownPreviewState({
			itemId: source.itemId,
			contentKey: selectedContentKey,
			sourcePath: source.sourcePath,
			status: 'rendering',
			html: null,
		});
		recordMarkdownRenderQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
		});
		void task.completed.then((completion: BridgeMarkdownRenderWorkerClientCompletion): void => {
			if (didCancel) {
				return;
			}
			recordMarkdownRenderCompletionTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				completion,
			});
			if (completion.status !== 'success') {
				setRenderModeCodeView();
				setSelectedMarkdownPreviewState({
					itemId: source.itemId,
					contentKey: selectedContentKey,
					sourcePath: source.sourcePath,
					status: 'failed',
					html: null,
				});
				return;
			}
			if (isOversizedMarkdownPreviewOutput(completion.response.html)) {
				setRenderModeCodeView();
				setSelectedMarkdownPreviewState({
					itemId: source.itemId,
					contentKey: selectedContentKey,
					sourcePath: source.sourcePath,
					status: 'failed',
					html: null,
				});
				return;
			}
			setSelectedMarkdownPreviewState({
				itemId: source.itemId,
				contentKey: selectedContentKey,
				sourcePath: source.sourcePath,
				status: 'ready',
				html: completion.response.html,
			});
		});

		return (): void => {
			didCancel = true;
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
		};
	}, [
		currentReviewPackageTelemetryContextRef,
		isActive,
		markdownWorkerClient,
		renderModeKind,
		reviewPackage,
		selectedContentResources,
		selectedItemId,
		selectedMarkdownPreviewStateRef,
		setRenderModeCodeView,
		setSelectedMarkdownPreviewState,
		telemetryRecorderRef,
	]);
}
