import { describe, test } from 'vitest';

import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { bridgeCodeViewContentRoleFactsForHandle } from '../code-view/bridge-code-view-materialization.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { recordBridgeCodeViewHydrationTelemetry } from './bridge-review-viewer-telemetry.js';

describe('Bridge review viewer telemetry', () => {
	test('accepts body-free content facts when web telemetry is disabled', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const selectedItem = reviewPackage.itemsById['source-high'];
		if (selectedItem === undefined) {
			throw new Error('expected source-high fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const resource = bridgeCodeViewContentRoleFactsForHandle({
			byteLength: 512_000,
			handle: makeBridgeContentHandle('source-high', 'head'),
		});
		const telemetryRecorder = disabledTelemetryRecorder();

		recordBridgeCodeViewHydrationTelemetry({
			telemetryRecorder,
			parentTraceContext: null,
			projection,
			item: selectedItem,
			resources: { head: resource },
			workerPoolEnabled: true,
		});
	});
});

function disabledTelemetryRecorder(): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => false,
		record: (): void => {},
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		flush: (): boolean => true,
	};
}
