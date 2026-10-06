#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${VERSION:-1.0.0}
bash scripts/build-app.sh --universal
ARCHIVE="MacPulse-$VERSION-universal.zip"
ditto -c -k --sequesterRsrc --keepParent dist/MacPulse.app "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Release: dist/$ARCHIVE"
