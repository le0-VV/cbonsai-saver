cask "cbonsai-saver" do
  version "1.1.6"
  sha256 "881ca1a790857166f499d1c60fd55bb5d24df477a2c0703915761de14efc99a0"

  url "https://github.com/le0-VV/cbonsai-saver/releases/download/#{version}/cbonsai-saver-#{version}.zip",
      verified: "github.com/le0-VV/cbonsai-saver/"
  name "cbonsai saver"
  desc "macOS screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"

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
