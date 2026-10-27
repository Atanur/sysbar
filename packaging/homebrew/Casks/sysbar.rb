cask "sysbar" do
  version "0.5.7"
  sha256 "2d7cea4c90d091b002b3e5af7b1d4182f21682abfd7fdaa1cc3cc17de7cfd455"

  url "https://github.com/atanur/sysbar/releases/download/v#{version}/Sysbar-#{version}.zip"
  name "Sysbar"
  desc "Tiny system monitor for the menu bar"
  homepage "https://sysbar.atanur.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sysbar.app"

  uninstall launchctl:  "com.atanur.sysbar.fanhelper",
            quit:       "com.atanur.sysbar",
            login_item: "Sysbar"

  zap trash: [
    "/tmp/sysbar-*",
    "~/Library/Preferences/com.atanur.sysbar.plist",
  ]
end
