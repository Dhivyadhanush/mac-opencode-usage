cask "opencode-usage" do
  version :latest
  sha256 :no_check

  # Latest release asset: drives both install and `brew upgrade`.
  url "https://github.com/Myleshen/mac-opencode-usage/releases/latest/download/OpenCodeUsage.zip"
  name "OpenCode Usage"
  desc "Menu bar monitor for OpenCode Go usage"
  homepage "https://github.com/Myleshen/mac-opencode-usage"

  app "OpenCodeUsage.app"
end
