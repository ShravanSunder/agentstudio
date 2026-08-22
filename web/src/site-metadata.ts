export const siteMetadata = {
  canonicalOrigin: "https://getagentstudio.dev",
  homeTitle: "Agent Studio: Native macOS workspace for coding agents",
  socialCard: {
    alt: "Agent Studio organizing multiple coding agents across repository and worktree panes.",
    height: 630,
    path: "/agent-studio-social-card.png",
    width: 1200,
  },
} as const;

export const canonicalHomeUrl = new URL("/", siteMetadata.canonicalOrigin).href;
export const canonicalSitemapUrl = new URL("/sitemap.xml", siteMetadata.canonicalOrigin).href;
