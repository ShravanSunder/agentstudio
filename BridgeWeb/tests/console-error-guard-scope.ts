// Which console.error messages fail a test, declared by each Vitest config
// through `provide` and read by ./console-error-guard.ts. The browser suite has
// always failed on every console.error; the node suites (unit, node-integration,
// E2E) fail only on React act() warnings.
export type ConsoleErrorGuardScope = 'every-console-error' | 'react-act-warnings';

export const everyConsoleErrorGuardScope = {
	consoleErrorGuardScope: 'every-console-error',
} as const satisfies { readonly consoleErrorGuardScope: ConsoleErrorGuardScope };

export const reactActWarningGuardScope = {
	consoleErrorGuardScope: 'react-act-warnings',
} as const satisfies { readonly consoleErrorGuardScope: ConsoleErrorGuardScope };

declare module 'vitest' {
	export interface ProvidedContext {
		consoleErrorGuardScope: ConsoleErrorGuardScope;
	}
}
