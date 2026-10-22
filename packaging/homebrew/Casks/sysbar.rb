cask "sysbar" do
  version "0.1.0"
  sha256 "17d12a4e77d62ee9b40fa0d8b8d7afac5e534fb32b782174c736bc4730bf3b24"

  url "https://github.com/atanur/sysbar/releases/download/v#{version}/Sysbar-#{version}.zip"
  name "Sysbar"
  desc "Tiny system monitor for the menu bar"
  homepage "https://sysbar.atanur.dev"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sysbar.app"

  uninstall quit:       "com.atanur.sysbar",
            login_item: "Sysbar"

  zap trash: [
    "/tmp/sysbar-*",
    "~/Library/Preferences/com.atanur.sysbar.plist",
  ]
end
