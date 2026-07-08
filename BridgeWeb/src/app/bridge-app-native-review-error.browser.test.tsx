// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import type { ReactElement } from 'react';
import { vi } from 'vitest';

import type { BridgeAppProps } from './bridge-app.js';

vi.mock('./bridge-app.js', async (importOriginal): Promise<typeof import('./bridge-app.js')> => {
	const actual = await importOriginal<typeof import('./bridge-app.js')>();
	const React = await import('react');
	const { createInProcessBridgeReviewWorkerTransportFactory } =
		await import('./bridge-app-native-review-error.browser.test-support.js');
	const ActualBridgeApp = actual.BridgeApp as (props: BridgeAppProps) => ReactElement;
	const BridgeApp = (props: BridgeAppProps = {}): ReactElement =>
		React.createElement(ActualBridgeApp, {
			...props,
			reviewWorkerTransportFactory:
				props.reviewWorkerTransportFactory ??
				createInProcessBridgeReviewWorkerTransportFactory({
					sendSchemeRpcCommand: async (): Promise<void> => {},
				}),
		});
	return {
		...actual,
		BridgeApp,
	};
});

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode wrapper loads the shared intake suite for this entrypoint.
import './bridge-app-native-review-error.browser.intake-suite.js';
// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode wrapper loads the shared metadata suite for this entrypoint.
import './bridge-app-native-review-error.browser.metadata-suite.js';
