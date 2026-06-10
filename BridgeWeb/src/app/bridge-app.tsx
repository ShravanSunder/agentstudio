import type { ReactElement } from 'react';
import { useEffect } from 'react';

import { installBridgePageHandshake } from '../bridge/bridge-page-handshake.js';

export function BridgeApp(): ReactElement {
	useEffect((): (() => void) => installBridgePageHandshake(), []);

	return <div data-testid="bridge-app-root" />;
}
