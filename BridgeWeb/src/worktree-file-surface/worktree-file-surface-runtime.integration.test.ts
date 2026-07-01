import { describe } from 'vitest';

import { registerWorktreeFileSurfaceRuntimeDemandTests } from './worktree-file-surface-runtime.demand.integration-suite.js';
import { registerWorktreeFileSurfaceRuntimeOpenTests } from './worktree-file-surface-runtime.open.integration-suite.js';
import { registerWorktreeFileSurfaceRuntimeResetTests } from './worktree-file-surface-runtime.reset.integration-suite.js';

describe('worktree file surface runtime', () => {
	registerWorktreeFileSurfaceRuntimeOpenTests();
	registerWorktreeFileSurfaceRuntimeDemandTests();
	registerWorktreeFileSurfaceRuntimeResetTests();
});
