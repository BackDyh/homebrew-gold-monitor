class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v0.1.2/aurumbar-0.1.2.tar.gz"
  sha256 "d5fbf628909fff7484a79c73090ad6d11029d9b63ed3c6e441fcabc5fad24c51"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--product", "aurumbar", "--disable-sandbox"
    bin.install ".build/release/aurumbar"
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
