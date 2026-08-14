class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v0.1.1/aurumbar-0.1.1.tar.gz"
  sha256 "4dcaf4d949851fb50ea3e421e0cca5b48a6da3b55947acc29c0594c5535e557c"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--product", "aurumbar", "--disable-sandbox"
    bin.install ".build/release/aurumbar"
  end

  service do
    run [opt_bin/"aurumbar"]
    run_type :immediate
    keep_alive false
    log_path var/"log/aurumbar.log"
    error_log_path var/"log/aurumbar.log"
  end

  test do
    assert_match "AurumBar #{version}", shell_output("#{bin}/aurumbar --version")
  end
end
