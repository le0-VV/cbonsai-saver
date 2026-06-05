class CbonsaiSaver < Formula
  desc "macOS screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"
  url "https://github.com/le0-VV/cbonsai-saver/releases/download/1.1.1/cbonsai-saver-1.1.1.zip"
  sha256 "13bd552fc287207134a5858c7fd89798f53f50da531afbdc58797adf7502d38c"
  license all_of: ["GPL-3.0-or-later", "X11-distribute-modifications-variant"]

  depends_on :macos
  depends_on arch: :arm64

  def install
    (prefix/"Screen Savers").install "cbonsai saver.saver"
  end

  def caveats
    <<~EOS
      cbonsai saver was installed to:
        #{opt_prefix}/Screen Savers/cbonsai saver.saver

      Link it into your user screen saver folder:
        mkdir -p "$HOME/Library/Screen Savers"
        ln -sfn "#{opt_prefix}/Screen Savers/cbonsai saver.saver" "$HOME/Library/Screen Savers/cbonsai saver.saver"

      For automatic user screen saver installation, use:
        brew install --cask cbonsai-saver
    EOS
  end

  test do
    assert_path_exists prefix/"Screen Savers/cbonsai saver.saver/Contents/MacOS/cbonsai saver"
    assert_path_exists prefix/"Screen Savers/cbonsai saver.saver/Contents/Resources/cbonsai"
  end
end
