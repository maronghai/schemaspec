class Rune < Formula
  desc "Minimal DSL for declaring database schemas using single-character symbols"
  homepage "https://github.com/rune-lang/rune"
  url "https://github.com/rune-lang/rune/releases/download/v0.280.0/rune-linux-x86_64.tar.gz"
  version "0.280.0"
  license "MIT"

  depends_on "glibc" if OS.linux?

  def install
    bin.install "rune"
  end

  test do
    system "#{bin}/rune", "--version"
  end
end
