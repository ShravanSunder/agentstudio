import { act } from 'react';
import type { ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import { makeFileDescriptor } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	useBridgeFileViewerStoreBindings,
	type BridgeFileViewerStoreBindings,
} from './use-bridge-file-viewer-store-bindings.js';

describe('useBridgeFileViewerStoreBindings Browser Mode', () => {
	test('keeps legacy display state local while the viewer store remains UI-only', async () => {
		let latestBindings: BridgeFileViewerStoreBindings | null = null;
		const descriptor = makeFileDescriptor({ path: 'Sources/App.swift' });

		render(<BridgeFileViewerStoreBindingsProbe bind={(bindings) => (latestBindings = bindings)} />);

		await expect.poll(() => latestBindings?.openFileState.status).toBe('idle');
		await act(async () => {
			requireBindings(latestBindings).viewerActions.setOpenFileState({
				status: 'loading',
				path: 'Sources/App.swift',
				descriptor,
			});
		});
		await expect.poll(() => latestBindings?.openFileState.status).toBe('loading');

		await act(async () => {
			const bindings = requireBindings(latestBindings);
			bindings.viewerActions.setOpenFileState((currentOpenFileState) => {
				if (currentOpenFileState.status === 'idle') {
					return currentOpenFileState;
				}
				return {
					...currentOpenFileState,
					status: 'failed',
				};
			});
			bindings.viewerActions.setSearchText('Sources');
			bindings.viewerActions.setFilterMode('fetchable');
		});

		const bindings = requireBindings(latestBindings);
		expect(bindings.openFileState).toMatchObject({
			status: 'failed',
			path: 'Sources/App.swift',
		});
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
			data-open-status={bindings.openFileState.status}
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
