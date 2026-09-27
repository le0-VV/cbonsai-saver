cask "cbonsai-saver" do
  version "1.1.7"
  sha256 "174fc29a148d26c69a2a012e65862a1231c59300c5c4a6658b54cbaf91fb6bf5"

  url "https://github.com/le0-VV/cbonsai-saver/releases/download/#{version}/cbonsai-saver-#{version}.zip"
  name "cbonsai saver"
  desc "Screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on :macos

  screen_saver "cbonsai saver.saver"

  preflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{staged_path}}/cbonsai saver.saver"],
        writable_paths: ["cbonsai saver.saver"]
  end

  postflight_steps do
    terminate_process "legacyScreenSaver"
  end

  zap trash: [
    "~/Library/Preferences/ByHost/wang.leonard.cbonsai-saver.*",
    "~/Library/Screen Savers/cbonsai saver.saver",
  ]
end
