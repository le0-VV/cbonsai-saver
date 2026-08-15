cask "cbonsai-saver" do
  version "1.1.7"
  sha256 "174fc29a148d26c69a2a012e65862a1231c59300c5c4a6658b54cbaf91fb6bf5"

  url "https://github.com/le0-VV/cbonsai-saver/releases/download/#{version}/cbonsai-saver-#{version}.zip",
      verified: "github.com/le0-VV/cbonsai-saver/"
  name "cbonsai saver"
  desc "macOS screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :big_sur

  screen_saver "cbonsai saver.saver"

  postflight do
    installed_saver = Pathname.new(cask.config.screen_saverdir).expand_path/"cbonsai saver.saver"
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", installed_saver.to_s]
    system_command "/usr/bin/killall",
                   args: ["legacyScreenSaver"],
                   must_succeed: false
  end

  zap trash: [
    "~/Library/Preferences/ByHost/wang.leonard.cbonsai-saver.*",
    "~/Library/Screen Savers/cbonsai saver.saver",
  ]
end
