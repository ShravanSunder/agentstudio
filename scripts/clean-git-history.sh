#!/bin/bash
set -e

echo "⚠️  WARNING: This will rewrite git history!"
echo "This will remove large build artifacts from all commits."
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

cd "$(dirname "$0")/.."

echo "🧹 Cleaning git history..."

# Create a backup branch
git branch -f backup-before-clean HEAD
echo "✅ Created backup branch: backup-before-clean"

# Remove large files and directories from history
git filter-repo --force --invert-paths \
  --path Frameworks/macos-arm64/ \
  --path vendor/Ghostty.app/ \
  --path vendor/ghostty-macos-universal.zip \
  --path vendor/ghostty/.zig-cache/ \
  --path vendor/ghostty/macos/build/ \
  --path vendor/ghostty/zig-out/ \
  --path vendor/ghostty/vendor/ \
  --path Frameworks/GhosttyKit.xcframework/ \
  --path-glob '*.dSYM/' \
  --path-glob '*.xcframework/'

echo "✅ Git history cleaned!"
echo ""
echo "⚠️  IMPORTANT: Your remote tracking has been removed by git-filter-repo"
echo "To push to GitHub, you'll need to:"
echo ""
echo "1. Re-add your remote:"
echo "   git remote add origin <your-repo-url>"
echo ""
echo "2. Force push (this rewrites history on GitHub):"
echo "   git push -f origin main"
echo ""
echo "If something went wrong, restore from backup:"
echo "   git reset --hard backup-before-clean"
