import { createRoot } from 'react-dom/client';

import {
	makeBridgeViewerBrowserFixture,
	installBridgeViewerMockedBackend,
	type BridgeViewerBrowserFixture,
	type BridgeViewerMockedBackend,
} from '../review-viewer/test-support/bridge-viewer-mocked-backend.js';
import {
	createBridgeMarkdownRenderModuleWorkerFactory,
	createBridgeMarkdownRenderWebWorkerClient,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-transport.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../review-viewer/workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	createBridgeReviewProjectionModuleWorkerFactory,
	createBridgeReviewProjectionWebWorkerClient,
} from '../review-viewer/workers/projection/review-projection-worker-transport.js';
import {
	deliveryModeForMockedBackend,
	fixtureClassForMockedBackend,
	latencyProfileForMockedBackend,
	parseBridgeAppDevFixtureOptions,
	reviewPackageForBridgeAppDevFixtureScenario,
	type BridgeAppDevFixtureScenario,
} from './bridge-app-dev-fixture.js';
import {
	createBridgeAppDevTelemetryBootstrapConfig,
	installBridgeAppDevTelemetryHost,
} from './bridge-app-dev-telemetry.js';
import {
	installBridgeAppDevWorktreeReviewBackend,
	type BridgeAppDevWorktreeReviewBackend,
} from './bridge-app-dev-worktree-review.js';
import { installBridgeAppDevWorktreeBackend } from './bridge-app-dev-worktree.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

// oxlint-disable-next-line import/no-unassigned-import -- Dev server must load the same app CSS as packaged BridgeWeb.
import './bridge-app.css';

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	const searchParams = new URLSearchParams(window.location.search);
	const options = parseBridgeAppDevFixtureOptions(searchParams);
	const telemetryScenario = bridgeAppDevTelemetryScenario({
		fixtureClass: options.fixtureClass,
		scenario: searchParams.get('scenario') ?? options.scenario,
	});
	const telemetryConfig = createBridgeAppDevTelemetryBootstrapConfig(telemetryScenario);
	const telemetryHost = installBridgeAppDevTelemetryHost({
		respondToHandshakeRequests: false,
		scenario: telemetryScenario,
	});
	const fixtureClass = fixtureClassForMockedBackend(options.fixtureClass);
	const workerFactory = options.workersEnabled
		? createBridgePierrePortableBlobWorkerFactory()
		: null;
	const markdownWorkerClient = options.workersEnabled
		? createBridgeMarkdownRenderWebWorkerClient({
				workerFactory: createBridgeMarkdownRenderModuleWorkerFactory(),
			})
		: null;
	const projectionWorkerClient = options.workersEnabled
		? createBridgeReviewProjectionWebWorkerClient({
				workerFactory: createBridgeReviewProjectionModuleWorkerFactory(),
			})
		: null;
	const fixture = fixtureClass === null ? null : makeBridgeViewerBrowserFixture({ fixtureClass });
	const backend =
		fixture === null
			? null
			: installBridgeViewerMockedBackend(fixture, {
					latencyProfile: latencyProfileForMockedBackend(options.latencyProfile),
					telemetryConfig,
				});
	const worktreeBackend =
		options.fixtureClass === 'worktree' && options.navigationCommand.context === 'files'
			? installBridgeAppDevWorktreeBackend()
			: null;
	const worktreeReviewBackend =
		options.fixtureClass === 'worktree' && options.navigationCommand.context === 'review'
			? installBridgeAppDevWorktreeReviewBackend()
			: null;

	window.addEventListener(
		'beforeunload',
		(): void => {
			backend?.dispose();
			telemetryHost.dispose();
			workerFactory?.revoke();
		},
		{ once: true },
	);

	createRoot(rootElement).render(
		<BridgeAppProtocolRouter
			codeViewWorkerPoolEnabled={options.workersEnabled}
			markdownWorkerClient={markdownWorkerClient}
			navigationCommand={options.navigationCommand}
			{...(worktreeBackend === null
				? {}
				: {
						fileViewerProps: {
							autoOpenInitialFile: true,
							fetchResource: worktreeBackend.fetchWorktreeFileResource,
							loadInitialSurface: worktreeBackend.loadWorktreeFileSurface,
							subscribeFrames: worktreeBackend.subscribeWorktreeFileFrames,
						},
					})}
			{...(workerFactory === null ? {} : { codeViewWorkerFactory: workerFactory.workerFactory })}
			{...(backend === null
				? worktreeReviewBackend !== null
					? {
							fetchContent: worktreeReviewBackend.fetchContent,
							...(projectionWorkerClient === null ? {} : { projectionWorkerClient }),
						}
					: projectionWorkerClient === null
						? {}
						: { projectionWorkerClient }
				: {
						fetchContent: backend.fetchContent,
						projectionWorkerClient: backend.projectionWorkerClient,
					})}
		/>,
	);

	void pushDevFixture({
		backend,
		deliveryMode: deliveryModeForMockedBackend(options.deliveryMode),
		fixture,
		scenario: options.scenario,
		worktreeReviewBackend,
	});
}

function bridgeAppDevTelemetryScenario(props: {
	readonly fixtureClass: string;
	readonly scenario: string;
}): string {
	return `vite-dev-${props.fixtureClass}-${props.scenario}`;
}

async function pushDevFixture(props: {
	readonly backend: BridgeViewerMockedBackend | null;
	readonly deliveryMode: 'full-load' | 'streaming-append';
	readonly fixture: BridgeViewerBrowserFixture | null;
	readonly scenario: BridgeAppDevFixtureScenario;
	readonly worktreeReviewBackend: BridgeAppDevWorktreeReviewBackend | null;
}): Promise<void> {
	if (props.worktreeReviewBackend !== null) {
		await props.worktreeReviewBackend.pushPackage();
		return;
	}
	if (props.backend === null || props.fixture === null) {
		return;
	}
	await props.backend.pushPackage(
		reviewPackageForBridgeAppDevFixtureScenario({
			fixture: props.fixture,
			scenario: props.scenario,
		}),
	);
	if (props.deliveryMode === 'streaming-append') {
		await props.backend.pushDelta();
	}
}
