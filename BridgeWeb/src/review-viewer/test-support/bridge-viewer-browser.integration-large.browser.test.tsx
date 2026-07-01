import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import { reviewPackageForBridgeAppDevFixtureScenario } from '../../app/bridge-app-dev-fixture.js';
import { BridgeApp } from '../../app/bridge-app.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../workers/pierre/bridge-pierre-dev-worker-factory.js';
import {
	bridgeViewerRenderedTextContent,
	bridgeViewerVisibleCodeTextContent,
	bridgeViewerVisibleTreeItemPaths,
	clickBridgeViewerFilterMenuOption,
	clickBridgeViewerProjectionMenuOption,
	expandBridgeViewerTreeFolder,
	findBridgeViewerTreeItemButton,
	requireBridgeViewerHTMLElement,
	setBridgeViewerSearchText,
	waitForBridgeViewerAnimationFrame,
	waitForBridgeViewerAppliedProjectionMode,
	waitForBridgeViewerCodeScrollOwner,
	waitForBridgeViewerElement,
	waitForBridgeViewerText,
	waitForBridgeViewerTreeItemAbsent,
	waitForBridgeViewerTreeItemButton,
	waitForBridgeViewerTreeScrollOwner,
	waitForBridgeViewerVisibleTreeItemPathAbsent,
} from './bridge-viewer-browser-dom.js';
import * as browserSupport from './bridge-viewer-browser.integration.test-support.js';
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
describe('Bridge viewer Browser Mode mocked backend large and streaming', () => {
	afterEach(async () => {
		cleanup();
		await Promise.resolve();
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
		disposeBridgeViewerMockedBackends();
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-nonce');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		delete window.bridgeReviewControlProbe;
	});

	test('large fixture scroll-click on a rendered tree file row materializes selected content', async () => {
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
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			const railScroll = await waitForBridgeViewerTreeScrollOwner();
			const scrolledButton = await browserSupport.waitForScrolledBridgeViewerFileTreeItemButton({
				scrollOwner: railScroll,
			});
			const scrolledPath = scrolledButton.dataset['itemPath'];
			if (scrolledPath === undefined) {
				throw new Error('expected scrolled Bridge viewer tree file button path');
			}

			scrolledButton.click();
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(scrolledPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');

			expect(browserSupport.selectedBridgeViewerPanelAttribute('data-selected-display-path')).toBe(
				scrolledPath,
			);
			expect(
				browserSupport.selectedBridgeViewerPanelAttribute(
					'data-selected-materialized-model-content-state',
				),
			).toMatch(/^(?:hydrated|windowed)$/u);
			expect(
				Number(
					browserSupport.selectedBridgeViewerPanelAttribute(
						'data-selected-content-character-count',
					),
				),
			).toBeGreaterThan(0);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('large fixture programmatic file reveal uses bounded CodeView motion', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();
		const deepPath = 'Sources/AgentStudio/source/module-24/file-292.ts';
		const selectedItemId = browserSupport.bridgeReviewFixtureItemIdForPath(fixture, deepPath);

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
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const motionSamples = await browserSupport.sampleBridgeCodeViewScrollMotion({
				frameCount: 24,
				scrollOwner: codeScroll,
				action: (): void => {
					window.dispatchEvent(
						new CustomEvent('__bridge_review_control', {
							detail: {
								method: 'bridge.diff.scrollToFile',
								itemId: selectedItemId,
							},
						}),
					);
				},
			});

			await browserSupport.waitForSelectedBridgeViewerDisplayPath(deepPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');

			const motionSummary = browserSupport.summarizeBridgeCodeViewScrollMotion(motionSamples);
			browserSupport.expectBridgeCodeViewIntentionalRevealMotion({
				context: 'programmatic file reveal',
				samples: motionSamples,
			});
			expect(motionSummary.largeFrameDeltaCount).toBeLessThanOrEqual(1);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});

	test('custom filter controls route through projection requests and render the first filtered selection', async () => {
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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const initialProjectionRequestCount = backend.projectionRequests.length;

		await clickBridgeViewerFilterMenuOption('bridge-review-facet-menu-control', 'Test');
		const testFileButton = await waitForBridgeViewerTreeItemButton(fixture.expected.testFilterPath);

		expect(testFileButton.dataset['itemPath']).toBe(fixture.expected.testFilterPath);
		expect(backend.projectionRequests.length).toBeGreaterThan(initialProjectionRequestCount);
		expect(backend.projectionRequests.at(-1)?.projectionRequest.facets).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['test'],
		});
		await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.testFilterPath);
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.testFilterText);
		expect(bridgeViewerRenderedTextContent()).not.toContain(fixture.expected.initialText);

		backend.dispose();
	});

	test('git status filter starts from all without marking every hidden-default option checked', async () => {
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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		const gitStatusFilterButton = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-review-facet-menu-control"]'),
		);
		gitStatusFilterButton.click();
		await waitForBridgeViewerElement('[data-testid="bridge-review-facet-popover"]');

		const checkedStates = [...document.querySelectorAll('[role="menuitemcheckbox"]')].map(
			(item: Element): string | null => item.getAttribute('aria-checked'),
		);
		expect(checkedStates).toEqual([
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
			'false',
		]);

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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		const initialProjectionRequestCount = backend.projectionRequests.length;
		expect(findBridgeViewerTreeItemButton(fixture.expected.initialPath)).not.toBeNull();

		await clickBridgeViewerProjectionMenuOption('Plans/specs');
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);

		expect(docsButton.dataset['itemPath']).toBe(fixture.expected.docsPath);
		expect(backend.projectionRequests.length).toBeGreaterThan(initialProjectionRequestCount);
		expect(backend.projectionRequests.at(-1)?.projectionRequest.mode).toEqual({
			kind: 'plansAndSpecs',
		});
		await waitForBridgeViewerAppliedProjectionMode('plansAndSpecs');
		const railScroll = await waitForBridgeViewerTreeScrollOwner();
		await waitForBridgeViewerVisibleTreeItemPathAbsent(railScroll, fixture.expected.initialPath);
		const visibleTreePaths = bridgeViewerVisibleTreeItemPaths(railScroll);
		expect(visibleTreePaths).toContain(fixture.expected.docsPath);
		expect(visibleTreePaths).not.toContain(fixture.expected.initialPath);

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
		await backend.pushMetadata();
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
			payloadKind: 'metadataDelta',
		});
		expect(backend.projectionRequests.at(-1)?.revision).toBe(fixture.streamingAppendDelta.revision);

		appendedButton.click();
		await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.appendedPath);
		await browserSupport.waitForSelectedBridgeViewerContentState('ready');
		await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.appendedText);

		expect(
			backend.requestedUrls.some((url: string): boolean =>
				url.includes(fixture.expected.appendedHeadHandleId),
			),
		).toBe(true);
		expect(
			backend.commandDetails.some((detail: unknown): boolean =>
				browserSupport.isBridgeCommandForItem(
					detail,
					'review.markFileViewed',
					'browser-streaming-append',
				),
			),
		).toBe(true);

		backend.dispose();
	});

	test('streaming append delta makes the appended path searchable without a tree reset', async () => {
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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await backend.pushDelta();
		setBridgeViewerSearchText(fixture.expected.appendedPath);
		const appendedButton = await waitForBridgeViewerTreeItemButton(fixture.expected.appendedPath);

		expect(appendedButton.dataset['itemPath']).toBe(fixture.expected.appendedPath);
		expect(backend.pushRecords).toContainEqual({
			op: 'merge',
			revision: fixture.streamingAppendDelta.revision,
			reviewGeneration: fixture.streamingAppendDelta.reviewGeneration,
			payloadKind: 'metadataDelta',
		});

		backend.dispose();
	});

	test('metadata window bootstrap makes offscreen paths searchable without a package body', async () => {
		const fixture = makeBridgeViewerBrowserFixture();
		const backend = installBridgeViewerMockedBackend(fixture);
		const deepPath = 'tree/module-07/file-095.ts';

		render(
			<BridgeApp
				codeViewWorkerPoolEnabled={false}
				fetchContent={backend.fetchContent}
				markdownWorkerClient={null}
				projectionWorkerClient={backend.projectionWorkerClient}
			/>,
		);
		await backend.pushMetadata();
		await waitForBridgeViewerElement('[data-testid="review-viewer-shell"]');
		for (let attempt = 0; attempt < 30; attempt += 1) {
			const itemCount = Number(
				document
					.querySelector('[data-testid="bridge-code-view-panel"]')
					?.getAttribute('data-code-view-item-count') ?? '0',
			);
			if (itemCount > 80) {
				break;
			}
			await waitForBridgeViewerAnimationFrame();
		}

		setBridgeViewerSearchText(deepPath);
		await waitForBridgeViewerTreeItemButton(deepPath, 30);
		const deepButton = findBridgeViewerTreeItemButton(deepPath);

		expect(deepButton?.dataset['itemPath']).toBe(deepPath);
		expect(backend.pushRecords.some((record) => record.payloadKind === 'metadataWindow')).toBe(
			true,
		);

		backend.dispose();
	});

	test('stale metadata replacements cannot erase a newer accepted delta', async () => {
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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await backend.pushDelta();
		await expandBridgeViewerTreeFolder('streaming/append');
		await waitForBridgeViewerTreeItemButton(fixture.expected.appendedPath);
		const projectionRequestCountAfterDelta = backend.projectionRequests.length;

		await backend.pushMetadata(fixture.reviewPackage);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(findBridgeViewerTreeItemButton(fixture.expected.appendedPath)).not.toBeNull();
		expect(backend.projectionRequests).toHaveLength(projectionRequestCountAfterDelta);
		expect(backend.pushRecords).toContainEqual({
			op: 'replace',
			revision: fixture.reviewPackage.revision,
			reviewGeneration: fixture.reviewPackage.reviewGeneration,
			payloadKind: 'metadata',
		});

		backend.dispose();
	});

	test('stale delta revision gaps cannot mutate the current metadata', async () => {
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
		await backend.pushMetadata();
		await waitForBridgeViewerText(fixture.expected.initialText);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();
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
			payloadKind: 'metadataDelta',
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
		await backend.pushMetadata();
		await browserSupport.waitForPendingProjectionResponseCount(backend, 1);
		backend.pendingProjectionResponses[0]?.resolve();
		await waitForBridgeViewerText(fixture.expected.initialText);

		await clickBridgeViewerFilterMenuOption('bridge-review-facet-menu-control', 'Test');
		await browserSupport.waitForProjectionRequestCount(backend, 2);
		await browserSupport.waitForProjectionAbortCount(backend, 1);
		await browserSupport.waitForPendingProjectionResponseExactCount(backend, 1);
		await clickBridgeViewerFilterMenuOption('bridge-review-facet-menu-control', 'Source');
		await browserSupport.waitForProjectionRequestCount(backend, 3);
		await browserSupport.waitForProjectionAbortCount(backend, 2);
		await browserSupport.waitForPendingProjectionResponseExactCount(backend, 1);

		backend.pendingProjectionResponses[0]?.resolve();
		await waitForBridgeViewerTreeItemButton(fixture.expected.searchPath);
		await waitForBridgeViewerTreeItemAbsent(fixture.expected.testFilterPath);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		expect(findBridgeViewerTreeItemButton(fixture.expected.searchPath)).not.toBeNull();
		expect(findBridgeViewerTreeItemButton(fixture.expected.testFilterPath)).toBeNull();
		expect(backend.projectionRequests[1]?.projectionRequest.facets).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['test'],
		});
		expect(backend.projectionRequests[2]?.projectionRequest.facets).toContainEqual({
			kind: 'fileClass',
			fileClasses: ['source'],
		});
		expect(backend.projectionAbortKeys.length).toBeGreaterThanOrEqual(2);
		expect(
			backend.projectionAbortKeys.every(
				(abortKey: string): boolean => abortKey === 'bridge-review-projection',
			),
		).toBe(true);

		backend.dispose();
	});

	test('selecting docs renders markdown in CodeView and keeps preview command explicit', async () => {
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
		await backend.pushMetadata();
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
		docsButton.click();
		await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);
		const codeScroll = await waitForBridgeViewerCodeScrollOwner();
		const docsItemId = browserSupport.bridgeReviewFixtureItemIdForPath(
			fixture,
			fixture.expected.docsPath,
		);
		const docsHeaderButton =
			await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(docsItemId);
		const docsHeaderOffset = await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
			collapseButton: docsHeaderButton,
			maxOffset: 8,
			scrollOwner: codeScroll,
		});
		expect(docsHeaderOffset).toBeGreaterThanOrEqual(0);
		expect(docsHeaderOffset).toBeLessThanOrEqual(8);
		expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
		expect(markdownWorker.requests).toHaveLength(0);

		document.dispatchEvent(
			new CustomEvent('__bridge_review_control', {
				detail: {
					method: 'bridge.fileView.showMarkdownPreview',
					itemId: 'browser-docs-plan',
				},
			}),
		);

		await waitForBridgeViewerElement('[data-testid="bridge-markdown-preview"]');
		await waitForBridgeViewerText('Rendered markdown preview');
		expect(markdownWorker.requests).toHaveLength(1);
		expect(markdownWorker.requests[0]?.sourcePath).toBe(fixture.expected.docsPath);

		backend.dispose();
	});

	test('large fixture markdown file selection pins the selected header in CodeView', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();
		const docsItemId = browserSupport.bridgeReviewFixtureItemIdForPath(
			fixture,
			fixture.expected.docsPath,
		);

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
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.largePath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(fixture.expected.largeText);

			const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
			docsButton.click();
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(fixture.expected.docsPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(
				fixture.expected.docsMarkdownHeading,
			);
			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const docsHeaderButton =
				await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(docsItemId);
			const docsHeaderOffset = await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
				collapseButton: docsHeaderButton,
				maxOffset: 8,
				scrollOwner: codeScroll,
			});

			expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
			expect(bridgeViewerVisibleCodeTextContent(codeScroll)).toContain(
				fixture.expected.docsMarkdownHeading,
			);
			expect(docsHeaderOffset).toBeGreaterThanOrEqual(0);
			expect(docsHeaderOffset).toBeLessThanOrEqual(8);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
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
		await backend.pushMetadata();
		const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
		docsButton.click();
		await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);
		document.dispatchEvent(
			new CustomEvent('__bridge_review_control', {
				detail: {
					method: 'bridge.fileView.showMarkdownPreview',
					itemId: 'browser-docs-plan',
				},
			}),
		);
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

	test('selecting a file from markdown preview restores CodeView and pins the selected header', async () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });
		const backend = installBridgeViewerMockedBackend(fixture);
		const markdownWorker = createImmediateMarkdownWorkerClient();
		const workerFactory = createBridgePierrePortableBlobWorkerFactory();
		const deepPath = 'Sources/AgentStudio/source/module-24/file-292.ts';
		const deepExpectedText = "export const fillerbrowser-filler-large-diffshub-292 = 'head';";
		const deepItemId = browserSupport.bridgeReviewFixtureItemIdForPath(fixture, deepPath);

		try {
			render(
				<BridgeApp
					codeViewWorkerPoolEnabled={true}
					codeViewWorkerFactory={workerFactory.workerFactory}
					fetchContent={backend.fetchContent}
					markdownWorkerClient={markdownWorker.client}
					projectionWorkerClient={backend.projectionWorkerClient}
				/>,
			);
			await backend.pushMetadata(
				reviewPackageForBridgeAppDevFixtureScenario({
					fixture,
					scenario: 'scroll',
				}),
			);
			const docsButton = await waitForBridgeViewerTreeItemButton(fixture.expected.docsPath);
			docsButton.click();
			await waitForBridgeViewerText(fixture.expected.docsMarkdownHeading);

			document.dispatchEvent(
				new CustomEvent('__bridge_review_control', {
					detail: {
						method: 'bridge.fileView.showMarkdownPreview',
						itemId: 'browser-docs-plan',
					},
				}),
			);
			await waitForBridgeViewerElement('[data-testid="bridge-markdown-preview"]');
			await waitForBridgeViewerText('Rendered markdown preview');

			window.dispatchEvent(
				new CustomEvent('__bridge_review_control', {
					detail: {
						method: 'bridge.fileTree.revealPath',
						path: deepPath,
					},
				}),
			);
			await browserSupport.waitForSelectedBridgeViewerDisplayPath(deepPath);
			await browserSupport.waitForSelectedBridgeViewerContentState('ready');
			await browserSupport.waitForBridgeViewerTextWithDiagnostics(deepExpectedText);
			const codeScroll = await waitForBridgeViewerCodeScrollOwner();
			const selectedHeaderButton =
				await browserSupport.waitForBridgeCodeHeaderCollapseButtonForItem(deepItemId);
			const selectedHeaderOffset =
				await browserSupport.waitForBridgeCodeHeaderOffsetFromScrollOwner({
					collapseButton: selectedHeaderButton,
					maxOffset: 8,
					scrollOwner: codeScroll,
				});

			expect(document.querySelector('[data-testid="bridge-markdown-preview"]')).toBeNull();
			expect(bridgeViewerVisibleCodeTextContent(codeScroll)).toContain(deepExpectedText);
			expect(selectedHeaderOffset).toBeGreaterThanOrEqual(-20);
			expect(selectedHeaderOffset).toBeLessThanOrEqual(8);
		} finally {
			await browserSupport.cleanupBridgeViewerReactTreeBeforeExternalWorkerRevoke();
			workerFactory.revoke();
			backend.dispose();
		}
	});
});
