import { useMemo, useRef, type ReactElement } from 'react';

import type {
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	BridgeFileViewerBrowserTestApp as BridgeFileViewerAppBase,
	type BridgeFileViewerAppProps,
} from './bridge-file-viewer-app.js';
import { createBridgeFileViewerBrowserTestCommWorkerTransportFactory } from './bridge-file-viewer-browser-test-harness.js';
import {
	BridgeFileViewerRuntimeTransportFactoryProvider,
	type BridgeFileViewerRuntimeTransportFactory,
} from './bridge-file-viewer-render-snapshot-controller.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport.js';

export interface BridgeFileViewerBrowserHarnessAppProps extends Omit<
	BridgeFileViewerAppProps,
	'worktreeFileSurfaceTransport'
> {
	readonly fileViewCommWorkerTransportFactory?: BridgeFileViewerRuntimeTransportFactory;
	readonly worktreeFileSurfaceTransport?: BridgeFileViewerBrowserHarnessSurfaceTransport;
}

export interface BridgeFileViewerBrowserHarnessSurfaceTransport extends BridgeFileViewerWorktreeFileSurfaceTransport {
	readonly fetchResource?: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
}

export function BridgeFileViewerBrowserHarnessApp(
	props: BridgeFileViewerBrowserHarnessAppProps = {},
): ReactElement {
	const fetchResource = props.worktreeFileSurfaceTransport?.fetchResource;
	const fetchResourceRef = useRef(fetchResource);
	fetchResourceRef.current = fetchResource;
	const fileViewCommWorkerTransportFactory = useMemo(
		() =>
			props.fileViewCommWorkerTransportFactory ??
			createBridgeFileViewerBrowserTestCommWorkerTransportFactory({
				fetchResourceRef,
			}),
		[props.fileViewCommWorkerTransportFactory],
	);
	const {
		fileViewCommWorkerTransportFactory: _fileViewCommWorkerTransportFactory,
		...productionProps
	} = props;
	const { fetchResource: _fetchResource, ...productionSurfaceTransport } =
		productionProps.worktreeFileSurfaceTransport ?? {};
	return (
		<BridgeFileViewerRuntimeTransportFactoryProvider
			transportFactory={fileViewCommWorkerTransportFactory}
		>
			<BridgeFileViewerAppBase
				{...productionProps}
				codeViewWorkerPoolEnabled={productionProps.codeViewWorkerPoolEnabled ?? false}
				worktreeFileSurfaceTransport={productionSurfaceTransport}
			/>
		</BridgeFileViewerRuntimeTransportFactoryProvider>
	);
}
