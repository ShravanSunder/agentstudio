import { useEffect } from 'react';

import type { BridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import { observeBridgePaneCommWorkerSessionDiagnosticSnapshots } from '../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeCommWorkerSessionTelemetrySample } from '../foundation/telemetry/bridge-viewer-activation-telemetry.js';

export function useBridgeCommWorkerSessionTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	paneRuntime: Pick<BridgePaneRuntime, 'installMainTelemetryRecorder'>,
): void {
	useEffect((): (() => void) => {
		paneRuntime.installMainTelemetryRecorder(telemetryRecorder);
		return observeBridgePaneCommWorkerSessionDiagnosticSnapshots((snapshot): void => {
			recordBridgeCommWorkerSessionTelemetrySample({ snapshot, telemetryRecorder });
		});
	}, [paneRuntime, telemetryRecorder]);
}
