#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || {
  echo "Usage: scripts/verify-release.sh ARCHIVE MANIFEST" >&2
  exit 64
}
ARCHIVE=$1
MANIFEST=$2
[[ -f "$ARCHIVE" && -f "$MANIFEST" ]] || {
  echo "Archive or manifest not found" >&2
  exit 1
}

VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")
EXPECTED_SHA=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$MANIFEST")
ACTUAL_SHA=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || {
  echo "Checksum mismatch" >&2
  exit 1
}
[[ $(basename "$ARCHIVE") == "aurumbar-$VERSION.tar.gz" ]] || {
  echo "Archive name does not match manifest version" >&2
  exit 1
}

python3 - "$ARCHIVE" <<'PY'
import sys
import tarfile

archive = sys.argv[1]
allowed = {"aurumbar", "LICENSE", "README.md"}
with tarfile.open(archive, "r:gz") as source:
    members = source.getmembers()
    names = {member.name for member in members}
    if names != allowed:
        raise SystemExit(f"Unexpected archive contents: {sorted(names)}")
    for member in members:
        if member.name.startswith("/") or ".." in member.name.split("/"):
            raise SystemExit(f"Unsafe archive path: {member.name}")
        if member.issym() or member.islnk():
            raise SystemExit(f"Links are not allowed: {member.name}")
PY

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP"
xcrun lipo "$TMP/aurumbar" -verify_arch arm64 x86_64
[[ $("$TMP/aurumbar" --version) == "AurumBar $VERSION" ]] || {
  echo "Binary version does not match manifest" >&2
  exit 1
}
codesign --verify --strict --verbose=2 "$TMP/aurumbar"

echo "Verified $ARCHIVE"
