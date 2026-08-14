class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://www.juhe.cn/docs/api/id/29"
  url "file://#{File.expand_path("../dist/aurumbar-0.1.0.tar.gz", __dir__)}"
  sha256 "c04f5d5bfdc808b1c9352d4ff518cc463d43f276b4664c8a2011e940ef11e773"
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
