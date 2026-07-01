import { useCallback, useRef, useState, type MutableRefObject } from 'react';

import type {
	BridgeFileViewerRenderedOpenFileContent,
	CommitOpenFileBodyProps,
} from './bridge-file-viewer-state.js';

export function useBridgeFileViewerBodyState(): {
	readonly clearOpenFileBody: () => void;
	readonly clearProvisionalOpenFileBody: () => void;
	readonly commitOpenFileBody: (commit: CommitOpenFileBodyProps) => void;
	readonly lastGoodOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly openFileBodyState: string | null;
	readonly openFileBodyVersion: number;
	readonly provisionalOpenFileBody: string | null;
	readonly provisionalOpenFileBodyRef: MutableRefObject<string | null>;
	readonly setOpenFileBodyState: (body: string | null) => void;
	readonly setProvisionalOpenFileBody: (body: string | null) => void;
} {
	const openFileBodyRef = useRef<string | null>(null);
	const provisionalOpenFileBodyRef = useRef<string | null>(null);
	const openFileBodyVersionRef = useRef(0);
	const [openFileBodyState, setOpenFileBodyState] = useState<string | null>(null);
	const [openFileBodyVersion, setOpenFileBodyVersion] = useState(0);
	const [lastGoodOpenFileContent, setLastGoodOpenFileContent] =
		useState<BridgeFileViewerRenderedOpenFileContent | null>(null);
	const [provisionalOpenFileBody, setProvisionalOpenFileBody] = useState<string | null>(null);

	const clearOpenFileBody = useCallback((): void => {
		openFileBodyRef.current = null;
		setOpenFileBodyState(null);
	}, []);
	const clearProvisionalOpenFileBody = useCallback((): void => {
		provisionalOpenFileBodyRef.current = null;
		setProvisionalOpenFileBody(null);
	}, []);
	const commitOpenFileBody = useCallback((commit: CommitOpenFileBodyProps): void => {
		const nextBodyVersion = openFileBodyVersionRef.current + 1;
		openFileBodyVersionRef.current = nextBodyVersion;
		openFileBodyRef.current = commit.body;
		setOpenFileBodyState(commit.body);
		setOpenFileBodyVersion(nextBodyVersion);
		setLastGoodOpenFileContent({
			body: commit.body,
			bodyVersion: nextBodyVersion,
			descriptor: commit.descriptor,
			path: commit.path,
		});
	}, []);

	return {
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		commitOpenFileBody,
		lastGoodOpenFileContent,
		openFileBodyRef,
		openFileBodyState,
		openFileBodyVersion,
		provisionalOpenFileBody,
		provisionalOpenFileBodyRef,
		setOpenFileBodyState,
		setProvisionalOpenFileBody,
	};
}
