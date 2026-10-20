class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v0.1.4/aurumbar-0.1.4.tar.gz"
  sha256 "58935aa67700c5862b8e003ee6623655edd6694ea0d716c0310d17ea8b37b442"
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
