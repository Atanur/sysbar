cask "sysbar" do
  version "0.6.2"
  sha256 "1abcd31b5688ef0b7f4a095c56fa9b5b77cee636aa0edbf54414790616639d1b"

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
