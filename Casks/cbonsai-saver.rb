cask "cbonsai-saver" do
  version "1.1.2"
  sha256 "6f3bf630d78abfd26faa6e029db4987c1aa4546076f725d42c2804116fc8eb1d"

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
