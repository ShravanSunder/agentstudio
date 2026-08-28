export const siteMetadata = {
  canonicalOrigin: "https://getagentstudio.dev",
  homeTitle: "Agent Studio: Native macOS IDE for parallel coding agents",
  socialCard: {
    alt: "Agent Studio. Run dozens of agents in one workspace. Stay oriented. Miss nothing.",
    height: 630,
    path: "/agent-studio-social-card.png",
    width: 1200,
  },
} as const;

export const canonicalHomeUrl = new URL("/", siteMetadata.canonicalOrigin).href;
export const canonicalSitemapUrl = new URL("/sitemap.xml", siteMetadata.canonicalOrigin).href;
