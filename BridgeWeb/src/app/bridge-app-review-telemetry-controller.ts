import { type MutableRefObject, useEffect, useRef } from 'react';

import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	createChildTraceContext,
	recordReviewStartupTelemetry,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';

export interface UseBridgeReviewRenderTelemetryControllerProps {
	readonly hasProjection: boolean;
	readonly isActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewPackageTelemetryContextRef: MutableRefObject<
		Map<string, BridgeReviewPackageTelemetryContext>
	>;
	readonly reviewReadyStartMillisecondsByPackageKeyRef: MutableRefObject<Map<string, number>>;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export function useBridgeReviewRenderTelemetryController(
	props: UseBridgeReviewRenderTelemetryControllerProps,
): void {
	const lastFirstRenderPackageRef = useRef<string | null>(null);
	const lastReviewReadyPackageRef = useRef<string | null>(null);
	useEffect((): void => {
		if (
			!props.isActive ||
			props.reviewPackage === null ||
			!props.hasProjection ||
			!props.telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const packageKey = `${props.reviewPackage.packageId}:${props.reviewPackage.reviewGeneration}`;
		if (lastFirstRenderPackageRef.current === packageKey) {
			return;
		}
		lastFirstRenderPackageRef.current = packageKey;
		const telemetryContext = props.reviewPackageTelemetryContextRef.current.get(packageKey);
		props.telemetryRecorderRef.current.record({
			scope: 'web',
			name: 'performance.bridge.web.first_render',
			durationMilliseconds: null,
			traceContext: createChildTraceContext(telemetryContext?.traceContext ?? null),
			stringAttributes: {
				'agentstudio.bridge.phase': 'render',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.slice': telemetryContext?.slice ?? 'unknown',
				'agentstudio.bridge.transport': telemetryContext?.transport ?? 'unknown',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		props.telemetryRecorderRef.current.flush({ force: true });
	}, [
		props.hasProjection,
		props.isActive,
		props.reviewPackage,
		props.reviewPackageTelemetryContextRef,
		props.telemetryRecorderRef,
	]);

	useEffect((): void => {
		if (
			!props.isActive ||
			props.reviewPackage === null ||
			!props.hasProjection ||
			props.selectedCodeViewItem === null ||
			!props.telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const packageKey = `${props.reviewPackage.packageId}:${props.reviewPackage.reviewGeneration}`;
		const selectedReadyKey = `${packageKey}:${props.selectedCodeViewItem.bridgeMetadata.itemId}:${props.selectedCodeViewItem.bridgeMetadata.cacheKey}`;
		if (lastReviewReadyPackageRef.current === selectedReadyKey) {
			return;
		}
		lastReviewReadyPackageRef.current = selectedReadyKey;
		const telemetryContext = props.reviewPackageTelemetryContextRef.current.get(packageKey);
		const reviewReadyStartMilliseconds =
			props.reviewReadyStartMillisecondsByPackageKeyRef.current.get(packageKey) ?? null;
		if (reviewReadyStartMilliseconds !== null) {
			props.reviewReadyStartMillisecondsByPackageKeyRef.current.delete(packageKey);
		}
		recordReviewStartupTelemetry({
			telemetryRecorder: props.telemetryRecorderRef.current,
			phase: 'review_ready',
			slice: telemetryContext?.slice ?? 'review_projection',
			transport: telemetryContext?.transport ?? 'intake',
			traceContext: createChildTraceContext(telemetryContext?.traceContext ?? null),
			durationMilliseconds:
				reviewReadyStartMilliseconds === null
					? null
					: performance.now() - reviewReadyStartMilliseconds,
			result: 'success',
			numericAttributes: {
				'agentstudio.bridge.review.item_count': props.reviewPackage.orderedItemIds.length,
			},
		});
	}, [
		props.hasProjection,
		props.isActive,
		props.reviewPackage,
		props.reviewPackageTelemetryContextRef,
		props.reviewReadyStartMillisecondsByPackageKeyRef,
		props.selectedCodeViewItem,
		props.telemetryRecorderRef,
	]);
}
