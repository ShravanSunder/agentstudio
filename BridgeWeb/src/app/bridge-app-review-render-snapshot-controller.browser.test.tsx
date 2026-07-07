import { useMemo, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerReviewSourceUpdateCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryBootstrapConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import { createBridgeReviewViewerStore } from '../review-viewer/state/review-viewer-store.js';
import type { BridgeReviewCommWorkerTransportDispatcher } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.js';
import {
	type CreateBridgeReviewRuntimeProtocolDispatcherProps,
	createBridgeReviewWorkerPierreCourier,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';

describe('useBridgeReviewRenderSnapshotController Browser Mode', () => {
	test('re-synchronizes review source after telemetry reboots the comm worker', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const capturedRuntimes: CapturedBridgeReviewRuntime[] = [];
		const transportFactory = makeCapturingTransportFactory(capturedRuntimes);
		const rendered = render(
			<BridgeReviewRenderSnapshotControllerProbe
				reviewPackage={reviewPackage}
				telemetryConfig={null}
				transportFactory={transportFactory}
			/>,
		);

		await expect
			.poll(() => capturedRuntimes[0]?.messages.some(isReviewSourceUpdateCommand) ?? false)
			.toBe(true);

		rendered.rerender(
			<BridgeReviewRenderSnapshotControllerProbe
				reviewPackage={reviewPackage}
				telemetryConfig={makeTelemetryConfig()}
				transportFactory={transportFactory}
			/>,
		);

		await expect.poll(() => capturedRuntimes.length).toBe(2);
		await expect
			.poll(() => capturedRuntimes[1]?.messages.some(isReviewSourceUpdateCommand) ?? false)
			.toBe(true);
		expect(capturedRuntimes[1]?.bootstrapRequest.runtime.telemetryConfig).toMatchObject({
			enabledScopes: ['web'],
			endpointUrl: 'agentstudio://telemetry/batch',
		});
	});
});

interface BridgeReviewRenderSnapshotControllerProbeProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly telemetryConfig: BridgeTelemetryBootstrapConfig | null;
	readonly transportFactory: CreateBridgeReviewRuntimeProtocolDispatcherProps['transportFactory'];
}

function BridgeReviewRenderSnapshotControllerProbe(
	props: BridgeReviewRenderSnapshotControllerProbeProps,
): ReactElement | null {
	const panelChromeSlice = useMemo(
		() => createBridgeReviewViewerStore().getState().panelChromeSlice,
		[],
	);
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	useBridgeReviewRenderSnapshotController({
		panelChromeSlice,
		pierreCourier,
		reviewPackage: props.reviewPackage,
		reviewTreeRows: reviewTreeRowsForPackage(props.reviewPackage),
		telemetryConfig: props.telemetryConfig,
		transportFactory: props.transportFactory,
	});
	return null;
}

interface CapturedBridgeReviewRuntime {
	readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
	readonly messages: BridgeWorkerMainToServerMessage[];
	disposeCount: number;
}

function makeCapturingTransportFactory(
	capturedRuntimes: CapturedBridgeReviewRuntime[],
): NonNullable<CreateBridgeReviewRuntimeProtocolDispatcherProps['transportFactory']> {
	return (props): BridgeReviewCommWorkerTransportDispatcher => {
		const runtime: CapturedBridgeReviewRuntime = {
			bootstrapRequest: props.bootstrapRequest,
			messages: [],
			disposeCount: 0,
		};
		capturedRuntimes.push(runtime);
		return {
			dispatch: (message): void => {
				runtime.messages.push(message);
			},
			dispose: (): void => {
				runtime.disposeCount += 1;
			},
		};
	};
}

function isReviewSourceUpdateCommand(
	message: BridgeWorkerMainToServerMessage,
): message is BridgeWorkerReviewSourceUpdateCommand {
	return message.command === 'reviewSourceUpdate';
}

function reviewTreeRowsForPackage(
	reviewPackage: BridgeReviewPackage,
): readonly ReviewTreeRowMetadata[] {
	return reviewPackage.orderedItemIds.map((itemId): ReviewTreeRowMetadata => {
		const item = reviewPackage.itemsById[itemId];
		if (item === undefined) {
			throw new Error(`Missing review item ${itemId}.`);
		}
		const path = item.headPath ?? item.basePath ?? item.itemId;
		return {
			rowId: `review-row:${item.itemId}`,
			itemId: item.itemId,
			path,
			depth: path.split('/').length - 1,
			isDirectory: false,
		};
	});
}

function makeTelemetryConfig(): BridgeTelemetryBootstrapConfig {
	return {
		enabledScopes: new Set(['web']),
		endpointUrl: 'agentstudio://telemetry/batch',
		maxEncodedBatchBytes: 16_384,
		maxSamplesPerBatch: 4,
		minimumFlushIntervalMilliseconds: 250,
		scenario: 'bridge-review',
	};
}
