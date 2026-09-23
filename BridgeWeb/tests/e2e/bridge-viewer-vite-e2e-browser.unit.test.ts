import { test } from 'vitest';

import {
	actWarningProbeComponentName,
	defineConsoleErrorGuardProbe,
} from '../console-error-guard-probe.ts';
import { reportPageActWarning } from './bridge-viewer-vite-e2e-browser.ts';

// A Chromium page reports React warnings with the component name already
// substituted, so the probe hands the E2E page-console listener that text.
defineConsoleErrorGuardProbe({
	suiteName: 'E2E page console',
	emitActWarning: async (): Promise<void> => {
		reportPageActWarning({
			text: (): string =>
				`An update to ${actWarningProbeComponentName} inside a test was not wrapped in act(...).`,
		});
	},
});

test('E2E page console messages other than act() warnings are not re-reported', () => {
	// The console error guard fails this test if the message is re-reported.
	reportPageActWarning({ text: (): string => 'Download the React DevTools' });
});
