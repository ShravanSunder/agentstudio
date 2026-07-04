import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordNativeWorktreeFileIntakeRejectTelemetry } from './bridge-app-native-worktree-file-telemetry.js';

describe('native worktree file telemetry', () => {
	test('uses idle-scheduled flushing for intake reject samples', () => {
		const recorder = makeCapturingRecorder();

		recordNativeWorktreeFileIntakeRejectTelemetry({
			frameGeneration: 7,
			reason: 'stale_sequence',
			receiverGeneration: 8,
			reopenSignaled: true,
			streamIdMatches: false,
			telemetryRecorder: recorder,
		});

		expect(recorder.samples.map((sample) => sample.name)).toEqual([
			'performance.bridge.web.worktree_file_intake_reject',
		]);
		expect(recorder.flushForces).toEqual([undefined]);
	});
});

function makeCapturingRecorder(): BridgeTelemetryRecorder & {
	readonly flushForces: Array<boolean | undefined>;
	readonly samples: BridgeTelemetrySample[];
} {
	const flushForces: Array<boolean | undefined> = [];
	const samples: BridgeTelemetrySample[] = [];
	return {
		flushForces,
		isEnabled: (): boolean => true,
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		samples,
		flush: (props): boolean => {
			flushForces.push(props?.force);
			return true;
		},
	};
}
