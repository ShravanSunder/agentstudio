import { useEffect } from 'react';

import { observeBridgePaneCommWorkerSessionDiagnosticSnapshots } from '../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeCommWorkerSessionTelemetrySample } from '../foundation/telemetry/bridge-viewer-activation-telemetry.js';

export function useBridgeCommWorkerSessionTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
): void {
	useEffect(
		(): (() => void) =>
			observeBridgePaneCommWorkerSessionDiagnosticSnapshots((snapshot): void => {
				recordBridgeCommWorkerSessionTelemetrySample({ snapshot, telemetryRecorder });
			}),
		[telemetryRecorder],
	);
}
