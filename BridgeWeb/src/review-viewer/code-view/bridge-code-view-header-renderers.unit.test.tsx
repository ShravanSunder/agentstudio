import { Children, isValidElement, type ReactElement, type ReactNode } from 'react';
import { describe, expect, test } from 'vitest';

import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { BridgeCodeViewFilePresentationToggle } from './bridge-code-view-file-presentation-toggle.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { createBridgeCodeViewHeaderRenderers } from './bridge-code-view-panel-support.js';

describe('Bridge CodeView header renderers', () => {
	test('appends the Diff and Open icon toggle after file counts', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const descriptor = reviewPackage.itemsById['docs-plan'];
		if (descriptor === undefined) throw new Error('expected Markdown fixture item');
		const presentationChanges: Array<{
			readonly itemId: string;
			readonly presentation: 'diff' | 'open';
		}> = [];
		const renderers = createBridgeCodeViewHeaderRenderers({
			collapsedItemIds: new Set(),
			isFilePresentationOpen: (): boolean => false,
			onHeaderVisibilityChange: (): void => {},
			onFilePresentationChange: (itemId, presentation): void => {
				presentationChanges.push({ itemId, presentation });
			},
			onToggleItemCollapse: (): void => {},
			reviewPackage,
		});

		const metadata = requireReactElement(
			renderers.renderHeaderMetadata(materializeBridgeCodeViewLoadingItem(descriptor)),
		);
		const metadataChildren = Children.toArray(metadata.props.children);
		const presentationToggleElement = metadataChildren.find(
			(child): child is ReactElement<Parameters<typeof BridgeCodeViewFilePresentationToggle>[0]> =>
				isValidElement(child) && child.type === BridgeCodeViewFilePresentationToggle,
		);
		const presentationToggleRoot =
			presentationToggleElement === undefined
				? undefined
				: requireReactElement(
						BridgeCodeViewFilePresentationToggle(presentationToggleElement.props),
					);
		const presentationToggle = findElementByTestId(
			presentationToggleRoot,
			'bridge-code-view-header-presentation-toggle',
		);

		expect(metadataChildren.map(visibleReactText).join(' ').replaceAll(/\s+/gu, ' ')).toContain(
			`-${descriptor.deletions} +${descriptor.additions}`,
		);
		expect(presentationToggle).toBeDefined();
		expect(metadataChildren.at(-1)).toBe(presentationToggleElement);
		expect(findElementByAriaLabel(presentationToggle, 'Diff')).not.toBeNull();
		const openToggle = findElementByAriaLabel(presentationToggle, 'Open');
		expect(openToggle).not.toBeNull();
		let defaultPrevented = false;
		let propagationStopped = false;
		openToggle?.props.onClick?.({
			preventDefault: (): void => {
				defaultPrevented = true;
			},
			stopPropagation: (): void => {
				propagationStopped = true;
			},
		});
		expect(defaultPrevented).toBe(false);
		expect(propagationStopped).toBe(true);
		presentationToggle?.props.onValueChange?.(['diff', 'open']);
		expect(presentationChanges).toEqual([{ itemId: descriptor.itemId, presentation: 'open' }]);
	});
});

function requireReactElement(node: ReactNode): ReactElement<{ readonly children?: ReactNode }> {
	if (!isValidElement<{ readonly children?: ReactNode }>(node)) {
		throw new Error('Expected React element');
	}
	return node;
}

function findElementByTestId(
	node: ReactNode,
	testId: string,
): ReactElement<{
	readonly 'data-testid'?: string;
	readonly children?: ReactNode;
	readonly onValueChange?: (values: readonly string[]) => void;
}> | null {
	if (
		!isValidElement<{
			readonly 'data-testid'?: string;
			readonly children?: ReactNode;
			readonly onValueChange?: (values: readonly string[]) => void;
		}>(node)
	) {
		return null;
	}
	if (node.props['data-testid'] === testId) return node;
	for (const child of Children.toArray(node.props.children)) {
		const match = findElementByTestId(child, testId);
		if (match !== null) return match;
	}
	return null;
}

function findElementByAriaLabel(
	node: ReactNode,
	ariaLabel: string,
): ReactElement<{
	readonly 'aria-label'?: string;
	readonly children?: ReactNode;
	readonly onClick?: (event: {
		readonly preventDefault: () => void;
		readonly stopPropagation: () => void;
	}) => void;
	readonly onPressedChange?: (pressed: boolean) => void;
}> | null {
	if (
		!isValidElement<{
			readonly 'aria-label'?: string;
			readonly children?: ReactNode;
			readonly onClick?: (event: {
				readonly preventDefault: () => void;
				readonly stopPropagation: () => void;
			}) => void;
			readonly onPressedChange?: (pressed: boolean) => void;
		}>(node)
	) {
		return null;
	}
	if (node.props['aria-label'] === ariaLabel) return node;
	for (const child of Children.toArray(node.props.children)) {
		const match = findElementByAriaLabel(child, ariaLabel);
		if (match !== null) return match;
	}
	return null;
}

function visibleReactText(node: ReactNode): string {
	if (typeof node === 'string' || typeof node === 'number') return String(node);
	if (!isValidElement<{ readonly children?: ReactNode }>(node)) return '';
	return Children.toArray(node.props.children).map(visibleReactText).join(' ');
}
