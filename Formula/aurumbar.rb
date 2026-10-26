class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v0.1.5/aurumbar-0.1.5.tar.gz"
  sha256 "ff5b44c5ee79005f68927e4bef83edc95ec1f70209e8d6faf00b1dfc2e6de95e"
  license "MIT"

  depends_on macos: :ventura

  def install
    bin.install "aurumbar"
  end

  service do
    run [opt_bin/"aurumbar", "run"]
    run_type :immediate
    keep_alive false
    log_path var/"log/aurumbar.log"
    error_log_path var/"log/aurumbar.log"
  end

  test do
    assert_match "AurumBar #{version}", shell_output("#{bin}/aurumbar --version")
  end
end
