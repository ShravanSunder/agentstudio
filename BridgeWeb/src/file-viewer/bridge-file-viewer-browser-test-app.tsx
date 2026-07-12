import { useMemo, useRef, type ReactElement } from 'react';

import type { BridgeProductFileContentDescriptor } from '../core/comm-worker/bridge-product-content-contracts.js';
import type {
	BridgeProductSubscriptionOptions,
	BridgeProductSubscriptionUpdateOptions,
} from '../core/comm-worker/bridge-product-subscription-contracts.js';
import type { BridgeProductCallResult } from '../core/comm-worker/bridge-product-transport-contract.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	BridgeFileViewerBrowserTestApp as BridgeFileViewerAppBase,
	type BridgeFileViewerAppProps,
} from './bridge-file-viewer-app.js';
import type {
	FileMetadataEvent,
	PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import { createBridgeFileViewerBrowserTestCommWorkerTransportFactory } from './bridge-file-viewer-browser-test-harness.js';
import {
	BridgeFileViewerRuntimeTransportFactoryProvider,
	type BridgeFileViewerRuntimeTransportFactory,
} from './bridge-file-viewer-render-snapshot-controller.js';

export interface BridgeFileViewerBrowserHarnessAppProps extends BridgeFileViewerAppProps {
	readonly fileProductSession?: BridgeFileViewerBrowserTestProductSession;
	readonly fileViewCommWorkerTransportFactory?: BridgeFileViewerRuntimeTransportFactory;
	readonly initialMetadataEvents?: readonly FileMetadataEvent[];
}

export interface BridgeFileViewerBrowserTestProductSession {
	readonly currentSource?: () =>
		| BridgeProductCallResult<'file.source.current'>
		| Promise<BridgeProductCallResult<'file.source.current'>>;
	readonly initialMetadataEvents?: readonly FileMetadataEvent[];
	readonly onMetadataSubscription?: (publisher: PublishFileMetadataEvents) => void | (() => void);
	readonly onMetadataSubscriptionOpen?: (
		options: BridgeProductSubscriptionOptions<'file.metadata'>,
	) => void;
	readonly onMetadataInterestUpdate?: (
		options: BridgeProductSubscriptionUpdateOptions<'file.metadata'>,
	) => void | Promise<void>;
	readonly onWorkerCommand?: (message: BridgeWorkerMainToServerMessage) => void;
	readonly onWorkerMessagesPublisher?: (
		publisher: (messages: readonly BridgeWorkerServerToMainMessage[]) => void,
	) => void;
	readonly readContent?: (props: {
		readonly descriptor: BridgeProductFileContentDescriptor;
		readonly signal: AbortSignal;
	}) => string | Promise<string>;
}

export function BridgeFileViewerBrowserHarnessApp(
	props: BridgeFileViewerBrowserHarnessAppProps = {},
): ReactElement {
	const productSessionRef = useRef<BridgeFileViewerBrowserTestProductSession | undefined>(
		undefined,
	);
	productSessionRef.current =
		props.fileProductSession === undefined && props.initialMetadataEvents === undefined
			? undefined
			: {
					...props.fileProductSession,
					...(props.initialMetadataEvents === undefined
						? {}
						: { initialMetadataEvents: props.initialMetadataEvents }),
				};
	const fileViewCommWorkerTransportFactory = useMemo(
		() =>
			props.fileViewCommWorkerTransportFactory ??
			createBridgeFileViewerBrowserTestCommWorkerTransportFactory({ productSessionRef }),
		[props.fileViewCommWorkerTransportFactory],
	);
	const {
		fileProductSession: _fileProductSession,
		fileViewCommWorkerTransportFactory: _fileViewCommWorkerTransportFactory,
		initialMetadataEvents: _initialMetadataEvents,
		...productionProps
	} = props;
	return (
		<BridgeFileViewerRuntimeTransportFactoryProvider
			transportFactory={fileViewCommWorkerTransportFactory}
		>
			<BridgeFileViewerAppBase
				{...productionProps}
				codeViewWorkerPoolEnabled={productionProps.codeViewWorkerPoolEnabled ?? false}
			/>
		</BridgeFileViewerRuntimeTransportFactoryProvider>
	);
}
