import type { ReactNode } from 'react';

import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeFileViewerDisplaySource } from './bridge-file-viewer-display-model.js';

export interface BridgeFileViewerAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly controlTarget?: EventTarget;
	readonly isActive?: boolean;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onDisplaySourceChange?: (source: BridgeFileViewerDisplaySource | null) => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly viewerHeaderControls?: ReactNode;
}
