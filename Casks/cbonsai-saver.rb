cask "cbonsai-saver" do
  version "1.1"
  sha256 "ae87070e2bdcff20caf766a95106a9f3585764b0738c6ff3ffc7bc342723978e"

  url "https://github.com/le0-VV/cbonsai-saver/releases/download/#{version}/cbonsai-saver-#{version}.zip",
      verified: "github.com/le0-VV/cbonsai-saver/"
  name "cbonsai saver"
  desc "macOS screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  screen_saver "cbonsai saver.saver"

  zap trash: [
    "~/Library/Preferences/ByHost/wang.leonard.cbonsai-saver.*",
    "~/Library/Screen Savers/cbonsai saver.saver",
  ]
end
