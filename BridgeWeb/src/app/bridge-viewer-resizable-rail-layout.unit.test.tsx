import { isValidElement, type ReactElement, type ReactNode } from 'react';
import { describe, expect, test } from 'vitest';

import { BridgeViewerResizableRailLayout } from './bridge-viewer-resizable-rail-layout.js';

describe('BridgeViewerResizableRailLayout', () => {
	test('keeps inactive content and rail children mounted without rendering resizable frames', () => {
		const element = BridgeViewerResizableRailLayout({
			autosaveId: 'bridge-viewer-right-rail',
			content: <section data-testid="content-child" />,
			contentTestId: 'bridge-file-viewer-content-panel',
			handleTestId: 'bridge-file-viewer-rail-resize-handle',
			isActive: false,
			rail: <aside data-testid="rail-child" />,
			railTestId: 'bridge-file-viewer-resizable-rail',
		});

		expect(findElementByTestId(element, 'content-child')).not.toBeNull();
		expect(findElementByTestId(element, 'rail-child')).not.toBeNull();
		expect(findElementByProp(element, 'data-slot', 'resizable-panel-group')).toBeNull();
		expect(findElementByProp(element, 'data-slot', 'resizable-panel')).toBeNull();
		expect(findElementByProp(element, 'data-slot', 'resizable-handle')).toBeNull();
	});
});

function findElementByTestId(node: ReactNode, testId: string): ReactElement | null {
	return findElementByProp(node, 'data-testid', testId);
}

function findElementByProp(
	node: ReactNode,
	propName: string,
	propValue: string,
): ReactElement | null {
	if (node === null || node === undefined || typeof node !== 'object') {
		return null;
	}
	if (Array.isArray(node)) {
		for (const child of node) {
			const match = findElementByProp(child, propName, propValue);
			if (match !== null) {
				return match;
			}
		}
		return null;
	}
	if (!isValidElement<{ readonly children?: ReactNode } & Record<string, unknown>>(node)) {
		return null;
	}
	if (node.props[propName] === propValue) {
		return node;
	}
	return findElementByProp(node.props.children, propName, propValue);
}
