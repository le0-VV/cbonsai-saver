class CbonsaiSaver < Formula
  desc "macOS screen saver that runs bundled cbonsai"
  homepage "https://github.com/le0-VV/cbonsai-saver"
  url "https://github.com/le0-VV/cbonsai-saver/releases/download/1.0/cbonsai-saver-1.0.zip"
  sha256 "04f81d0a9f4c24014b969269d6b127c9bd55492eeb31984ab3de828c4d28162a"
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
    EOS
  end

  test do
    assert_path_exists prefix/"Screen Savers/cbonsai saver.saver/Contents/MacOS/cbonsai saver"
    assert_path_exists prefix/"Screen Savers/cbonsai saver.saver/Contents/Resources/cbonsai"
  end
end
