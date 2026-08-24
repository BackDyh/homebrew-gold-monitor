class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v0.1.3/aurumbar-0.1.3.tar.gz"
  sha256 "2fa431a6277b68014ce8cd1bdbe8a4275c7ff7d76cc50ae583934c316995ff3b"
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
