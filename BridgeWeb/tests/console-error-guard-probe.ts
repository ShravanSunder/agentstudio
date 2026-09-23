import { describe, expect, test } from 'vitest';

export const actWarningProbeComponentName = 'ActWarningProbe';

interface DefineConsoleErrorGuardProbeProps {
	readonly suiteName: string;
	readonly emitActWarning: () => Promise<void>;
}

// Proves the suite's configuration loads ./console-error-guard.ts by letting the
// guard fail a real test. `test.fails` passes only when its test fails, and
// onTestFailed records why, so the following test asserts the failure came from
// the guard and names the component that updated outside act().
export function defineConsoleErrorGuardProbe(props: DefineConsoleErrorGuardProbeProps): void {
	describe(`console error guard in the ${props.suiteName} suite`, () => {
		let recordedGuardFailure = '';

		test.fails('fails a test that emits a React act() warning', async ({ onTestFailed }) => {
			onTestFailed(({ task }): void => {
				recordedGuardFailure = (task.result?.errors ?? [])
					.map((error: { readonly message: string }): string => error.message)
					.join('\n');
			});
			await props.emitActWarning();
		});

		test('reports the act() warning with the component name', () => {
			expect(recordedGuardFailure).toContain('BridgeWeb console error guard tripped');
			expect(recordedGuardFailure).toContain(
				`An update to ${actWarningProbeComponentName} inside a test was not wrapped in act(...)`,
			);
		});
	});
}
