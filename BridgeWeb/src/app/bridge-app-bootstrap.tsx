import { createRoot } from 'react-dom/client';

import { BridgeApp } from './bridge-app.js';

const rootElement = document.querySelector('#root');

if (rootElement !== null) {
	createRoot(rootElement).render(<BridgeApp />);
}
