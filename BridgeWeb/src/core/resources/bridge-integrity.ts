import type { BridgeIntegrityDescriptor } from '../models/bridge-resource-descriptor.js';

export interface VerifyBridgeResourceIntegrityProps {
	readonly data: Uint8Array;
	readonly integrity: BridgeIntegrityDescriptor | undefined;
}

export type BridgeResourceIntegrityResult =
	| {
			readonly ok: true;
			readonly authoritative: boolean;
	  }
	| {
			readonly ok: false;
			readonly reason: 'chunk_manifest_unsupported' | 'integrity_mismatch';
			readonly actual?: string;
	  };

export async function verifyBridgeResourceIntegrity(
	props: VerifyBridgeResourceIntegrityProps,
): Promise<BridgeResourceIntegrityResult> {
	if (props.integrity === undefined) {
		return { ok: true, authoritative: true };
	}
	if (props.integrity.kind === 'previewOnly') {
		return { ok: true, authoritative: false };
	}
	if (props.integrity.kind === 'chunkManifest') {
		return { ok: false, reason: 'chunk_manifest_unsupported' };
	}
	const actual = await sha256IntegrityValue(props.data);
	if (actual !== props.integrity.value) {
		return {
			ok: false,
			reason: 'integrity_mismatch',
			actual,
		};
	}
	return { ok: true, authoritative: true };
}

async function sha256IntegrityValue(data: Uint8Array): Promise<string> {
	const dataBuffer = new ArrayBuffer(data.byteLength);
	new Uint8Array(dataBuffer).set(data);
	const digest = await globalThis.crypto.subtle.digest('SHA-256', dataBuffer);
	const bytes = [...new Uint8Array(digest)];
	const hex = bytes.map((byte: number): string => byte.toString(16).padStart(2, '0')).join('');
	return `sha256:${hex}`;
}
