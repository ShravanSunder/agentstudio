import type { Browser } from 'playwright';

let verifierBrowser: Browser | null = null;

export function installVerifierBrowser(browser: Browser): void {
	verifierBrowser = browser;
}

export function clearVerifierBrowser(): void {
	verifierBrowser = null;
}

export function requireVerifierBrowser(): Browser {
	if (verifierBrowser === null) {
		throw new Error('Expected BridgeViewer worktree dev-server verifier browser to be installed');
	}
	return verifierBrowser;
}
