import { describe, expect, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { recordBridgeCodeViewHydrationTelemetry } from './bridge-review-viewer-telemetry.js';

describe('Bridge review viewer telemetry', () => {
	test('does not read selected content bodies when web telemetry is disabled', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const selectedItem = reviewPackage.itemsById['source-high'];
		if (selectedItem === undefined) {
			throw new Error('expected source-high fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		let readTextCallCount = 0;
		const resource: BridgeContentResource = {
			authoritative: true,
			byteLength: 512_000,
			handle: makeBridgeContentHandle('source-high', 'head'),
			readText: (): string => {
				readTextCallCount += 1;
				return 'large body\n'.repeat(50_000);
			},
		};
		const telemetryRecorder = disabledTelemetryRecorder();

		recordBridgeCodeViewHydrationTelemetry({
			telemetryRecorder,
			parentTraceContext: null,
			projection,
			item: selectedItem,
			resources: { head: resource },
			workerPoolEnabled: true,
		});

		expect(readTextCallCount).toBe(0);
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
