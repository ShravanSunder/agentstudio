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
	deliveryModeForMockedBackend,
	fixtureClassForMockedBackend,
	latencyProfileForMockedBackend,
	parseBridgeAppDevFixtureOptions,
	reviewPackageForBridgeAppDevFixtureScenario,
	type BridgeAppDevFixtureScenario,
} from './bridge-app-dev-fixture.js';
import { BridgeApp } from './bridge-app.js';

// oxlint-disable-next-line import/no-unassigned-import -- Dev server must load the same app CSS as packaged BridgeWeb.
import './bridge-app.css';

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	const options = parseBridgeAppDevFixtureOptions(new URLSearchParams(window.location.search));
	const fixtureClass = fixtureClassForMockedBackend(options.fixtureClass);
	const workerFactory = options.workersEnabled
		? createBridgePierrePortableBlobWorkerFactory()
		: null;
	const markdownWorkerClient = options.workersEnabled
		? createBridgeMarkdownRenderWebWorkerClient({
				workerFactory: createBridgeMarkdownRenderModuleWorkerFactory(),
			})
		: null;
	const fixture = fixtureClass === null ? null : makeBridgeViewerBrowserFixture({ fixtureClass });
	const backend =
		fixture === null
			? null
			: installBridgeViewerMockedBackend(fixture, {
					latencyProfile: latencyProfileForMockedBackend(options.latencyProfile),
				});

	window.addEventListener(
		'beforeunload',
		(): void => {
			backend?.dispose();
			workerFactory?.revoke();
		},
		{ once: true },
	);

	createRoot(rootElement).render(
		<BridgeApp
			codeViewWorkerPoolEnabled={options.workersEnabled}
			markdownWorkerClient={markdownWorkerClient}
			{...(workerFactory === null ? {} : { codeViewWorkerFactory: workerFactory.workerFactory })}
			{...(backend === null
				? {}
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
	});
}

async function pushDevFixture(props: {
	readonly backend: BridgeViewerMockedBackend | null;
	readonly deliveryMode: 'full-load' | 'streaming-append';
	readonly fixture: BridgeViewerBrowserFixture | null;
	readonly scenario: BridgeAppDevFixtureScenario;
}): Promise<void> {
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
