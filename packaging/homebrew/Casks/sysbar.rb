cask "sysbar" do
  version "0.3.3"
  sha256 "c1c24ceed0cf11c40940cb7340712c0223280cb8df3d99932904c740eff57682"

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
