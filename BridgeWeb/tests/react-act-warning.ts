// React reports an act() problem through console.error in one of two forms:
// "An update to <Component> inside a test was not wrapped in act(...)" and
// "The current testing environment is not configured to support act(...)".
// The console error guard and the E2E page-console relay share this predicate.
const reactActWarningPattern = /not wrapped in act\(|not configured to support act\(/u;

export function isReactActWarning(message: string): boolean {
	return reactActWarningPattern.test(message);
}
