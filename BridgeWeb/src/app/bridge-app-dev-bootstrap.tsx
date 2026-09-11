import { createRoot, type Root } from 'react-dom/client';

import { Toaster } from '@/components/ui/sonner.js';

import { createBridgePaneRuntime } from '../core/comm-worker/bridge-pane-runtime.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../review-viewer/workers/pierre/bridge-pierre-dev-worker-factory.js';
import { createBridgeCommWorkerModuleWorker } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-dev-factory.js';
import { parseBridgeAppDevFixtureOptions } from './bridge-app-dev-fixture.js';
import { installBridgeAppDevProductSessionHost } from './bridge-app-dev-product-session-host.js';
import { BridgeAppDevSessionNotice } from './bridge-app-dev-session-notice.js';
import { installBridgeAppDevTelemetryHost } from './bridge-app-dev-telemetry.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';
import { createBridgeMarkdownRenderRuntimeWithClient } from './markdown/bridge-markdown-render-runtime.js';
import {
	createBridgeMarkdownRenderModuleWorkerFactory,
	createBridgeMarkdownRenderWebWorkerClient,
} from './markdown/worker/bridge-markdown-render-worker-transport.js';

// oxlint-disable-next-line import/no-unassigned-import -- Dev server must load the same app CSS as packaged BridgeWeb.
import './bridge-app.css';

await preloadBridgeReviewViewerShell();

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	const root = createRoot(rootElement);
	let disposeViewer = (): void => {};
	function renderInactiveSession(): void {
		disposeViewer();
		root.render(<BridgeAppDevSessionNotice onRefresh={(): void => location.reload()} />);
	}
	disposeViewer = mountDevelopmentViewer(root, renderInactiveSession);
	window.addEventListener(
		'beforeunload',
		(): void => {
			root.unmount();
			disposeViewer();
		},
		{ once: true },
	);
}

function mountDevelopmentViewer(root: Root, onSessionInUse: () => void): () => void {
	const searchParams = new URLSearchParams(window.location.search);
	const options = parseBridgeAppDevFixtureOptions(searchParams);
	const telemetryScenario = bridgeAppDevTelemetryScenario({
		fixtureClass: options.fixtureClass,
		scenario: searchParams.get('scenario') ?? options.scenario,
	});
	const telemetryHost = installBridgeAppDevTelemetryHost({
		scenario: telemetryScenario,
	});
	const productSessionHost = installBridgeAppDevProductSessionHost({
		navigationIntent: options.navigationIntent,
		reloadPage: (): void => location.reload(),
		onSessionInUse,
	});
	const workerFactory = createBridgePierrePortableBlobWorkerFactory();
	const markdownWorkerClient = createBridgeMarkdownRenderWebWorkerClient({
		workerFactory: createBridgeMarkdownRenderModuleWorkerFactory(),
	});
	const markdownRuntime = createBridgeMarkdownRenderRuntimeWithClient(markdownWorkerClient);
	const paneRuntime = createBridgePaneRuntime({
		sessionProps: { workerFactory: createBridgeCommWorkerModuleWorker },
	});

	root.render(
		<>
			<BridgeAppProtocolRouter
				codeViewWorkerPoolEnabled
				markdownRuntime={markdownRuntime}
				paneRuntime={paneRuntime}
				fileViewerProps={{ autoOpenInitialFile: true }}
				codeViewWorkerFactory={workerFactory.workerFactory}
			/>
			<Toaster />
		</>,
	);
	let disposed = false;
	return (): void => {
		if (disposed) return;
		disposed = true;
		productSessionHost.dispose();
		paneRuntime.dispose();
		markdownRuntime.dispose();
		telemetryHost.dispose();
		workerFactory.revoke();
	};
}

async function preloadBridgeReviewViewerShell(): Promise<void> {
	await import('../review-viewer/shell/review-viewer-shell.js');
}

function bridgeAppDevTelemetryScenario(props: {
	readonly fixtureClass: string;
	readonly scenario: string;
}): string {
	return `vite-dev-${props.fixtureClass}-${props.scenario}`;
}
