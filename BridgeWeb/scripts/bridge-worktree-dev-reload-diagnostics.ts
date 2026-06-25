export function parseBridgeWorktreeDevReloadIntegerList(props: {
	readonly label: string;
	readonly text: string;
}): readonly number[] {
	if (props.text.length === 0) {
		return [];
	}
	if (!/^\d+(,\d+)*$/u.test(props.text)) {
		throw new Error(
			`Expected strict nonnegative integer ${props.label} list, got ${JSON.stringify(props.text)}`,
		);
	}
	return props.text
		.split(',')
		.map((token) => parseBridgeWorktreeDevReloadIntegerToken({ label: props.label, token }));
}

export function parseBridgeWorktreeDevReloadIntegerToken(props: {
	readonly label: string;
	readonly token: string;
}): number {
	if (!/^\d+$/u.test(props.token)) {
		throw new Error(
			`Expected strict nonnegative integer ${props.label} token, got ${JSON.stringify(
				props.token,
			)}`,
		);
	}
	const value = Number(props.token);
	if (!Number.isSafeInteger(value)) {
		throw new Error(
			`Expected safe integer ${props.label} token, got ${JSON.stringify(props.token)}`,
		);
	}
	return value;
}

export function parseBridgeWorktreeDevReloadStringList(text: string): readonly string[] {
	return text.length === 0 ? [] : text.split(',').filter((token) => token.length > 0);
}
