import type { ReactElement } from 'react';
import { z } from 'zod';

import { BridgeApp, type BridgeAppProps } from './bridge-app.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

export const bridgeAppProtocolSchema = z.enum(['review', 'worktree-file']);
export type BridgeAppProtocol = z.infer<typeof bridgeAppProtocolSchema>;

export type BridgeAppProtocolRouterProps = BridgeAppProps & {
	readonly protocol?: BridgeAppProtocol;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
};

const bridgeAppProtocolAttributeName = 'data-bridge-app-protocol';

export function BridgeAppProtocolRouter(props: BridgeAppProtocolRouterProps = {}): ReactElement {
	const { navigationCommand, protocol: explicitProtocol, ...appProps } = props;
	if (navigationCommand !== undefined) {
		return (
			<BridgeApp
				{...appProps}
				navigationCommand={navigationCommand}
				viewerMode={viewerModeForBridgeViewerNavigationCommand(navigationCommand)}
			/>
		);
	}
	const protocol =
		explicitProtocol ?? resolveBridgeAppProtocolFromElement(document.documentElement);
	switch (protocol) {
		case 'review':
			return <BridgeApp {...appProps} viewerMode="review" />;
		case 'worktree-file':
			return <BridgeApp {...appProps} viewerMode="file" />;
	}
	return <BridgeApp {...appProps} viewerMode="review" />;
}

function viewerModeForBridgeViewerNavigationCommand(
	navigationCommand: BridgeViewerNavigationCommand,
): 'file' | 'review' {
	switch (navigationCommand.context) {
		case 'files':
			return 'file';
		case 'review':
			return 'review';
	}
	return 'review';
}

export function resolveBridgeAppProtocolFromElement(element: Element): BridgeAppProtocol {
	const rawProtocol = element.getAttribute(bridgeAppProtocolAttributeName) ?? 'review';
	const parsedProtocol = bridgeAppProtocolSchema.safeParse(rawProtocol);
	return parsedProtocol.success ? parsedProtocol.data : 'review';
}
