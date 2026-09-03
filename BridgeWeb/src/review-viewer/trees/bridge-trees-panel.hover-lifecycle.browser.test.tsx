import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode mounts the production Review tree.
import '../../app/bridge-app.css';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { BridgeReviewTreesPanel } from './bridge-trees-panel.js';

describe('BridgeReviewTreesPanel hover lifecycle', () => {
	test('records first interaction again for a newer retained Review activation', async () => {
		// Arrange
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const telemetryRecorder = makeCapturingRecorder(telemetrySamples);
		const reviewPackage = makeBridgeReviewPackage();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const rendered = await render(
			<BridgeReviewTreesPanel
				activationCause="context_switcher"
				activationSequence={1}
				activationStartedAtPerfNow={performance.now()}
				isActive={true}
				onSelectItem={(): void => {}}
				presentationPositionKey="activation-one"
				projection={projection}
				reviewPackage={reviewPackage}
				reviewTreeRows={[]}
				searchMode={{ kind: 'text' }}
				searchText=""
				selectedItemId={null}
				telemetryRecorder={telemetryRecorder}
			/>,
		);
		await waitForAnimationFrame();
		expect(firstInteractionSamples(telemetrySamples)).toHaveLength(1);

		// Act
		await act(async (): Promise<void> => {
			await rendered.rerender(
				<BridgeReviewTreesPanel
					activationCause="native_request"
					activationSequence={2}
					activationStartedAtPerfNow={performance.now()}
					isActive={true}
					onSelectItem={(): void => {}}
					presentationPositionKey="activation-one"
					projection={projection}
					reviewPackage={reviewPackage}
					reviewTreeRows={[]}
					searchMode={{ kind: 'text' }}
					searchText=""
					selectedItemId={null}
					telemetryRecorder={telemetryRecorder}
				/>,
			);
		});
		await waitForAnimationFrame();

		// Assert
		expect(firstInteractionSamples(telemetrySamples)).toHaveLength(2);
	});

	test('clears Review hover exactly once when the tree unmounts', async () => {
		// Arrange
		const hoveredItemIds: Array<string | null> = [];
		const reviewPackage = makeBridgeReviewPackage();
		const rendered = await render(
			<BridgeReviewTreesPanel
				isActive={true}
				onHoveredItemIdChange={(itemId): void => {
					hoveredItemIds.push(itemId);
				}}
				onSelectItem={(): void => {}}
				presentationPositionKey="hover-lifecycle"
				projection={buildBridgeReviewProjection({
					reviewPackage,
					request: { facets: [], mode: { kind: 'normalReview' } },
				})}
				reviewPackage={reviewPackage}
				reviewTreeRows={[]}
				searchMode={{ kind: 'text' }}
				searchText=""
				selectedItemId={null}
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			await rendered.unmount();
			await Promise.resolve();
		});

		// Assert
		expect(hoveredItemIds).toEqual([null]);
	});
});

function firstInteractionSamples(
	samples: readonly BridgeTelemetrySample[],
): readonly BridgeTelemetrySample[] {
	return samples.filter(
		(sample): boolean => sample.name === 'performance.bridge.viewer.time_to_first_interaction',
	);
}

function makeCapturingRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		flush: (): boolean => true,
		isEnabled: (): boolean => true,
		measure: <TResult,>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
	};
}

function waitForAnimationFrame(): Promise<void> {
	return act(
		() =>
			new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => resolve());
			}),
	);
}
