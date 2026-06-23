import type { BridgeIntegrityDescriptor } from '../models/bridge-resource-descriptor.js';

export interface VerifyBridgeResourceIntegrityProps {
	readonly data: Uint8Array;
	readonly integrity: BridgeIntegrityDescriptor | undefined;
}

export type BridgeResourceIntegrityResult =
	| { readonly ok: true }
	| {
			readonly ok: false;
			readonly reason: 'integrity_mismatch';
			readonly actual: string;
	  };

export async function verifyBridgeResourceIntegrity(
	props: VerifyBridgeResourceIntegrityProps,
): Promise<BridgeResourceIntegrityResult> {
	if (props.integrity === undefined) {
		return { ok: true };
	}
	const actual = await sha256IntegrityValue(props.data);
	if (actual !== props.integrity.value) {
		return {
			ok: false,
			reason: 'integrity_mismatch',
			actual,
		};
	}
	return { ok: true };
}

async function sha256IntegrityValue(data: Uint8Array): Promise<string> {
	const dataBuffer = new ArrayBuffer(data.byteLength);
	new Uint8Array(dataBuffer).set(data);
	const digest = await globalThis.crypto.subtle.digest('SHA-256', dataBuffer);
	const bytes = [...new Uint8Array(digest)];
	const hex = bytes.map((byte: number): string => byte.toString(16).padStart(2, '0')).join('');
	return `sha256:${hex}`;
}
