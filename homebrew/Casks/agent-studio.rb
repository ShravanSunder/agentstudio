cask "agent-studio" do
  version "0.0.9"
  sha256 "c12d9eef9a0b29fc1d1ee2268b06fafc756c16eb5121fc41dfb66a8c8a111bb3"

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
