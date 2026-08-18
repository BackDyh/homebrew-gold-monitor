#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build-release.sh VERSION [--allow-dirty] [--signing unsigned|developer-id]

Builds a universal AurumBar release candidate under .build/release-artifacts/VERSION.
Developer ID mode requires AURUMBAR_CODESIGN_IDENTITY and a configured notarytool
keychain profile named by AURUMBAR_NOTARY_PROFILE.
USAGE
}

[[ $# -ge 1 ]] || { usage >&2; exit 64; }
VERSION=$1
shift
ALLOW_DIRTY=false
SIGNING=unsigned
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty) ALLOW_DIRTY=true ;;
    --signing)
      shift
      [[ $# -gt 0 ]] || { usage >&2; exit 64; }
      SIGNING=$1
      ;;
    *) usage >&2; exit 64 ;;
  esac
  shift
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid version: $VERSION" >&2
  exit 64
}
[[ "$SIGNING" == "unsigned" || "$SIGNING" == "developer-id" ]] || {
  echo "Invalid signing mode: $SIGNING" >&2
  exit 64
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ -n $(git status --porcelain --untracked-files=all) && "$ALLOW_DIRTY" != true ]]; then
  echo "Working tree is dirty; commit changes or pass --allow-dirty." >&2
  exit 1
fi

OUTPUT_ROOT="$ROOT/.build/release-artifacts"
SCRATCH_ROOT="$ROOT/.build/release-scratch"
mkdir -p "$OUTPUT_ROOT" "$SCRATCH_ROOT"
OUTPUT=$(mktemp -d "$OUTPUT_ROOT/$VERSION.XXXXXX")
SCRATCH=$(mktemp -d "$SCRATCH_ROOT/$VERSION.XXXXXX")
STAGING="$SCRATCH/staging"
mkdir -p "$STAGING"

for ARCH in arm64 x86_64; do
  swift build \
    -c release \
    --product aurumbar \
    --scratch-path "$SCRATCH/$ARCH" \
    --triple "$ARCH-apple-macosx13.0"
done

xcrun lipo -create \
  "$SCRATCH/arm64/$([ -d "$SCRATCH/arm64/arm64-apple-macosx/release" ] && echo arm64-apple-macosx/release || echo release)/aurumbar" \
  "$SCRATCH/x86_64/$([ -d "$SCRATCH/x86_64/x86_64-apple-macosx/release" ] && echo x86_64-apple-macosx/release || echo release)/aurumbar" \
  -output "$STAGING/aurumbar"
xcrun lipo "$STAGING/aurumbar" -verify_arch arm64 x86_64
chmod 0755 "$STAGING/aurumbar"

ACTUAL_VERSION=$("$STAGING/aurumbar" --version)
[[ "$ACTUAL_VERSION" == "AurumBar $VERSION" ]] || {
  echo "Version mismatch: expected AurumBar $VERSION, got $ACTUAL_VERSION" >&2
  exit 1
}

NOTARIZED=false
if [[ "$SIGNING" == "developer-id" ]]; then
  : "${AURUMBAR_CODESIGN_IDENTITY:?Set AURUMBAR_CODESIGN_IDENTITY}"
  : "${AURUMBAR_NOTARY_PROFILE:?Set AURUMBAR_NOTARY_PROFILE}"
  codesign --force --options runtime --timestamp \
    --sign "$AURUMBAR_CODESIGN_IDENTITY" "$STAGING/aurumbar"
  codesign --verify --strict --verbose=2 "$STAGING/aurumbar"
  ditto -c -k --keepParent "$STAGING/aurumbar" "$SCRATCH/notary.zip"
  xcrun notarytool submit "$SCRATCH/notary.zip" \
    --keychain-profile "$AURUMBAR_NOTARY_PROFILE" --wait
  NOTARIZED=true
else
  codesign --force --sign - "$STAGING/aurumbar"
  codesign --verify --strict --verbose=2 "$STAGING/aurumbar"
fi

cp LICENSE README.md "$STAGING/"
chmod 0644 "$STAGING/LICENSE" "$STAGING/README.md"
COMMIT=$(git rev-parse HEAD)
DIRTY=false
[[ -n $(git status --porcelain --untracked-files=all) ]] && DIRTY=true
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD)}
ARCHIVE="aurumbar-$VERSION.tar.gz"

python3 - "$STAGING" "$OUTPUT/$ARCHIVE" "$SOURCE_DATE_EPOCH" <<'PY'
import gzip
import io
import os
import sys
import tarfile

staging, output, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
entries = [("aurumbar", 0o755), ("LICENSE", 0o644), ("README.md", 0o644)]
raw = io.BytesIO()
with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as archive:
    for name, mode in entries:
        path = os.path.join(staging, name)
        info = archive.gettarinfo(path, arcname=name)
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mode = mode
        info.mtime = epoch
        with open(path, "rb") as source:
            archive.addfile(info, source)
with open(output, "wb") as destination:
    with gzip.GzipFile(filename="", mode="wb", fileobj=destination, mtime=epoch) as compressed:
        compressed.write(raw.getvalue())
PY

SHA=$(shasum -a 256 "$OUTPUT/$ARCHIVE" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA" "$ARCHIVE" > "$OUTPUT/$ARCHIVE.sha256"
cat > "$OUTPUT/manifest.json" <<EOF
{
  "version": "$VERSION",
  "gitCommit": "$COMMIT",
  "dirty": $DIRTY,
  "architectures": ["arm64", "x86_64"],
  "signing": "$SIGNING",
  "notarized": $NOTARIZED,
  "archive": "$ARCHIVE",
  "sha256": "$SHA",
  "swiftVersion": "$(swift --version | head -1)",
  "xcodeVersion": "$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'Command Line Tools')"
}
EOF

"$ROOT/scripts/verify-release.sh" "$OUTPUT/$ARCHIVE" "$OUTPUT/manifest.json"
"$ROOT/scripts/render-formula.sh" \
  "$VERSION" "$OUTPUT/$ARCHIVE" "$OUTPUT/aurumbar.rb"
echo "Release candidate: $OUTPUT/$ARCHIVE"
