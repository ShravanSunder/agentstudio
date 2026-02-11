# Setting Up the Homebrew Tap Repo

## 1. Create the repo

Go to GitHub and create a new **public** repository:

- **Name:** `homebrew-agentstudio` (the `homebrew-` prefix is required)
- **Owner:** `ShravanSunder`
- **Visibility:** Public
- **Initialize with:** README

## 2. Clone and add the Cask

```bash
git clone https://github.com/ShravanSunder/homebrew-agentstudio.git
cd homebrew-agentstudio

mkdir -p Casks
```

Copy `homebrew/Casks/agent-studio.rb` from the main repo into `Casks/agent-studio.rb`.

Then add a README:

```bash
cat > README.md << 'EOF'
# Homebrew Tap for Agent Studio

## Installation

```bash
brew tap ShravanSunder/agentstudio
brew install --cask agent-studio
```

## What gets installed

- **Agent Studio** — macOS terminal app with embedded Ghostty terminal emulator
- **tmux** — terminal multiplexer (installed as dependency if not present)

## Updating

```bash
brew update
brew upgrade --cask agent-studio
```

## Uninstalling

```bash
brew uninstall --cask agent-studio
brew untap ShravanSunder/agentstudio
```
EOF
```

Commit and push:

```bash
git add .
git commit -m "Initial Cask for agent-studio"
git push
```

## 3. Create the Personal Access Token (PAT)

This is needed so the auto-update workflow in the main repo can push to the tap repo.

1. Go to https://github.com/settings/tokens?type=beta (Fine-grained tokens)
2. Click **Generate new token**
3. Settings:
   - **Name:** `homebrew-tap-updater`
   - **Expiration:** 1 year (or custom)
   - **Repository access:** Select `homebrew-agentstudio` only
   - **Permissions:** Contents → Read and write
4. Copy the token

## 4. Add the secret to the main repo

1. Go to `https://github.com/ShravanSunder/agentstudio/settings/secrets/actions`
2. Click **New repository secret**
3. **Name:** `HOMEBREW_TAP_TOKEN`
4. **Value:** Paste the PAT from step 3
5. Click **Add secret**

## 5. Test the tap locally

```bash
brew tap ShravanSunder/agentstudio
brew install --cask agent-studio
```

## How auto-updates work

When a new **non-prerelease** GitHub Release is published in the main `agentstudio` repo:

1. The `update-homebrew.yml` workflow triggers
2. It downloads the release ZIP and computes its SHA256
3. It checks out the `homebrew-agentstudio` tap repo
4. Updates the Cask file with the new version and SHA256
5. Commits and pushes to the tap repo

Users then get the update via `brew update && brew upgrade --cask agent-studio`.
