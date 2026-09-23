import {
	actWarningProbeComponentName,
	defineConsoleErrorGuardProbe,
} from './console-error-guard-probe.ts';

// The unit suite runs without a DOM, so the probe emits React's act() warning
// exactly as react-dom does: a printf template with the component name argument.
defineConsoleErrorGuardProbe({
	suiteName: 'unit',
	emitActWarning: async (): Promise<void> => {
		console.error(
			'An update to %s inside a test was not wrapped in act(...).',
			actWarningProbeComponentName,
		);
	},
});
