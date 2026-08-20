import { CodeView, type CodeViewOptions } from '@pierre/diffs';
import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import '../../app/bridge-app.css';
import { bridgeCodeViewOptions } from './bridge-code-view-options.js';
import { BridgeCodeViewPanelFrame } from './bridge-code-view-panel-frame.js';

describe('BridgeCodeViewPanelFrame View Settings', () => {
	test('keeps selected annotation rows on Pierre annotation background', () => {
		expect(bridgeCodeViewOptions.unsafeCSS).toContain('[data-line-annotation][data-selected-line]');
		expect(bridgeCodeViewOptions.unsafeCSS).toContain(
			'--diffs-line-bg: var(--diffs-annotation-bg)',
		);
	});

	test('updates options on the same mounted Pierre owner', async () => {
		// Arrange
		const mountedInstances: CodeView[] = [];
		const appliedOptions: CodeViewOptions<undefined>[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetup = CodeView.prototype.setup;
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setup = function captureInstance(root: HTMLElement): void {
			mountedInstances.push(this);
			originalSetup.call(this, root);
		};
		CodeView.prototype.setOptions = function captureOptions(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			if (options !== undefined) appliedOptions.push(options);
			originalSetOptions.call(this, options);
		};

		try {
			const initialOptions = {
				...bridgeCodeViewOptions,
				disableLineNumbers: false,
				overflow: 'wrap' as const,
			};
			const rendered = await render(
				<BridgeCodeViewPanelFrame {...frameProps} codeViewOptions={initialOptions} />,
			);
			const initialOwner = mountedInstances.at(-1);

			// Act
			const changedOptions = {
				...bridgeCodeViewOptions,
				diffIndicators: 'classic' as const,
				diffStyle: 'unified' as const,
				disableBackground: true,
				disableLineNumbers: true,
				overflow: 'scroll' as const,
			};
			await act(async (): Promise<void> => {
				await rendered.rerender(
					<BridgeCodeViewPanelFrame {...frameProps} codeViewOptions={changedOptions} />,
				);
				await Promise.resolve();
			});

			// Assert
			expect(mountedInstances).toHaveLength(1);
			expect(mountedInstances[0]).toBe(initialOwner);
			expect(appliedOptions.at(-1)).toMatchObject({
				diffIndicators: 'classic',
				diffStyle: 'unified',
				disableBackground: true,
				disableLineNumbers: true,
				overflow: 'scroll',
			});
			expect(document.querySelector('[data-testid="bridge-code-view-panel"]')).toHaveAttribute(
				'data-bridge-code-view-overflow',
				'scroll',
			);
		} finally {
			CodeView.prototype.setup = originalSetup;
			CodeView.prototype.setOptions = originalSetOptions;
		}
	});
});

const frameProps = {
	handleCodeViewPostRender: (): void => {},
	handleCodeViewScroll: (): void => {},
	handleCodeViewUserScrollIntent: (): void => {},
	headerRenderers: {
		renderHeaderMetadata: (): null => null,
		renderHeaderPrefix: (): null => null,
	},
	initialItems: [],
	materializationDiagnostic: {
		additionLineCount: 0,
		deletionLineCount: 0,
		durationMilliseconds: 0,
		fileLineCount: 0,
		itemType: 'none' as const,
		itemVersion: 0,
		modelContentState: 'none' as const,
		modelItemVersion: 0,
		updateResult: 'not-run' as const,
	},
	materializationResourceEntryCount: 0,
	materializationResourceEntryItemIds: '',
	onSelectedLinesChange: (): void => {},
	selectedChangeKind: 'none',
	selectedContentCacheKeyCount: 0,
	selectedContentCacheKeys: '',
	selectedContentCharacterCount: 0,
	selectedContentLineCount: 0,
	selectedContentRoleCount: 0,
	selectedContentRoleNames: '',
	selectedContentState: 'none' as const,
	selectedDisplayPath: null,
	selectedInitialItemIndex: -1,
	selectedInitialItemIsFirst: false,
	selectedItemId: null,
	selectedLines: null,
	selectedPresentationKind: 'none',
	selectedPresentationVersion: 'none',
	selectionScrollDiagnostic: {
		didScroll: false,
		itemId: 'none',
		itemTop: 'missing' as const,
		reason: 'not-run',
		remainingFrameBudget: 0,
	},
	setCodeViewHandle: (): void => {},
	sourceKey: 'stable-source',
	workerPoolEnabled: false,
};
