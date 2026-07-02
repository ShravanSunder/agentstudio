import { useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import {
	requireBridgeViewerHTMLElement,
	waitForBridgeViewerAnimationFrame,
} from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import { makeWorktreeFileSurfaceRuntimeFetchedResource } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerApp } from './bridge-file-viewer-app.js';
import { makeFileDescriptor, makeFrames } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	makeDeferredContent,
	openFilePath,
	openFileState,
	requireDeactivateFiles,
	waitForDemandDispatchState,
	waitForRecordedFetchCount,
} from './bridge-file-viewer-browser-test-harness.js';

describe('BridgeFileViewerApp Browser Mode', () => {
	test('preloads visible file tree demand without opening a file session', async () => {
		const firstDescriptor = makeFileDescriptor({
			contentHandle: 'first-visible-content',
			fileId: 'file-first-visible',
			path: 'src/first-visible.ts',
		});
		const secondDescriptor = makeFileDescriptor({
			contentHandle: 'second-visible-content',
			fileId: 'file-second-visible',
			path: 'src/second-visible.ts',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						props.resourceUrl.includes('second-visible-content')
							? 'export const secondVisible = true;\n'
							: 'export const firstVisible = true;\n',
					);
				}}
				initialFrames={makeFrames(firstDescriptor, secondDescriptor)}
			/>,
		);

		await waitForDemandDispatchState('settled');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-stimulus-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('2');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(shell.getAttribute('data-last-demand-dispatch-first-disposition')).toBe(
			'visible-preloaded',
		);
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBe('visible');
		expect(openFileState()).toBeNull();
		expect(openFilePath()).toBeNull();
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/first-visible-content?generation=1',
			'agentstudio://resource/worktree-file/worktree.fileContent/second-visible-content?generation=1',
		]);
	});

	test('preloads only fetchable visible file tree demand', async () => {
		const textDescriptor = makeFileDescriptor({
			contentHandle: 'text-visible-content',
			fileId: 'file-text-visible',
			path: 'src/text-visible.ts',
		});
		const binaryDescriptor = makeFileDescriptor({
			contentHandle: 'binary-visible-content',
			fileId: 'file-binary-visible',
			isBinary: true,
			path: 'assets/logo.png',
		});
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'unavailable-visible-content',
			fileId: 'file-unavailable-visible',
			path: 'generated/huge.log',
			virtualizedExtentKind: 'unavailable',
		});
		const fetchedResourceUrls: string[] = [];

		render(
			<BridgeFileViewerApp
				fetchResource={async (props) => {
					fetchedResourceUrls.push(props.resourceUrl);
					return makeWorktreeFileSurfaceRuntimeFetchedResource(
						'export const textVisible = true;\n',
					);
				}}
				initialFrames={makeFrames(textDescriptor, binaryDescriptor, unavailableDescriptor)}
			/>,
		);

		await waitForDemandDispatchState('settled');

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-last-demand-dispatch-loaded-count')).toBe('1');
		expect(shell.getAttribute('data-last-demand-dispatch-failed-count')).toBe('0');
		expect(fetchedResourceUrls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/text-visible-content?generation=1',
		]);
	});

	test('ignores visible demand results that settle after Files becomes inactive', async () => {
		const visibleDescriptor = makeFileDescriptor({
			contentHandle: 'inactive-visible-content',
			fileId: 'file-inactive-visible',
			path: 'src/inactive-visible.ts',
		});
		const deferredContent = makeDeferredContent();
		const fetchedResourceUrls: string[] = [];
		let deactivateFiles: (() => void) | null = null;

		function ControlledFileViewer(): ReactElement {
			const [isActive, setIsActive] = useState(true);
			deactivateFiles = (): void => {
				setIsActive(false);
			};
			return (
				<BridgeFileViewerApp
					fetchResource={(props) => {
						fetchedResourceUrls.push(props.resourceUrl);
						return deferredContent.promise;
					}}
					initialFrames={makeFrames(visibleDescriptor)}
					isActive={isActive}
				/>
			);
		}

		render(<ControlledFileViewer />);

		await waitForRecordedFetchCount({
			expectedCount: 1,
			recordedFetches: fetchedResourceUrls,
		});
		const deactivate = requireDeactivateFiles(deactivateFiles);
		deactivate();
		await waitForBridgeViewerAnimationFrame();
		deferredContent.resolve(
			makeWorktreeFileSurfaceRuntimeFetchedResource('export const inactiveVisible = true;\n'),
		);
		await waitForBridgeViewerAnimationFrame();
		await waitForBridgeViewerAnimationFrame();

		const shell = requireBridgeViewerHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		expect(shell.getAttribute('data-file-viewer-active')).toBe('false');
		expect(shell.getAttribute('data-last-demand-dispatch-status')).toBe('idle');
		expect(shell.getAttribute('data-last-demand-dispatch-first-lane')).toBeNull();
	});
});
