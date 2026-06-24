import type { BridgeDescriptorRef } from '../../../core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDemandStimulus,
	WorktreeFileDescriptor,
	WorktreeFileInvalidation,
	WorktreeOpenFileStaleReason,
} from '../models/worktree-file-protocol-models.js';

export interface WorktreeOpenFileSessionState {
	readonly openFileSessionId: string;
	readonly path: string;
	readonly fileId: string;
	readonly descriptorRef: BridgeDescriptorRef;
	readonly renderContentKey: string;
	readonly status: 'opening' | 'fresh' | 'stale' | 'refreshing' | 'failed' | 'closed';
	readonly staleReason?: WorktreeOpenFileStaleReason;
	readonly latestDescriptorRef?: BridgeDescriptorRef;
	readonly latestDescriptor?: WorktreeFileDescriptor;
}

export interface WorktreeFileSurfaceState {
	readonly openFileSessionsById: Readonly<Record<string, WorktreeOpenFileSessionState>>;
}

export interface OpenWorktreeFileSessionProps {
	readonly state: WorktreeFileSurfaceState;
	readonly descriptor: WorktreeFileDescriptor;
	readonly openFileSessionId: string;
}

export interface ApplyWorktreeFileInvalidationToStateProps {
	readonly state: WorktreeFileSurfaceState;
	readonly invalidation: WorktreeFileInvalidation;
}

export interface ApplyWorktreeFileInvalidationResult {
	readonly state: WorktreeFileSurfaceState;
	readonly stimuli: readonly WorktreeFileDemandStimulus[];
}

export interface RefreshWorktreeOpenFileSessionProps {
	readonly state: WorktreeFileSurfaceState;
	readonly openFileSessionId: string;
}

export interface RefreshWorktreeOpenFileSessionResult {
	readonly state: WorktreeFileSurfaceState;
	readonly stimulus?: WorktreeFileDemandStimulus;
}

export function createWorktreeFileSurfaceState(): WorktreeFileSurfaceState {
	return {
		openFileSessionsById: {},
	};
}

export function openWorktreeFileSession(
	props: OpenWorktreeFileSessionProps,
): WorktreeFileSurfaceState {
	const session: WorktreeOpenFileSessionState = {
		openFileSessionId: props.openFileSessionId,
		path: props.descriptor.path,
		fileId: props.descriptor.fileId,
		descriptorRef: props.descriptor.contentDescriptor.ref,
		renderContentKey: props.descriptor.contentDescriptor.ref.descriptorId,
		status: 'fresh',
	};
	return {
		...props.state,
		openFileSessionsById: {
			...props.state.openFileSessionsById,
			[props.openFileSessionId]: session,
		},
	};
}

export function applyWorktreeFileInvalidationToState(
	props: ApplyWorktreeFileInvalidationToStateProps,
): ApplyWorktreeFileInvalidationResult {
	const updatedSessions = Object.fromEntries(
		Object.entries(props.state.openFileSessionsById).map(([sessionId, session]) => {
			if (!doesInvalidationMatchOpenSession(props.invalidation, session)) {
				return [sessionId, session];
			}
			return [sessionId, makeStaleOpenFileSession(session, props.invalidation)];
		}),
	);
	const invalidatedStimuli = Object.values(props.state.openFileSessionsById)
		.filter((session) => doesInvalidationMatchOpenSession(props.invalidation, session))
		.map(
			(session): WorktreeFileDemandStimulus => ({
				kind: 'openFileInvalidated',
				descriptorRef: session.descriptorRef,
			}),
		);
	return {
		state: {
			...props.state,
			openFileSessionsById: updatedSessions,
		},
		stimuli: invalidatedStimuli,
	};
}

export function refreshWorktreeOpenFileSession(
	props: RefreshWorktreeOpenFileSessionProps,
): RefreshWorktreeOpenFileSessionResult {
	const session = props.state.openFileSessionsById[props.openFileSessionId];
	if (
		session === undefined ||
		session.status !== 'stale' ||
		session.latestDescriptorRef === undefined
	) {
		return { state: props.state };
	}
	return {
		state: {
			...props.state,
			openFileSessionsById: {
				...props.state.openFileSessionsById,
				[props.openFileSessionId]: {
					...session,
					descriptorRef: session.latestDescriptorRef,
					renderContentKey: session.latestDescriptorRef.descriptorId,
					status: 'refreshing',
				},
			},
		},
		stimulus: {
			kind: 'explicitRefresh',
			descriptorRef: session.latestDescriptorRef,
		},
	};
}

function makeStaleOpenFileSession(
	session: WorktreeOpenFileSessionState,
	invalidation: WorktreeFileInvalidation,
): WorktreeOpenFileSessionState {
	if (invalidation.latestDescriptor === undefined) {
		return {
			...session,
			status: 'stale',
			staleReason: invalidation.reason,
		};
	}
	return {
		...session,
		status: 'stale',
		staleReason: invalidation.reason,
		latestDescriptorRef: invalidation.latestDescriptor.contentDescriptor.ref,
		latestDescriptor: invalidation.latestDescriptor,
	};
}

function doesInvalidationMatchOpenSession(
	invalidation: WorktreeFileInvalidation,
	session: WorktreeOpenFileSessionState,
): boolean {
	return invalidation.fileId === session.fileId || invalidation.path === session.path;
}
