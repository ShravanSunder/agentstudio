import type { ReactElement } from 'react';
import { z } from 'zod';

import {
	BridgeFileViewerApp,
	type BridgeFileViewerAppProps,
} from '../file-viewer/bridge-file-viewer-app.js';
import { BridgeApp, type BridgeAppProps } from './bridge-app.js';
import { BridgeViewerAppShell } from './bridge-viewer-app-shell.js';

export const bridgeAppProtocolSchema = z.enum(['review', 'worktree-file']);
export type BridgeAppProtocol = z.infer<typeof bridgeAppProtocolSchema>;

export interface BridgeAppProtocolRouterProps extends BridgeAppProps {
	readonly protocol?: BridgeAppProtocol;
	readonly worktreeFileAppProps?: BridgeFileViewerAppProps;
}

const bridgeAppProtocolAttributeName = 'data-bridge-app-protocol';

export function BridgeAppProtocolRouter(props: BridgeAppProtocolRouterProps = {}): ReactElement {
	const { protocol: explicitProtocol, worktreeFileAppProps, ...reviewAppProps } = props;
	const protocol =
		explicitProtocol ?? resolveBridgeAppProtocolFromElement(document.documentElement);
	switch (protocol) {
		case 'review':
			return <BridgeApp {...reviewAppProps} />;
		case 'worktree-file':
			return (
				<BridgeViewerAppShell mode="file">
					<BridgeFileViewerApp
						{...(reviewAppProps.codeViewWorkerFactory === undefined
							? {}
							: { codeViewWorkerFactory: reviewAppProps.codeViewWorkerFactory })}
						{...(reviewAppProps.codeViewWorkerPoolEnabled === undefined
							? {}
							: { codeViewWorkerPoolEnabled: reviewAppProps.codeViewWorkerPoolEnabled })}
						{...worktreeFileAppProps}
					/>
				</BridgeViewerAppShell>
			);
	}
	return <BridgeApp {...reviewAppProps} />;
}

export function resolveBridgeAppProtocolFromElement(element: Element): BridgeAppProtocol {
	const rawProtocol = element.getAttribute(bridgeAppProtocolAttributeName) ?? 'review';
	const parsedProtocol = bridgeAppProtocolSchema.safeParse(rawProtocol);
	return parsedProtocol.success ? parsedProtocol.data : 'review';
}
