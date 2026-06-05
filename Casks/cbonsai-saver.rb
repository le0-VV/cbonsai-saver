cask "cbonsai-saver" do
  version "1.1.1"
  sha256 "13bd552fc287207134a5858c7fd89798f53f50da531afbdc58797adf7502d38c"

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
  end

  zap trash: [
    "~/Library/Preferences/ByHost/wang.leonard.cbonsai-saver.*",
    "~/Library/Screen Savers/cbonsai saver.saver",
  ]
end
