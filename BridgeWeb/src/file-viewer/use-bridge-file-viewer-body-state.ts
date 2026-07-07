import { useCallback, useRef, type MutableRefObject } from 'react';

import type { CommitOpenFileBodyProps } from './bridge-file-viewer-state.js';

export function useBridgeFileViewerBodyState(): {
	readonly clearOpenFileBody: () => void;
	readonly clearProvisionalOpenFileBody: () => void;
	readonly commitOpenFileBody: (commit: CommitOpenFileBodyProps) => void;
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly provisionalOpenFileBodyRef: MutableRefObject<string | null>;
} {
	const openFileBodyRef = useRef<string | null>(null);
	const provisionalOpenFileBodyRef = useRef<string | null>(null);

	const clearOpenFileBody = useCallback((): void => {
		openFileBodyRef.current = null;
	}, []);
	const clearProvisionalOpenFileBody = useCallback((): void => {
		provisionalOpenFileBodyRef.current = null;
	}, []);
	const commitOpenFileBody = useCallback((commit: CommitOpenFileBodyProps): void => {
		openFileBodyRef.current = commit.body;
	}, []);

	return {
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		commitOpenFileBody,
		openFileBodyRef,
		provisionalOpenFileBodyRef,
	};
}
