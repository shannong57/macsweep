class Macsweep < Formula
  desc "Clean up and look after your Mac from a simple terminal menu"
  homepage "https://github.com/shannong57/macsweep"
  url "https://github.com/shannong57/macsweep/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "96abc4157496ca108cfd3cb6b0de973ef32481b2a2af6e883316443b58aa52d1"
  license "MIT"

  depends_on :macos

  def install
    bin.install "macsweep"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/macsweep version")
  end
end
