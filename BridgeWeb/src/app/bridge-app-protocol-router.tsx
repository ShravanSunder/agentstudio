import type { ReactElement } from 'react';
import { z } from 'zod';

import { BridgeApp, type BridgeAppProps } from './bridge-app.js';

export const bridgeAppProtocolSchema = z.enum(['review', 'worktree-file']);
export type BridgeAppProtocol = z.infer<typeof bridgeAppProtocolSchema>;

export type BridgeAppProtocolRouterProps = BridgeAppProps & {
	readonly protocol?: BridgeAppProtocol;
};

const bridgeAppProtocolAttributeName = 'data-bridge-app-protocol';

export function BridgeAppProtocolRouter(props: BridgeAppProtocolRouterProps = {}): ReactElement {
	const { protocol: explicitProtocol, ...appProps } = props;
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

export function resolveBridgeAppProtocolFromElement(element: Element): BridgeAppProtocol {
	const rawProtocol = element.getAttribute(bridgeAppProtocolAttributeName) ?? 'review';
	const parsedProtocol = bridgeAppProtocolSchema.safeParse(rawProtocol);
	return parsedProtocol.success ? parsedProtocol.data : 'review';
}
