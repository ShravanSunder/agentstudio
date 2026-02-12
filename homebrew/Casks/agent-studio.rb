cask "agent-studio" do
  version "0.0.1-alpha"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/ShravanSunder/agentstudio/releases/download/v#{version}/AgentStudio-v#{version}-macos.zip"
  name "Agent Studio"
  desc "macOS terminal application with Ghostty terminal emulator and project management"
  homepage "https://github.com/ShravanSunder/agentstudio"

  depends_on macos: ">= :sonoma"
  depends_on formula: "tmux"

  app "AgentStudio.app"

  zap trash: [
    "~/Library/Preferences/com.agentstudio.app.plist",
    "~/Library/Caches/com.agentstudio.app",
    "~/Library/Application Support/AgentStudio",
  ]
end
