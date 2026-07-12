import { act } from 'react';
import type { ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	useBridgeFileViewerStoreBindings,
	type BridgeFileViewerStoreBindings,
} from './use-bridge-file-viewer-store-bindings.js';

describe('useBridgeFileViewerStoreBindings Browser Mode', () => {
	test('keeps only component UI choices in the File viewer store', async () => {
		let latestBindings: BridgeFileViewerStoreBindings | null = null;

		render(<BridgeFileViewerStoreBindingsProbe bind={(bindings) => (latestBindings = bindings)} />);

		await act(async () => {
			const bindings = requireBindings(latestBindings);
			bindings.viewerActions.setSearchText('Sources');
			bindings.viewerActions.setFilterMode('fetchable');
		});

		const bindings = requireBindings(latestBindings);
		expect(bindings.rootSnapshot).toMatchObject({
			searchText: 'Sources',
			filterMode: 'fetchable',
		});
		expect(Object.keys(bindings.viewerStore.getState()).toSorted()).toEqual([
			'actions',
			'rootSnapshot',
		]);
		expect(JSON.stringify(bindings.viewerStore.getState())).not.toMatch(
			/renderState|openFileState|initialSurfaceLoadState|refreshDebugState|lastOpenLoadTelemetry|lastDemandDispatchDebugState/i,
		);
	});
});

interface BridgeFileViewerStoreBindingsProbeProps {
	readonly bind: (bindings: BridgeFileViewerStoreBindings) => void;
}

function BridgeFileViewerStoreBindingsProbe(
	props: BridgeFileViewerStoreBindingsProbeProps,
): ReactElement {
	const bindings = useBridgeFileViewerStoreBindings();
	props.bind(bindings);
	return (
		<div
			data-filter-mode={bindings.rootSnapshot.filterMode}
			data-search-text={bindings.rootSnapshot.searchText}
			data-testid="bridge-file-viewer-store-bindings-probe"
		/>
	);
}

function requireBindings(
	bindings: BridgeFileViewerStoreBindings | null,
): BridgeFileViewerStoreBindings {
	expect(bindings).not.toBeNull();
	if (bindings === null) {
		throw new Error('Expected File View store bindings');
	}
	return bindings;
}
