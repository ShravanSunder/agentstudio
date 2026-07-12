import { createRoot } from 'react-dom/client';

import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

// oxlint-disable-next-line import/no-unassigned-import -- The packaged app loads compiled CSS from index.html; this source import keeps dev/build contracts explicit.
import './bridge-app.css';

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	createRoot(rootElement).render(
		<BridgeAppProtocolRouter fileViewerProps={{ autoOpenInitialFile: true }} />,
	);
}
