cask "cbonsai-saver" do
  version "1.1.5"
  sha256 "18046612d08d277e5a9d4a3b7c455fc1c518443f525f73b5e353cc91922fd079"

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
