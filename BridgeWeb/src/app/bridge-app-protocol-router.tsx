import type { ReactElement } from 'react';
import { z } from 'zod';

import { WorktreeFileApp } from '../worktree-file-surface/worktree-file-app.js';
import { BridgeApp, type BridgeAppProps } from './bridge-app.js';

export const bridgeAppProtocolSchema = z.enum(['review', 'worktree-file']);
export type BridgeAppProtocol = z.infer<typeof bridgeAppProtocolSchema>;

export interface BridgeAppProtocolRouterProps extends BridgeAppProps {
	readonly protocol?: BridgeAppProtocol;
}

const bridgeAppProtocolAttributeName = 'data-bridge-app-protocol';

export function BridgeAppProtocolRouter(props: BridgeAppProtocolRouterProps = {}): ReactElement {
	const protocol = props.protocol ?? resolveBridgeAppProtocolFromElement(document.documentElement);
	switch (protocol) {
		case 'review':
			return <BridgeApp {...props} />;
		case 'worktree-file':
			return <WorktreeFileApp />;
	}
	return <BridgeApp {...props} />;
}

export function resolveBridgeAppProtocolFromElement(element: Element): BridgeAppProtocol {
	const rawProtocol = element.getAttribute(bridgeAppProtocolAttributeName) ?? 'review';
	const parsedProtocol = bridgeAppProtocolSchema.safeParse(rawProtocol);
	return parsedProtocol.success ? parsedProtocol.data : 'review';
}
