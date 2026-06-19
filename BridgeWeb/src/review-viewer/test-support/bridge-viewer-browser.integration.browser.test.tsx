import pierrePortableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import { reviewPackageForBridgeAppDevFixtureScenario } from '../../app/bridge-app-dev-fixture.js';
import { BridgeApp } from '../../app/bridge-app.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	bridgeViewerCodeTextContent,
	bridgeViewerCodeGeometry,
	bridgeViewerRenderedTextContent,
	bridgeViewerVisibleCodeTextContent,
	bridgeViewerVisibleTreeTextContent,
	clickBridgeViewerFilterMenuOption,
	clickBridgeViewerProjectionButton,
	collapseBridgeViewerTreeFolder,
	expandBridgeViewerTreeFolder,
	findBridgeViewerTreeItemButton,
	requireBridgeViewerHTMLElement,
	setBridgeViewerSearchText,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerCodeHeaderCollapseButton,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerElement,
	waitForBridgeViewerHunkExpandButton,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemAbsent,
	waitForBridgeViewerTreeItemButton,
	waitForBridgeViewerTreeScrollOwner,
} from './bridge-viewer-browser-dom.js';
import {
	createDeferredMarkdownWorkerClient,
	createImmediateMarkdownWorkerClient,
	markdownResponseForRequest,
} from './bridge-viewer-markdown-worker-test-client.js';
import {
	disposeBridgeViewerMockedBackends,
	installBridgeViewerMockedBackend,
	makeBridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend.js';

describe('Bridge viewer Browser Mode mocked backend', () => {
	afterEach(() => {
		disposeBridgeViewerMockedBackends();
		cleanup();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-nonce');
	});

	test('mounts the real viewer from a mocked Bridge package push', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		await waitForBridgeViewerText(fixture.expected.initialPath);
		await waitForBridgeViewerText(fixture.expected.initialText);
		await waitForBridgeViewerRenderedCodeGeometry();

		expect(backend.projectionRequests).toEqual([
			expect.objectContaining({
				method: 'reviewProjection.build',
				workloadId: 'interactive',
			}),
		]);
		expect(
			backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-a')),
		).toBe(true);

		backend.dispose();
	});

	test(
		'default packaged Pierre worker path hydrates the initial selected content after worker readiness',
		{
			timeout: 12_000,
		},
		async () => {
			const fixture = makeBridgeViewerBrowserFixture();
			const backend = installBridgeViewerMockedBackend(fixture);
			const uninstallPackagedWorkerFetchMock = installPierrePackagedWorkerFetchMock();

			try {
				render(
					<BridgeApp
						codeViewWorkerPoolEnabled={true}
						fetchContent={backend.fetchContent}
						markdownWorkerClient={null}
						projectionWorkerClient={backend.projectionWorkerClient}
					/>,
				);
				await backend.pushPackage();
				await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
				await waitForBridgeViewerText(fixture.expected.initialText);
				await waitForBridgeViewerRenderedCodeGeometry();

				expect(
					document.querySelector('[data-testid="bridge-pierre-worker-pool-failed"]'),
				).toBeNull();
				expect(
					document.querySelector('[data-testid="bridge-pierre-worker-pool-loading"]'),
				).toBeNull();
				expect(
					backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-a')),
				).toBe(true);
			} finally {
				uninstallPackagedWorkerFetchMock();
				backend.dispose();
			}
		},
	);

	test('clicking a tree row fetches and renders the newly selected file', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForBridgeViewerText(fixture.expected.secondText);
		await waitForBridgeViewerAnimationFrame();

		expect(
			backend.requestedUrls.some((url: string): boolean => url.includes('browser-source-b-head')),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('stale content responses cannot overwrite newer selected content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferContentHandleIds: [fixture.expected.secondHeadHandleId],
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForPendingContentResponseCount(backend, 1);

		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);

		backend.pendingContentResponses[0]?.resolve();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(bridgeViewerCodeTextContent()).toContain(fixture.expected.addedText);
		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.secondText);
		expect(backend.pendingContentResponses[0]?.handleId).toBe(fixture.expected.secondHeadHandleId);
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.secondHeadHandleId),
			),
		).toBe(true);

		backend.dispose();
	});

	test('added files render full fetched content instead of placeholder rows', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();

		const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
		addedButton.click();
		await waitForBridgeViewerText(fixture.expected.addedText);

		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.addedText);
		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes('browser-added-source-head'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('collapsed unchanged hunk separators expand additional context', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();

		const hunkedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.hunkPath);
		hunkedButton.click();
		const expandButton = await waitForBridgeViewerHunkExpandButton();

		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.hunkExpandedText);

		expandButton.click();
		await waitForBridgeViewerText(fixture.expected.hunkExpandedText);

		backend.dispose();
	});

	test('CodeView file headers collapse and expand file content through Pierre items', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const collapseButton = await waitForBridgeViewerCodeHeaderCollapseButton();
		expect(collapseButton.getAttribute('aria-expanded')).toBe('true');
		collapseButton.click();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(collapseButton.getAttribute('aria-expanded')).toBe('false');
		expect(bridgeViewerCodeTextContent()).not.toContain(fixture.expected.initialText);

		collapseButton.click();
		await waitForBridgeViewerText(fixture.expected.initialText);

		expect(collapseButton.getAttribute('aria-expanded')).toBe('true');

		backend.dispose();
	});

	test('review chrome controls expose pointer affordances instead of inert default cursors', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const collapseButton = await waitForBridgeViewerCodeHeaderCollapseButton();
		const treeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.initialPath);
		const searchButton = requireBridgeViewerHTMLElement(
			document.querySelector('button[data-testid="bridge-review-search-toggle"]'),
		);
		const statusFilterButton = requireBridgeViewerHTMLElement(
			document.querySelector('button[data-testid="bridge-review-git-status-menu-control"]'),
		);

		expect(getComputedStyle(collapseButton).cursor).toBe('pointer');
		expect(getComputedStyle(treeButton).cursor).toBe('pointer');
		expect(getComputedStyle(searchButton).cursor).toBe('pointer');
		expect(getComputedStyle(statusFilterButton).cursor).toBe('pointer');
		expect(getComputedStyle(collapseButton).userSelect).toBe('none');
		expect(getComputedStyle(treeButton).userSelect).toBe('none');

		backend.dispose();
	});

	test('content fetch failure records the request and renders unavailable state', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			contentFailures: [fixture.expected.secondHeadHandleId],
			latencyProfile: 'small',
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForBridgeViewerText('Content unavailable');

		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.secondHeadHandleId),
			),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-source-b'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('projection worker failure renders a typed projection error instead of hanging', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			projectionFailure: true,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText('Review projection unavailable');

		expect(backend.projectionRequests).toHaveLength(1);
		expect(bridgeViewerRenderedTextContent()).not.toContain('Projecting review');

		backend.dispose();
	});

	test('CodeView and right rail keep independent scroll ownership', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');

		const largeButton = await waitForBridgeViewerTreeItemButton(fixture.expected.largePath);
		largeButton.click();
		await waitForBridgeViewerText(fixture.expected.largeText);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const railScroll = await waitForBridgeViewerTreeScrollOwner();
		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="review-viewer-shell"]'),
		);
		const documentScrollBefore = document.scrollingElement?.scrollTop ?? 0;
		const codeTextBefore = bridgeViewerVisibleCodeTextContent(codeScroll);
		const treeTextBefore = bridgeViewerVisibleTreeTextContent(railScroll);

		codeScroll.scrollTop = Math.max(1, codeScroll.scrollHeight - codeScroll.clientHeight);
		codeScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		railScroll.scrollTop = Math.max(1, railScroll.scrollHeight - railScroll.clientHeight);
		railScroll.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(codeScroll.scrollHeight).toBeGreaterThan(codeScroll.clientHeight);
		expect(codeScroll.scrollTop).toBeGreaterThan(0);
		expect(bridgeViewerVisibleCodeTextContent(codeScroll)).not.toBe(codeTextBefore);
		expect(railScroll.dataset['fileTreeVirtualizedScroll']).toBe('true');
		expect(railScroll.scrollTop).toBeGreaterThan(0);
		expect(bridgeViewerVisibleTreeTextContent(railScroll)).not.toBe(treeTextBefore);
		expect(shell.scrollTop).toBe(0);
		expect(document.scrollingElement?.scrollTop ?? 0).toBe(documentScrollBefore);

		backend.dispose();
	});

	test('search expands nested tree matches without losing selected CodeView content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);
		await collapseBridgeViewerTreeFolder('Sources/BridgeViewer');
		await waitForBridgeViewerTreeItemAbsent(fixture.expected.searchPath);

		setBridgeViewerSearchText(fixture.expected.searchText);
		const matchedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.searchPath);

		expect(matchedButton.textContent ?? '').toContain(fixture.expected.searchText);
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.initialText);
		expect(backend.projectionRequests).toHaveLength(1);

		backend.dispose();
	});

	test('large fixture search reveals added files and renders their fetched content', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();

		try {
			render(
				<BridgeApp
					codeViewWorkerPoolEnabled={true}
					codeViewWorkerFactory={workerFactory.workerFactory}
					fetchContent={backend.fetchContent}
					markdownWorkerClient={null}
					projectionWorkerClient={backend.projectionWorkerClient}
				/>,
			);
			await backend.pushPackage(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await waitForBridgeViewerText(fixture.expected.largeText);

			setBridgeViewerSearchText('NewPanel');
			const addedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.addedPath);
			addedButton.click();
			await waitForBridgeViewerText(fixture.expected.addedText);
			const codeScroll = await waitForBridgeViewerCodeScrollOwner();

			expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.addedText);
			expect(bridgeViewerVisibleCodeTextContent(codeScroll)).toContain(fixture.expected.addedText);
			expect(
				backend.requestedUrls.some((url: string): boolean =>
					url.includes(fixture.expected.addedHeadHandleId),
				),
			).toBe(true);
		} finally {
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('custom filter controls route through projection requests and preserve a visible selection', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const initialProjectionRequestCount = backend.projectionRequests.length;

		await clickBridgeViewerFilterMenuOption('bridge-review-file-class-menu-control', 'Test');
		const testFileButton = await waitForBridgeViewerTreeItemButton(fixture.expected.testFilterPath);

		expect(testFileButton.dataset['itemPath']).toBe(fixture.expected.testFilterPath);
		expect(backend.projectionRequests.length).toBeGreaterThan(initialProjectionRequestCount);
		expect(backend.projectionRequests.at(-1)?.projectionRequest.refinements).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['test'],
		});
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.initialText);

		backend.dispose();
	});

	test('view chips update projection through custom controls', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const initialProjectionRequestCount = backend.projectionRequests.length;
		expect(findBridgeViewerTreeItemButton(fixture.expected.initialPath)).not.toBeNull();

		clickBridgeViewerProjectionButton('Docs/plans');
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
		await waitForBridgeViewerTreeItemAbsent(fixture.expected.initialPath);

		expect(docsButton.dataset['itemPath']).toBe(fixture.expected.docsPath);
		expect(backend.projectionRequests.length).toBeGreaterThan(initialProjectionRequestCount);
		expect(backend.projectionRequests.at(-1)?.projectionRequest.base).toEqual({
			kind: 'docsAndPlans',
		});

		backend.dispose();
	});

	test('streaming append delta updates the rail through the Bridge push lane', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'medium-agentstudio' });
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await backend.pushDelta();
		await expandBridgeViewerTreeFolder('streaming/append');
		const appendedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.appendedPath);
		await waitForBridgeViewerText(fixture.expected.initialText);

		expect(appendedButton.dataset['itemPath']).toBe(fixture.expected.appendedPath);
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.initialText);
		expect(backend.pushRecords).toContainEqual({
			op: 'merge',
			revision: fixture.streamingAppendDelta.revision,
			reviewGeneration: fixture.streamingAppendDelta.reviewGeneration,
			payloadKind: 'delta',
		});
		expect(backend.projectionRequests.at(-1)?.revision).toBe(fixture.streamingAppendDelta.revision);

		appendedButton.click();
		await waitForBridgeViewerText(fixture.expected.appendedText);

		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.appendedHeadHandleId),
			),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				isBridgeCommandForItem(detail, 'review.markFileViewed', 'browser-streaming-append'),
			),
		).toBe(true);

		backend.dispose();
	});

	test('stale package replacements cannot erase a newer accepted delta', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'medium-agentstudio' });
		const backend = installBridgeViewerMockedBackend(fixture);

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await backend.pushDelta();
		await expandBridgeViewerTreeFolder('streaming/append');
		await waitForBridgeViewerTreeItemButton(fixture.expected.appendedPath);
		const projectionRequestCountAfterDelta = backend.projectionRequests.length;

		await backend.pushPackage(fixture.reviewPackage);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(findBridgeViewerTreeItemButton(fixture.expected.appendedPath)).not.toBeNull();
		expect(backend.projectionRequests).toHaveLength(projectionRequestCountAfterDelta);
		expect(backend.pushRecords).toContainEqual({
			op: 'replace',
			revision: fixture.reviewPackage.revision,
			reviewGeneration: fixture.reviewPackage.reviewGeneration,
			payloadKind: 'package',
		});

		backend.dispose();
	});

	test('stale delta revision gaps cannot mutate the current package', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'medium-agentstudio' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const staleDelta = {
			...fixture.streamingAppendDelta,
			revision: fixture.streamingAppendDelta.revision + 1,
		};

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const projectionRequestCountBeforeStaleDelta = backend.projectionRequests.length;

		await backend.pushDelta(staleDelta);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(findBridgeViewerTreeItemButton(fixture.expected.appendedPath)).toBeNull();
		expect(backend.projectionRequests).toHaveLength(projectionRequestCountBeforeStaleDelta);
		expect(backend.pushRecords).toContainEqual({
			op: 'merge',
			revision: staleDelta.revision,
			reviewGeneration: staleDelta.reviewGeneration,
			payloadKind: 'delta',
		});

		backend.dispose();
	});

	test('stale projection responses cannot overwrite a newer projection request', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture, {
			deferProjectionResponses: true,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		await waitForPendingProjectionResponseCount(backend, 1);
		backend.pendingProjectionResponses[0]?.resolve();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await clickBridgeViewerFilterMenuOption('bridge-review-file-class-menu-control', 'Test');
		await waitForProjectionRequestCount(backend, 2);
		await waitForProjectionAbortCount(backend, 1);
		await waitForPendingProjectionResponseExactCount(backend, 1);
		await clickBridgeViewerFilterMenuOption('bridge-review-file-class-menu-control', 'Source');
		await waitForProjectionRequestCount(backend, 3);
		await waitForProjectionAbortCount(backend, 2);
		await waitForPendingProjectionResponseExactCount(backend, 1);

		backend.pendingProjectionResponses[0]?.resolve();
		await waitForBridgeViewerTreeItemButton(fixture.expected.searchPath);
		await waitForBridgeViewerTreeItemAbsent(fixture.expected.testFilterPath);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(findBridgeViewerTreeItemButton(fixture.expected.searchPath)).not.toBeNull();
		expect(findBridgeViewerTreeItemButton(fixture.expected.testFilterPath)).toBeNull();
		expect(backend.projectionRequests[1]?.projectionRequest.refinements).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['test'],
		});
		expect(backend.projectionRequests[2]?.projectionRequest.refinements).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['source'],
		});
		expect(backend.projectionAbortKeys).toEqual([
			'bridge-review-projection',
			'bridge-review-projection',
		]);

		backend.dispose();
	});

	test('selected docs render through the typed markdown worker client path', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);
		const markdownWorker = createImmediateMarkdownWorkerClient();

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={markdownWorker.client}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
		docsButton.click();
		await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);
		await waitForBridgeViewerElement('[data-testid="bridge-markdown-preview"]');

		expect(markdownWorker.requests).toHaveLength(1);
		expect(markdownWorker.requests[0]?.markdownText).toContain(fixture.expected.docsMarkdownText);
		expect(markdownWorker.requests[0]?.sourcePath).toBe(fixture.expected.docsPath);
		expect(bridgeViewerRenderedTextContent()).toContain('const fixture = true;');
		expect(document.querySelector('[data-testid="bridge-markdown-preview"] img')).toBeNull();
		expect(document.querySelector('[data-testid="bridge-markdown-preview"] a[href]')).toBeNull();
		expect(
			document.querySelector(
				'[data-testid="bridge-markdown-preview"] form, [data-testid="bridge-markdown-preview"] input, [data-testid="bridge-markdown-preview"] button, [data-testid="bridge-markdown-preview"] details, [data-testid="bridge-markdown-preview"] dialog, [data-testid="bridge-markdown-preview"] [contenteditable]',
			),
		).toBeNull();

		backend.dispose();
	});

	test('stale markdown worker responses cannot overwrite newer selected content', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);
		const markdownWorker = createDeferredMarkdownWorkerClient({
			waitForAnimationFrame: waitForBridgeViewerAnimationFrame,
		});

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={markdownWorker.client}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushPackage();
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
		docsButton.click();
		const pendingRequest = await markdownWorker.waitForPendingRequest();
		const secondButton = await waitForBridgeViewerTreeItemButton(fixture.expected.secondPath);
		secondButton.click();
		await waitForBridgeViewerText(fixture.expected.secondText);

		pendingRequest.resolve(markdownResponseForRequest(pendingRequest.request));
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(markdownWorker.abortedRequests).toHaveLength(1);
		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(bridgeViewerRenderedTextContent()).toContain(fixture.expected.secondText);

		backend.dispose();
	});
});

function isBridgeCommandForItem(detail: unknown, method: string, itemId: string): boolean {
	if (!isRecord(detail)) {
		return false;
	}
	const params = detail['params'];
	return detail['method'] === method && isRecord(params) && params['fileId'] === itemId;
}

async function waitForPendingProjectionResponseCount(
	backend: ReturnType<typeof installBridgeViewerMockedBackend>,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingProjectionResponses.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} pending projection responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingProjectionResponseCount(backend, count, remainingAttempts - 1);
}

async function waitForPendingProjectionResponseExactCount(
	backend: ReturnType<typeof installBridgeViewerMockedBackend>,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingProjectionResponses.length === count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected exactly ${count} pending projection responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingProjectionResponseExactCount(backend, count, remainingAttempts - 1);
}

async function waitForProjectionRequestCount(
	backend: ReturnType<typeof installBridgeViewerMockedBackend>,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.projectionRequests.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} projection requests`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForProjectionRequestCount(backend, count, remainingAttempts - 1);
}

async function waitForBridgeViewerRenderedCodeGeometry(remainingAttempts = 180): Promise<void> {
	const geometry = bridgeViewerCodeGeometry();
	if (
		geometry.containerCount > 0 &&
		geometry.lineCount > 0 &&
		geometry.firstContainerWidth > 0 &&
		geometry.firstContainerHeight > 0
	) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge CodeView geometry; geometry=${JSON.stringify(geometry)}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerRenderedCodeGeometry(remainingAttempts - 1);
}

async function waitForProjectionAbortCount(
	backend: ReturnType<typeof installBridgeViewerMockedBackend>,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.projectionAbortKeys.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} projection aborts`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForProjectionAbortCount(backend, count, remainingAttempts - 1);
}

async function waitForPendingContentResponseCount(
	backend: ReturnType<typeof installBridgeViewerMockedBackend>,
	count: number,
	remainingAttempts = 180,
): Promise<void> {
	if (backend.pendingContentResponses.length >= count) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected ${count} pending content responses`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForPendingContentResponseCount(backend, count, remainingAttempts - 1);
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}

function installPierrePackagedWorkerFetchMock(): () => void {
	const originalFetch = window.fetch.bind(window);
	window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const url = resourceUrlFromFetchInput(input);
		if (url === 'agentstudio://app/workers/pierre-diffs-worker-portable.js') {
			return new Response(pierrePortableWorkerSource, {
				headers: { 'content-type': 'application/javascript' },
			});
		}
		return await originalFetch(input, init);
	};
	return (): void => {
		window.fetch = originalFetch;
	};
}

function resourceUrlFromFetchInput(input: RequestInfo | URL): string {
	if (typeof input === 'string') {
		return input;
	}
	if (input instanceof URL) {
		return input.href;
	}
	return input.url;
}
