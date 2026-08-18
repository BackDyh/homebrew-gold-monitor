#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || {
  echo "Usage: scripts/render-formula.sh VERSION ARCHIVE OUTPUT" >&2
  exit 64
}
VERSION=$1
ARCHIVE=$2
OUTPUT=$3
[[ -f "$ARCHIVE" ]] || { echo "Archive not found: $ARCHIVE" >&2; exit 1; }
SHA=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
cat > "$OUTPUT" <<EOF
class Aurumbar < Formula
  desc "Native macOS menu bar monitor for Au99.99 gold prices"
  homepage "https://github.com/BackDyh/homebrew-gold-monitor"
  url "https://github.com/BackDyh/homebrew-gold-monitor/releases/download/v${VERSION}/aurumbar-${VERSION}.tar.gz"
  sha256 "${SHA}"
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
EOF
ruby -c "$OUTPUT"
echo "Candidate Formula: $OUTPUT"
