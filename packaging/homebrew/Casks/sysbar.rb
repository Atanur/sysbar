cask "sysbar" do
  version "0.1.2"
  sha256 "638555206147b8e7fe3038c1b3e0009cc0e619dcf72bb0f9a0c7bfeaaf71b490"

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

  uninstall quit:       "com.atanur.sysbar",
            login_item: "Sysbar"

  zap trash: [
    "/tmp/sysbar-*",
    "~/Library/Preferences/com.atanur.sysbar.plist",
  ]
end
