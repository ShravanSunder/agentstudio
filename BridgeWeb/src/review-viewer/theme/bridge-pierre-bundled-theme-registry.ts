type BridgeThemeColorScheme = 'dark' | 'light';

type BridgeThemeLike = Record<string, unknown>;

type BridgeThemeLoader<TTheme extends BridgeThemeLike = BridgeThemeLike> = () => Promise<TTheme>;

interface BridgeThemeDescriptor<TTheme extends BridgeThemeLike = BridgeThemeLike> {
	readonly name: string;
	readonly load: BridgeThemeLoader<TTheme>;
	readonly collection?: string;
	readonly colorScheme?: BridgeThemeColorScheme;
	readonly displayName?: string;
}

interface BridgeThemeCollectionFilter {
	readonly collection?: string;
	readonly colorScheme?: BridgeThemeColorScheme;
}

type BridgeThemeCollectionComparator<TTheme extends BridgeThemeLike = BridgeThemeLike> = (
	leftTheme: BridgeThemeDescriptor<TTheme>,
	rightTheme: BridgeThemeDescriptor<TTheme>,
) => number;

interface BridgeThemeResolver<TTheme extends BridgeThemeLike = BridgeThemeLike> {
	readonly registerTheme: (name: string, load: BridgeThemeLoader<TTheme>) => void;
}

interface BridgeThemeCollection<TTheme extends BridgeThemeLike = BridgeThemeLike> {
	readonly getTheme: (name: string) => BridgeThemeDescriptor<TTheme> | undefined;
	readonly getThemeNames: (filter?: BridgeThemeCollectionFilter) => readonly string[];
	readonly getThemes: (
		filter?: BridgeThemeCollectionFilter,
	) => readonly BridgeThemeDescriptor<TTheme>[];
	readonly hasTheme: (name: string) => boolean;
	readonly orderBy: (
		compare: BridgeThemeCollectionComparator<TTheme>,
	) => BridgeThemeCollection<TTheme>;
	readonly pick: (names: readonly string[]) => BridgeThemeCollection<TTheme>;
	readonly registerInto: (resolver: BridgeThemeResolver<TTheme>) => void;
}

interface CreateThemeOptions<TTheme extends BridgeThemeLike = BridgeThemeLike> {
	readonly name: string;
	readonly load: BridgeThemeLoader<TTheme>;
	readonly collection?: string;
	readonly colorScheme?: BridgeThemeColorScheme;
	readonly displayName?: string;
}

export function createTheme<TTheme extends BridgeThemeLike = BridgeThemeLike>(
	options: CreateThemeOptions<TTheme>,
): BridgeThemeDescriptor<TTheme> {
	return {
		name: options.name,
		load: options.load,
		...(options.collection === undefined ? {} : { collection: options.collection }),
		...(options.colorScheme === undefined ? {} : { colorScheme: options.colorScheme }),
		...(options.displayName === undefined ? {} : { displayName: options.displayName }),
	};
}

export const pierreThemes = createEmptyBridgeThemeCollection();
export const shikiThemes = createEmptyBridgeThemeCollection();
export const themes = createEmptyBridgeThemeCollection();

function createEmptyBridgeThemeCollection<
	TTheme extends BridgeThemeLike = BridgeThemeLike,
>(): BridgeThemeCollection<TTheme> {
	const collection: BridgeThemeCollection<TTheme> = {
		getTheme: (): undefined => undefined,
		getThemeNames: (): readonly string[] => [],
		getThemes: (): readonly BridgeThemeDescriptor<TTheme>[] => [],
		hasTheme: (): boolean => false,
		orderBy: (): BridgeThemeCollection<TTheme> => collection,
		pick: (): BridgeThemeCollection<TTheme> => collection,
		registerInto: (): void => {},
	};
	return collection;
}
